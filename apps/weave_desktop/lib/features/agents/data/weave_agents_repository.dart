import 'package:weave_agents/weave_agents.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../domain/agents_repository.dart';
import '../domain/terminal_launcher.dart';

/// Reads agent definitions and availability through [WeaveServices].
final class WeaveAgentsRepository implements AgentsRepository {
  const WeaveAgentsRepository(this._services, this._terminal);

  final WeaveServices _services;
  final TerminalLauncher _terminal;

  @override
  List<AgentAdapter> get agents => _services.agents.adapters.toList(growable: false);

  @override
  String get configurationPath => agentsFilePath(_services.paths);

  @override
  Future<List<AgentAvailability>> checkAvailability() => Future.wait(<Future<AgentAvailability>>[for (final AgentAdapter adapter in agents) adapter.checkAvailability()]);

  @override
  Future<Set<String>> customAgentIds() async => <String>{for (final AgentDefinition definition in await loadCustomAgents(_services.paths)) definition.id};

  @override
  Future<void> saveAgent(AgentDefinition definition) async {
    await saveCustomAgent(_services.paths, definition);
    await _services.reloadAgents();
  }

  @override
  Future<void> removeAgent(String agentId) async {
    await removeCustomAgent(_services.paths, agentId);
    await _services.reloadAgents();
  }

  @override
  Future<AgentPlanUsage> readPlanUsage(String agentId) {
    final AgentAdapter? adapter = _services.agents[agentId];
    if (adapter == null) {
      throw AgentPlanUsageException('$agentId is not configured.');
    }
    return adapter.readPlanUsage();
  }

  @override
  Future<AgentAccount> addAccount(String agentId, String name) async {
    final AgentAccount account = await addAgentAccount(_services.paths, agentId: agentId, name: name, takenIds: _services.agents.ids.toSet());
    await _services.reloadAgents();
    return account;
  }

  @override
  Future<void> removeAccount(String accountId) async {
    await removeAgentAccount(_services.paths, accountId);
    await _services.reloadAgents();
  }

  @override
  Future<AgentAccountInfo?> readAccount(String agentId) async => _services.agents[agentId]?.readAccount();

  @override
  Future<bool> isInstalled(String executable) async => await AgentExecutableLocator(environment: _services.environment).locate(executable) != null;

  @override
  Future<void> openInTerminal(String command, {required String name}) => _terminal.run(command, name: name);
}
