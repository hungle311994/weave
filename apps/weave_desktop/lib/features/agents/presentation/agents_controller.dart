import 'package:flutter/foundation.dart';
import 'package:weave_agents/weave_agents.dart';

import '../domain/agents_repository.dart';

/// Loads agent availability for agent-related screens and selectors.
final class AgentsController extends ChangeNotifier {
  AgentsController(this._repository);

  final AgentsRepository _repository;
  final Map<String, AgentAvailability> _availability = <String, AgentAvailability>{};
  final Map<String, AgentPlanUsage> _planUsage = <String, AgentPlanUsage>{};
  final Map<String, String> _planUsageErrors = <String, String>{};
  final Map<String, AgentAccountInfo> _accounts = <String, AgentAccountInfo>{};
  Future<void>? _refresh;
  Future<void>? _queued;
  bool _refreshingPlanUsage = false;
  bool _disposed = false;
  bool _planUsageRead = false;
  Set<String> _customIds = const <String>{};

  /// Every agent, each extra account right after the agent it belongs to.
  List<AgentAdapter> get agents {
    final List<AgentAdapter> all = _repository.agents;
    final Map<String, int> order = <String, int>{for (final (int index, AgentAdapter adapter) in all.indexed) adapter.id: index};
    final List<(int, int, AgentAdapter)> ranked = <(int, int, AgentAdapter)>[for (final (int index, AgentAdapter adapter) in all.indexed) (order[adapter.account?.agentId] ?? index, index, adapter)]..sort(((int, int, AgentAdapter) a, (int, int, AgentAdapter) b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return <AgentAdapter>[for (final (int _, int _, AgentAdapter adapter) in ranked) adapter];
  }

  String get configurationPath => _repository.configurationPath;

  AgentAvailability? availabilityOf(String agentId) => _availability[agentId];

  bool get refreshing => _refresh != null;

  /// Who [agentId] is signed in as, when its CLI reports it.
  AgentAccountInfo? accountOf(String agentId) => _accounts[agentId];

  /// Adds an account named [name] of [agentId] and opens its sign-in in
  /// Terminal. Returns the new account.
  Future<AgentAccount> addAccount(String agentId, String name) async {
    final AgentAccount account = await _repository.addAccount(agentId, name);
    await refresh();
    await signIn(account.id);
    return account;
  }

  /// Removes an extra account; its configuration folder, and so its
  /// sign-in on this Mac, goes with it.
  Future<void> removeAccount(String accountId) async {
    await _repository.removeAccount(accountId);
    _forget(accountId);
    await refresh();
  }

  /// Whether [executable] is found on this Mac.
  Future<bool> isInstalled(String executable) => _repository.isInstalled(executable);

  /// Opens [agentId]'s sign-in command in Terminal; `false` when it has none.
  Future<bool> signIn(String agentId) async {
    final String? command = _availability[agentId]?.signInCommand;
    if (command == null) {
      return false;
    }
    await _repository.openInTerminal(command, name: 'sign-in-$agentId');
    return true;
  }

  void _forget(String agentId) {
    _availability.remove(agentId);
    _planUsage.remove(agentId);
    _planUsageErrors.remove(agentId);
    _accounts.remove(agentId);
  }

  /// Whether [agentId] comes from `agents.json` and can be removed.
  bool isCustom(String agentId) => _customIds.contains(agentId);

  /// Saves [definition] to `agents.json`, then re-checks every agent.
  Future<void> addAgent(AgentDefinition definition) async {
    await _repository.saveAgent(definition);
    await refresh();
  }

  Future<void> removeAgent(String agentId) async {
    await _repository.removeAgent(agentId);
    _forget(agentId);
    await refresh();
  }

  /// Plan limits last read from [agentId]'s CLI, if any.
  AgentPlanUsage? planUsageOf(String agentId) => _planUsage[agentId];

  /// Why the last plan usage read for [agentId] failed.
  String? planUsageErrorOf(String agentId) => _planUsageErrors[agentId];

  bool get refreshingPlanUsage => _refreshingPlanUsage;

  /// Agents that are ready and can report plan usage.
  List<AgentAdapter> get planUsageAgents => <AgentAdapter>[
    for (final AgentAdapter adapter in agents)
      if (adapter.reportsPlanUsage && (_availability[adapter.id]?.isAvailable ?? false)) adapter,
  ];

  /// Reads plan usage the first time the Agents screen opens after launch;
  /// later visits keep the last values until the user refreshes them.
  Future<void> ensurePlanUsage() => _planUsageRead ? Future<void>.value() : refreshPlanUsage();

  /// Re-reads plan usage for every ready agent that reports it, in parallel.
  /// Reading it runs the agent's local usage command, never a model.
  Future<void> refreshPlanUsage() async {
    if (_refreshingPlanUsage) {
      return;
    }
    _planUsageRead = true;
    _refreshingPlanUsage = true;
    _notify();
    try {
      if (_availability.isEmpty) {
        await refresh();
      }
      await Future.wait(<Future<void>>[
        for (final AgentAdapter adapter in planUsageAgents)
          _repository
              .readPlanUsage(adapter.id)
              .then(
                (AgentPlanUsage usage) {
                  _planUsage[adapter.id] = usage;
                  _planUsageErrors.remove(adapter.id);
                },
                onError: (Object error) {
                  _planUsageErrors[adapter.id] = error is AgentPlanUsageException ? error.message : 'Could not read usage: $error';
                },
              ),
      ]);
    } finally {
      _refreshingPlanUsage = false;
      _notify();
    }
  }

  bool get hasReadyAgent => _availability.values.any((AgentAvailability availability) => availability.isAvailable);

  bool get needsSetup => _availability.isNotEmpty && !hasReadyAgent;

  /// Checks whether every agent is installed and signed in, and who it is
  /// signed in as; local commands only, no model. While a check runs, one
  /// more is queued after it, so a caller always sees results newer than its call.
  Future<void> refresh() {
    if (_refresh case final Future<void> running) {
      return _queued ??= running.then((void _) {
        _queued = null;
        return refresh();
      });
    }
    return _refresh = _check().whenComplete(() {
      _refresh = null;
      _notify();
    });
  }

  Future<void> _check() async {
    _notify();
    // In the repository's order, which checkAvailability's results follow.
    // Read before agents.json: a save writes the file before it reloads the
    // agents, so the custom IDs are never older than this list.
    final List<AgentAdapter> adapters = _repository.agents;
    _customIds = await _repository.customAgentIds();
    final List<AgentAvailability> results = await _repository.checkAvailability();
    for (int index = 0; index < adapters.length; index++) {
      _availability[adapters[index].id] = results[index];
    }
    // Show sign-in states now; account details can take a moment longer.
    _notify();
    await Future.wait(<Future<void>>[
      for (final AgentAdapter adapter in adapters)
        if (_availability[adapter.id]?.isAvailable ?? false)
          _repository.readAccount(adapter.id).then((AgentAccountInfo? info) {
            if (info == null) {
              _accounts.remove(adapter.id);
            } else {
              _accounts[adapter.id] = info;
            }
          })
        else
          Future<void>.sync(() => _accounts.remove(adapter.id)),
    ]);
  }

  /// Checks and usage reads finish after the screen may have closed.
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
