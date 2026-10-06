import 'package:flutter/material.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../weave_controller.dart';

/// Form that configures and starts a workflow.
class NewWorkflowView extends StatefulWidget {
  const NewWorkflowView({required this.controller, super.key});

  final WeaveController controller;

  @override
  State<NewWorkflowView> createState() => _NewWorkflowViewState();
}

class _NewWorkflowViewState extends State<NewWorkflowView> {
  final TextEditingController _repository = TextEditingController();
  final TextEditingController _request = TextEditingController();
  final TextEditingController _verification = TextEditingController();
  final Map<AgentRole, String?> _agents = <AgentRole, String?>{for (final AgentRole role in AgentRole.values) role: null};
  int _maxReviews = 3;
  final Set<String> _mcpServerIds = <String>{};
  final TextEditingController _maxTokens = TextEditingController();
  final Map<AgentRole, TextEditingController> _models = <AgentRole, TextEditingController>{for (final AgentRole role in AgentRole.values) role: TextEditingController()};
  final Map<AgentRole, String?> _fallbacks = <AgentRole, String?>{for (final AgentRole role in AgentRole.values) role: null};
  bool _approvePlan = false;
  bool _approveChanges = false;
  bool _reviewPlan = false;
  bool _saveAsDefaults = false;
  String? _repositoryRoot;
  String? _error;
  bool _busy = false;

  /// Changes on every load so dropdowns pick up the loaded settings.
  int _loadGeneration = 0;

  WeaveController get _controller => widget.controller;

  @override
  void dispose() {
    _repository.dispose();
    _request.dispose();
    _verification.dispose();
    _maxTokens.dispose();
    for (final TextEditingController model in _models.values) {
      model.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRepository() async {
    final String directory = _repository.text.trim();
    if (directory.isEmpty) {
      setState(() => _error = 'Enter the path of a Git repository.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (String root, WorkflowSettings settings) = await _controller.loadRepository(directory);
      if (!mounted) {
        return;
      }
      setState(() {
        _repositoryRoot = root;
        _repository.text = root;
        for (final AgentRole role in AgentRole.values) {
          _agents[role] = settings.assignments.agentIdFor(role);
        }
        _verification.text = settings.verificationCommands.map((VerificationCommand command) => _commandLine(command)).join('\n');
        _maxReviews = settings.maxReviewCycles;
        _mcpServerIds
          ..clear()
          ..addAll(settings.mcpServerIds);
        _approvePlan = settings.requirePlanApproval;
        _approveChanges = settings.requireChangesApproval;
        _reviewPlan = settings.reviewPlan;
        _maxTokens.text = settings.maxTokens?.toString() ?? '';
        for (final AgentRole role in AgentRole.values) {
          _models[role]!.text = settings.modelOverrides[role] ?? '';
          _fallbacks[role] = settings.fallbackAgentIds[role]?.firstOrNull;
        }
        _loadGeneration++;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _repositoryRoot = null;
          _error = _describe(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _start() async {
    if (_repositoryRoot == null || _repositoryRoot != _repository.text.trim()) {
      await _loadRepository();
      if (_repositoryRoot == null) {
        return;
      }
    }
    final String request = _request.text.trim();
    if (request.isEmpty) {
      setState(() => _error = 'Describe the change to make.');
      return;
    }
    if (_agents.values.any((String? id) => id == null)) {
      setState(() => _error = 'Choose an agent for every role.');
      return;
    }

    final List<McpServerDefinition> suggestions = _controller.mcpSuggestions(request, _mcpServerIds);
    if (suggestions.isNotEmpty) {
      if (!mounted) {
        return;
      }
      final _McpChoice? choice = await showDialog<_McpChoice>(
        context: context,
        builder: (BuildContext context) => _McpSuggestionDialog(suggestions: suggestions),
      );
      if (choice == null || !mounted) {
        return;
      }
      if (choice.server case final McpServerDefinition server) {
        setState(() => _mcpServerIds.add(server.id));
      }
    }

    final String maxTokensText = _maxTokens.text.trim();
    final int? maxTokens = maxTokensText.isEmpty ? null : int.tryParse(maxTokensText);
    if (maxTokensText.isNotEmpty && (maxTokens == null || maxTokens < 1)) {
      setState(() => _error = 'The token budget must be a positive number, or empty for no limit.');
      return;
    }

    final WorkflowSettings settings;
    try {
      settings = WorkflowSettings(
        assignments: AgentAssignments(plannerAgentId: _agents[AgentRole.planner]!, implementerAgentId: _agents[AgentRole.implementer]!, reviewerAgentId: _agents[AgentRole.reviewer]!),
        verificationCommands: <VerificationCommand>[
          for (final String line in _verification.text.split('\n'))
            if (line.trim().isNotEmpty) VerificationCommand.parse(line),
        ],
        maxReviewCycles: _maxReviews,
        mcpServerIds: _mcpServerIds.toList(),
        modelOverrides: <AgentRole, String>{for (final AgentRole role in AgentRole.values) role: _models[role]!.text},
        fallbackAgentIds: <AgentRole, List<String>>{
          for (final AgentRole role in AgentRole.values)
            if (_fallbacks[role] case final String fallback) role: <String>[fallback],
        },
        requirePlanApproval: _approvePlan,
        requireChangesApproval: _approveChanges,
        reviewPlan: _reviewPlan,
        maxTokens: maxTokens,
      );
    } on FormatException catch (error) {
      setState(() => _error = 'Verification command: ${error.message}');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _controller.startWorkflow(request: request, repositoryPath: _repositoryRoot!, settings: settings, saveAsDefaults: _saveAsDefaults);
      if (mounted) {
        _request.clear();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _describe(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> recentRepositories = <String>{for (final WorkflowTask task in _controller.tasks) task.repositoryPath}.take(5).toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        if (_controller.needsSetup)
          Card(
            key: const Key('setup-banner'),
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.rocket_launch_outlined),
              title: const Text('Set up a coding agent first'),
              subtitle: const Text('No agent is ready. Install Claude Code, Codex, or another CLI agent and sign in to it; Weave uses the agent\'s own sign-in and never asks for passwords.'),
              trailing: FilledButton(onPressed: () => _controller.select(const AgentsSelection()), child: const Text('Open Agents')),
            ),
          ),
        Text('New workflow', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('The planner writes a plan, the implementer edits the code and reviews its own work, Weave runs your checks, and the reviewer approves or sends it back.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('repository'),
                controller: _repository,
                decoration: InputDecoration(labelText: 'Repository', hintText: '/path/to/repository', border: const OutlineInputBorder(), helperText: _repositoryRoot == null ? null : 'Git repository loaded'),
                onSubmitted: (String _) => _loadRepository(),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(onPressed: _busy ? null : _loadRepository, child: const Text('Load')),
            ),
          ],
        ),
        if (recentRepositories.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final String repository in recentRepositories)
                ActionChip(
                  label: Text(repository, overflow: TextOverflow.ellipsis),
                  onPressed: () {
                    _repository.text = repository;
                    _loadRepository();
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          key: const Key('request'),
          controller: _request,
          minLines: 4,
          maxLines: 12,
          decoration: const InputDecoration(labelText: 'Request', hintText: 'What should change?', border: OutlineInputBorder(), alignLabelWithHint: true),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            for (final AgentRole role in AgentRole.values)
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  key: Key('agent-${role.name}-$_loadGeneration'),
                  isExpanded: true,
                  initialValue: _agents[role],
                  decoration: InputDecoration(labelText: _roleLabel(role), border: const OutlineInputBorder()),
                  items: <DropdownMenuItem<String>>[
                    for (final AgentAdapter adapter in _controller.agents)
                      DropdownMenuItem<String>(
                        value: adapter.id,
                        child: Text(_controller.availabilityOf(adapter.id)?.isAvailable == false ? '${adapter.displayName} (not installed)' : adapter.displayName, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (String? id) => setState(() => _agents[role] = id),
                ),
              ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<int>(
                key: Key('max-reviews-$_loadGeneration'),
                initialValue: _maxReviews,
                decoration: const InputDecoration(labelText: 'Max reviews', border: OutlineInputBorder()),
                items: <DropdownMenuItem<int>>[for (int count = 1; count <= 6; count++) DropdownMenuItem<int>(value: count, child: Text('$count'))],
                onChanged: (int? count) => setState(() => _maxReviews = count ?? _maxReviews),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('verification'),
          controller: _verification,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(fontFamily: 'Menlo'),
          decoration: const InputDecoration(labelText: 'Verification commands', hintText: 'One per line, e.g. fvm dart analyze', helperText: 'Run by Weave before every review, without a shell.', border: OutlineInputBorder(), alignLabelWithHint: true),
        ),
        const SizedBox(height: 16),
        Text('MCP servers', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final McpServerDefinition server in _controller.mcp.servers)
              FilterChip(
                key: Key('mcp-${server.id}'),
                label: Text(server.displayName),
                tooltip: server.setupHint,
                selected: _mcpServerIds.contains(server.id),
                onSelected: (bool selected) => setState(() => selected ? _mcpServerIds.add(server.id) : _mcpServerIds.remove(server.id)),
              ),
          ],
        ),
        ExpansionTile(
          key: const Key('advanced'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Checkpoints, budget, models, and fallbacks'),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: <Widget>[
            SwitchListTile(key: const Key('approve-plan'), contentPadding: EdgeInsets.zero, value: _approvePlan, onChanged: (bool value) => setState(() => _approvePlan = value), title: const Text('Pause for my approval of the plan')),
            SwitchListTile(key: const Key('approve-changes'), contentPadding: EdgeInsets.zero, value: _approveChanges, onChanged: (bool value) => setState(() => _approveChanges = value), title: const Text('Pause for my approval of the changes before review')),
            SwitchListTile(key: const Key('review-plan'), contentPadding: EdgeInsets.zero, value: _reviewPlan, onChanged: (bool value) => setState(() => _reviewPlan = value), title: const Text('Let the reviewer check the plan before implementation')),
            const SizedBox(height: 8),
            SizedBox(
              width: 260,
              child: TextField(
                key: const Key('max-tokens'),
                controller: _maxTokens,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Token budget (empty = no limit)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                for (final AgentRole role in AgentRole.values)
                  SizedBox(
                    width: 220,
                    child: Column(
                      children: <Widget>[
                        TextField(
                          controller: _models[role],
                          decoration: InputDecoration(labelText: '${_roleLabel(role)} model (optional)', border: const OutlineInputBorder()),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String?>(
                          key: Key('fallback-${role.name}-$_loadGeneration'),
                          isExpanded: true,
                          initialValue: _fallbacks[role],
                          decoration: InputDecoration(labelText: '${_roleLabel(role)} fallback', border: const OutlineInputBorder()),
                          items: <DropdownMenuItem<String?>>[
                            const DropdownMenuItem<String?>(child: Text('None')),
                            for (final AgentAdapter adapter in _controller.agents)
                              DropdownMenuItem<String?>(
                                value: adapter.id,
                                child: Text(adapter.displayName, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (String? id) => setState(() => _fallbacks[role] = id),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _saveAsDefaults,
          onChanged: (bool? value) => setState(() => _saveAsDefaults = value ?? false),
          title: const Text('Save these settings as defaults for this repository'),
        ),
        if (_error case final String error)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(error, style: TextStyle(color: theme.colorScheme.error)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('start'),
            onPressed: _busy ? null : _start,
            icon: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
            label: const Text('Start workflow'),
          ),
        ),
      ],
    );
  }

  static String _roleLabel(AgentRole role) => switch (role) {
    AgentRole.planner => 'Planner',
    AgentRole.implementer => 'Implementer',
    AgentRole.reviewer => 'Reviewer',
  };

  /// Quotes arguments so the line parses back to the same command.
  static String _commandLine(VerificationCommand command) => <String>[command.executable, ...command.arguments].map((String word) => word.isEmpty || word.contains(RegExp(r'''[\s"'\\|&;<>]''')) ? "'${word.replaceAll("'", r"'\''")}'" : word).join(' ');

  static String _describe(Object error) => switch (error) {
    WorkflowStartException(:final String message) => message,
    StateError(:final String message) => message,
    _ => error.toString(),
  };
}

/// The answer to an MCP offer: a server to enable, or none.
final class _McpChoice {
  const _McpChoice(this.server);

  final McpServerDefinition? server;
}

/// Offers MCP servers for links found in the request, e.g. Figma designs.
class _McpSuggestionDialog extends StatefulWidget {
  const _McpSuggestionDialog({required this.suggestions});

  final List<McpServerDefinition> suggestions;

  @override
  State<_McpSuggestionDialog> createState() => _McpSuggestionDialogState();
}

class _McpSuggestionDialogState extends State<_McpSuggestionDialog> {
  late McpServerDefinition _selected = widget.suggestions.first;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Use an MCP server?'),
    content: SizedBox(
      width: 480,
      child: RadioGroup<McpServerDefinition>(
        groupValue: _selected,
        onChanged: (McpServerDefinition? server) => setState(() => _selected = server ?? _selected),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('The request links to something an MCP server can open. Enable one so every agent can read it:'),
            const SizedBox(height: 8),
            for (final McpServerDefinition server in widget.suggestions)
              RadioListTile<McpServerDefinition>(
                key: Key('suggest-${server.id}'),
                value: server,
                title: Text(server.displayName),
                subtitle: server.setupHint == null ? null : Text(server.setupHint!),
              ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
      TextButton(key: const Key('mcp-skip'), onPressed: () => Navigator.of(context).pop(const _McpChoice(null)), child: const Text('Continue without')),
      FilledButton(key: const Key('mcp-enable'), onPressed: () => Navigator.of(context).pop(_McpChoice(_selected)), child: const Text('Enable and start')),
    ],
  );
}
