import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../../../core/design_system/design_system.dart';
import '../../agents/presentation/agents_controller.dart';
import '../../integrations/presentation/integrations_controller.dart';
import '../../workflow_run/presentation/dialogs/delete_workflow_dialog.dart';
import '../../workflow_run/presentation/workflow_controller.dart';
import '../domain/loaded_repository.dart';
import '../domain/repository_picker_platform.dart';
import 'dialogs/advanced_settings_dialog.dart';
import 'dialogs/agent_picker_dialog.dart';
import 'dialogs/repository_picker_dialog.dart';
import 'new_task_controller.dart';
import 'widgets/agent_pipeline_card.dart';

/// Form that configures and starts a workflow.
class NewTaskPage extends StatefulWidget {
  const NewTaskPage({required this.controller, required this.workflow, required this.agents, required this.integrations, required this.repositoryPicker, required this.onOpenAgents, required this.onOpenWorkflow, required this.subSidebarVisible, required this.onToggleSubSidebar, required this.onSubSidebarVisibilityChanged, super.key});

  final NewTaskController controller;
  final WorkflowController workflow;
  final AgentsController agents;
  final IntegrationsController integrations;
  final RepositoryPickerPlatform repositoryPicker;
  final VoidCallback onOpenAgents;
  final ValueChanged<String> onOpenWorkflow;
  final bool subSidebarVisible;
  final VoidCallback onToggleSubSidebar;
  final ValueChanged<bool> onSubSidebarVisibilityChanged;

  @override
  State<NewTaskPage> createState() => _NewTaskPageState();
}

class _NewTaskPageState extends State<NewTaskPage> {
  late final TextEditingController _request;
  late final TextEditingController _verification;
  late final TextEditingController _maxTokens;
  late final Map<AgentRole, String?> _agents;
  late final Map<AgentRole, TextEditingController> _models;
  late final Map<AgentRole, String?> _fallbacks;
  late final Set<String> _mcpServerIds;
  late int _maxReviews;
  late bool _approvePlan;
  late bool _approveChanges;
  late bool _reviewPlan;
  late bool _saveAsDefaults;

  /// The task's repositories by root, with their branch, in the order they
  /// were added; see [NewTaskDraft.repositories].
  late final Map<String, String?> _repositories;
  bool _busy = false;
  double? _draggedSidebarWidth;
  Set<AgentRole> _missingAgentRoles = <AgentRole>{};

  NewTaskController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final NewTaskDraft draft = _controller.draft;
    _request = TextEditingController(text: draft.request);
    _verification = TextEditingController(text: draft.verification);
    _maxTokens = TextEditingController(text: draft.maxTokens);
    _agents = Map<AgentRole, String?>.of(draft.agents);
    _models = <AgentRole, TextEditingController>{for (final AgentRole role in AgentRole.values) role: TextEditingController(text: draft.models[role] ?? '')};
    _fallbacks = Map<AgentRole, String?>.of(draft.fallbacks);
    _mcpServerIds = Set<String>.of(draft.mcpServerIds);
    _maxReviews = draft.maxReviews;
    _approvePlan = draft.approvePlan;
    _approveChanges = draft.approveChanges;
    _reviewPlan = draft.reviewPlan;
    _saveAsDefaults = draft.saveAsDefaults;
    _repositories = Map<String, String?>.of(draft.repositories);
  }

  @override
  void dispose() {
    _saveDraft();
    _request.dispose();
    _verification.dispose();
    _maxTokens.dispose();
    for (final TextEditingController model in _models.values) {
      model.dispose();
    }
    super.dispose();
  }

  void _saveDraft() {
    final NewTaskDraft draft = _controller.draft;
    draft.request = _request.text;
    draft.verification = _verification.text;
    draft.maxTokens = _maxTokens.text;
    for (final AgentRole role in AgentRole.values) {
      draft.agents[role] = _agents[role];
      draft.models[role] = _models[role]!.text;
      draft.fallbacks[role] = _fallbacks[role];
    }
    draft.mcpServerIds
      ..clear()
      ..addAll(_mcpServerIds);
    draft.maxReviews = _maxReviews;
    draft.approvePlan = _approvePlan;
    draft.approveChanges = _approveChanges;
    draft.reviewPlan = _reviewPlan;
    draft.saveAsDefaults = _saveAsDefaults;
    draft.repositories
      ..clear()
      ..addAll(_repositories);
  }

  /// Every New Task problem is reported as a toast.
  void _showError(String message) {
    if (mounted) {
      showWeaveToast(context, message: message, tone: WeaveToastTone.danger);
    }
  }

  /// Adds a repository the agents may read and, if allowed after planning,
  /// edit. The first one also brings its saved settings, except the agents,
  /// which the user always chooses.
  Future<void> _addRepository() async {
    final LoadedRepository? loaded = await _pickRepository();
    if (loaded == null || !mounted) {
      return;
    }
    if (_repositories.containsKey(loaded.root)) {
      _showError('${path.basename(loaded.root)} is already part of this task.');
      return;
    }
    setState(() {
      if (_repositories.isEmpty) {
        _applyRepositorySettings(loaded.settings);
      }
      _repositories[loaded.root] = loaded.branch;
    });
    _saveDraft();
  }

  Future<LoadedRepository?> _pickRepository() {
    final List<String> recentRepositories = <String>{
      for (final WorkflowTask task in widget.workflow.tasks)
        for (final String repository in task.repositoryPaths)
          if (!_repositories.containsKey(repository)) repository,
    }.take(5).toList(growable: false);
    return showRepositoryPickerDialog(
      context: context,
      recentRepositories: recentRepositories,
      initialPath: '',
      platform: widget.repositoryPicker,
      loadRepository: _controller.loadRepository,
      cloneRepository: (String url, String parentDirectory) => _controller.cloneRepository(url, parentDirectory: parentDirectory),
    );
  }

  /// Verification, checkpoints, limits and MCP servers saved for a repository.
  void _applyRepositorySettings(WorkflowSettings settings) {
    _verification.text = settings.verificationCommands.map((VerificationCommand command) => _commandLine(command)).join('\n');
    _maxReviews = settings.maxReviewCycles;
    _mcpServerIds
      ..clear()
      ..addAll(settings.mcpServerIds);
    _approvePlan = settings.requirePlanApproval;
    _approveChanges = settings.requireChangesApproval;
    _reviewPlan = settings.reviewPlan;
    _maxTokens.text = settings.maxTokens?.toString() ?? '';
  }

  Future<void> _chooseAgent(AgentRole role) async {
    final AgentPickerResult? result = await showAgentPickerDialog(
      context: context,
      roleLabel: _roleLabel(role),
      agents: widget.agents,
      selectedAgentId: _agents[role],
      model: _models[role]!.text,
      fallbackAgentId: _fallbacks[role],
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _agents[role] = result.agentId;
      _models[role]!.text = result.model ?? '';
      _fallbacks[role] = result.fallbackAgentId;
      _missingAgentRoles.remove(role);
    });
    _saveDraft();
  }

  void _clearAgent(AgentRole role) {
    setState(() {
      _agents[role] = null;
      _models[role]!.clear();
      _fallbacks[role] = null;
    });
    _saveDraft();
  }

  Future<bool> _openAdvancedSettings() async {
    final AdvancedSettingsResult? result = await showAdvancedSettingsDialog(
      context: context,
      maxReviewCycles: _maxReviews,
      verificationCommands: _verification.text,
      mcpServers: widget.integrations.servers,
      selectedMcpServerIds: _mcpServerIds,
      requirePlanApproval: _approvePlan,
      requireChangesApproval: _approveChanges,
      reviewPlan: _reviewPlan,
      maxTokens: _maxTokens.text,
      saveAsDefaults: _saveAsDefaults,
      confirmLabel: 'Start workflow',
    );
    if (result == null || !mounted) {
      return false;
    }
    setState(() {
      _maxReviews = result.maxReviewCycles;
      _verification.text = result.verificationCommands;
      _mcpServerIds
        ..clear()
        ..addAll(result.mcpServerIds);
      _approvePlan = result.requirePlanApproval;
      _approveChanges = result.requireChangesApproval;
      _reviewPlan = result.reviewPlan;
      _maxTokens.text = result.maxTokens?.toString() ?? '';
      _saveAsDefaults = result.saveAsDefaults;
    });
    _saveDraft();
    return true;
  }

  Future<void> _start() async {
    if (_repositories.isEmpty) {
      _showError('Add the repository this task works on.');
      return;
    }
    final String request = _request.text.trim();
    if (request.isEmpty) {
      _showError('Describe the change to make.');
      return;
    }
    final Set<AgentRole> missingRoles = <AgentRole>{
      for (final AgentRole role in AgentRole.values)
        if (_agents[role] == null) role,
    };
    if (missingRoles.isNotEmpty) {
      setState(() => _missingAgentRoles = missingRoles);
      _showError('Choose an agent for ${missingRoles.map(_roleLabel).join(', ')}.');
      return;
    }

    if (!await _openAdvancedSettings() || !mounted) {
      return;
    }

    final List<McpServerDefinition> suggestions = widget.integrations.suggestionsFor(request, _mcpServerIds);
    if (suggestions.isNotEmpty) {
      final _McpChoice? choice = await _showMcpSuggestion(suggestions);
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
      _showError('The token budget must be a positive number, or empty for no limit.');
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
        modelOverrides: <AgentRole, String>{
          for (final AgentRole role in AgentRole.values)
            if (_models[role]!.text.trim().isNotEmpty) role: _models[role]!.text.trim(),
        },
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
      _showError('Verification command: ${error.message}');
      return;
    }

    setState(() => _busy = true);
    try {
      // The first repository is the agents' working directory and where
      // verification runs; the user decides after planning which ones change.
      final List<String> repositories = _repositories.keys.toList(growable: false);
      await _controller.startWorkflow(request: request, repositoryPath: repositories.first, additionalRepositoryPaths: repositories.skip(1).toList(growable: false), settings: settings, saveAsDefaults: _saveAsDefaults);
      if (mounted) {
        _request.clear();
        _controller.draft.clearStartedRequest();
        _saveDraft();
      }
    } on Object catch (error) {
      if (mounted) {
        _showError(_describe(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<_McpChoice?> _showMcpSuggestion(List<McpServerDefinition> suggestions) {
    McpServerDefinition selected = suggestions.first;
    return showWeaveDialog<_McpChoice>(
      context: context,
      title: 'Use an MCP server?',
      subtitle: 'The request mentions content an MCP server may be able to open.',
      body: StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) => Column(
          children: <Widget>[
            for (final McpServerDefinition server in suggestions) ...<Widget>[
              WeaveCard(
                key: Key('suggest-${server.id}'),
                surface: selected.id == server.id ? WeaveSurface.selected : WeaveSurface.elevated,
                padding: const EdgeInsets.all(WeaveSpacing.s16),
                onTap: () => setDialogState(() => selected = server),
                child: Row(
                  children: <Widget>[
                    const WeaveIcon(WeaveIcons.squareSlash, size: WeaveSpacing.s24),
                    const SizedBox(width: WeaveSpacing.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(server.displayName, style: WeaveTypography.bodyStrong),
                          if (server.setupHint case final String hint) Text(hint, style: WeaveTypography.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: WeaveSpacing.s10),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        WeaveButton(key: const Key('mcp-skip'), label: 'Continue without', onPressed: () => Navigator.of(context).pop(const _McpChoice(null))),
        WeaveButton.primary(key: const Key('mcp-enable'), label: 'Enable and start', onPressed: () => Navigator.of(context).pop(_McpChoice(selected))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool dragging = _draggedSidebarWidth != null;
    final bool sidebarFits = MediaQuery.sizeOf(context).width >= WeaveLayout.sidebarExpandBreakpoint;
    final bool sidebarVisible = widget.subSidebarVisible && sidebarFits;
    final double sidebarWidth = _draggedSidebarWidth ?? (sidebarVisible ? WeaveLayout.contextualSidebarWidth : 0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AnimatedContainer(
          key: const Key('home-sub-sidebar'),
          width: sidebarWidth,
          duration: dragging || !sidebarFits ? WeaveMotion.instant : WeaveMotion.standard,
          curve: WeaveMotion.curve,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: WeaveLayout.contextualSidebarWidth,
              maxWidth: WeaveLayout.contextualSidebarWidth,
              child: SizedBox(
                width: WeaveLayout.contextualSidebarWidth,
                child: HomeSidebarContent(workflow: widget.workflow, onOpenWorkflow: widget.onOpenWorkflow),
              ),
            ),
          ),
        ),
        WeaveSidebarResizeHandle(
          key: const Key('home-sub-sidebar-handle'),
          expanded: sidebarVisible,
          onToggle: widget.onToggleSubSidebar,
          onDragStart: (DragStartDetails details) => setState(() => _draggedSidebarWidth = sidebarVisible ? WeaveLayout.contextualSidebarWidth : 0),
          onDragUpdate: (DragUpdateDetails details) {
            setState(() {
              _draggedSidebarWidth = ((_draggedSidebarWidth ?? 0) + details.delta.dx).clamp(0, WeaveLayout.contextualSidebarMaxWidth).toDouble();
            });
          },
          onDragEnd: (DragEndDetails details) {
            final bool visible = (_draggedSidebarWidth ?? 0) >= WeaveLayout.contextualSidebarBreakpoint;
            setState(() => _draggedSidebarWidth = null);
            widget.onSubSidebarVisibilityChanged(visible);
          },
        ),
        Expanded(
          child: SingleChildScrollView(
            key: const Key('new-task-main'),
            padding: const EdgeInsets.fromLTRB(WeaveLayout.pageGutter, WeaveLayout.windowContentTopPadding, WeaveSpacing.s28, WeaveSpacing.s40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Align(
                  alignment: Alignment.topLeft,
                  child: WeaveBreadcrumb(key: Key('new-task-breadcrumb'), items: <String>['Home', 'New task']),
                ),
                const SizedBox(height: WeaveSpacing.s12),
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    key: const Key('new-task-content'),
                    constraints: const BoxConstraints(maxWidth: WeaveLayout.newTaskFormWidth),
                    child: _buildForm(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (widget.agents.needsSetup) ...<Widget>[
        WeaveCard(
          key: const Key('setup-banner'),
          borderColor: WeaveColors.amber,
          child: Row(
            children: <Widget>[
              const WeaveIcon(WeaveIcons.alertTriangle, color: WeaveColors.amber),
              const SizedBox(width: WeaveSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Set up a coding agent first', style: WeaveTypography.titleSmall),
                    Text('Install a CLI agent and sign in to it. Weave uses the agent\'s own sign-in.', style: WeaveTypography.bodySmall),
                  ],
                ),
              ),
              WeaveButton(label: 'Open Agents', onPressed: widget.onOpenAgents),
            ],
          ),
        ),
        const SizedBox(height: WeaveSpacing.s20),
      ],
      const WeavePageHeader(
        breadcrumb: <String>[],
        title: 'What should Weave build?',
        subtitle: 'Describe your task and Weave will plan, implement, review, and verify it with the right agents.',
      ),
      const SizedBox(height: WeaveSpacing.s24),
      Text('Repositories', style: WeaveTypography.label),
      const SizedBox(height: WeaveSpacing.s8),
      for (final MapEntry<String, String?>(key: String root, value: String? branch) in _repositories.entries) ...<Widget>[
        WeaveCard(
          key: ValueKey<String>('repository-$root'),
          surface: WeaveSurface.field,
          padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16, vertical: WeaveSpacing.s10),
          child: Row(
            children: <Widget>[
              const WeaveIcon(WeaveIcons.folder, size: WeaveSpacing.s20, color: WeaveColors.green),
              const SizedBox(width: WeaveSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(path.basename(root), style: WeaveTypography.bodyStrong),
                    Text(root, style: WeaveTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (branch != null) ...<Widget>[WeaveChip(label: branch, icon: WeaveIcons.gitBranch, shape: WeaveChipShape.pill), const SizedBox(width: WeaveSpacing.s8)],
              WeaveIconButton(
                key: ValueKey<String>('remove-repository-$root'),
                icon: WeaveIcons.close,
                tooltip: 'Remove ${path.basename(root)} from this task',
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _repositories.remove(root));
                        _saveDraft();
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: WeaveSpacing.s8),
      ],
      WeaveCard(
        key: const Key('repository-add'),
        surface: WeaveSurface.sunken,
        padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16, vertical: WeaveSpacing.s12),
        onTap: _busy ? null : _addRepository,
        child: Row(
          children: <Widget>[
            const WeaveIcon(WeaveIcons.plus, size: WeaveSpacing.s20, color: WeaveColors.purpleSoft),
            const SizedBox(width: WeaveSpacing.s10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(_repositories.isEmpty ? 'Add a repository' : 'Add another repository', style: WeaveTypography.bodyStrong),
                  Text(
                    _repositories.isEmpty ? 'Choose a cloned Git repository, or several for a task that spans them.' : 'Name the repositories to change in the task description; after planning, Weave asks before any of them is edited.',
                    style: WeaveTypography.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: WeaveSpacing.s24),
      WeaveTextField.multiline(
        key: const Key('request'),
        controller: _request,
        label: 'Task description',
        hintText: 'Describe what should change…',
        minLines: 6,
        maxLines: 6,
      ),
      const SizedBox(height: WeaveSpacing.s24),
      Text('Agent pipeline', style: WeaveTypography.label),
      const SizedBox(height: WeaveSpacing.s12),
      LayoutBuilder(
        builder: (BuildContext context, BoxConstraints pipeline) {
          if (pipeline.maxWidth >= WeaveLayout.newTaskPipelineRowMinWidth) {
            return Row(
              children: <Widget>[
                for (int index = 0; index < AgentRole.values.length; index++) ...<Widget>[
                  Expanded(child: _agentCard(AgentRole.values[index], index + 1)),
                  if (index < AgentRole.values.length - 1) ...<Widget>[
                    const SizedBox(width: WeaveSpacing.s8),
                    const WeaveIcon(WeaveIcons.arrowRight, size: WeaveIconSize.control),
                    const SizedBox(width: WeaveSpacing.s8),
                  ],
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int index = 0; index < AgentRole.values.length; index++) ...<Widget>[
                _agentCard(AgentRole.values[index], index + 1),
                if (index < AgentRole.values.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: WeaveSpacing.s4),
                    child: Center(child: WeaveIcon(WeaveIcons.chevronDown, size: WeaveIconSize.control)),
                  ),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: WeaveSpacing.s32),
      Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: WeaveLayout.newTaskStartButtonWidth,
          child: WeaveButton.primary(key: const Key('start'), label: _busy ? 'Starting…' : 'Start workflow', icon: _busy ? null : WeaveIcons.play, onPressed: _busy ? null : _start, expand: true),
        ),
      ),
    ],
  );

  Widget _agentCard(AgentRole role, int number) {
    final AgentAdapter? agent = _agentById(_agents[role]);
    return AgentPipelineCard(
      key: Key('agent-${role.name}'),
      number: number,
      roleLabel: _roleLabel(role),
      agent: agent,
      model: _models[role]!.text.trim().isEmpty ? null : _models[role]!.text.trim(),
      available: agent != null && widget.agents.availabilityOf(agent.id)?.isAvailable != false,
      onTap: () => _chooseAgent(role),
      onClear: agent == null ? null : () => _clearAgent(role),
      hasError: _missingAgentRoles.contains(role),
    );
  }

  AgentAdapter? _agentById(String? id) {
    for (final AgentAdapter agent in widget.agents.agents) {
      if (agent.id == id) {
        return agent;
      }
    }
    return null;
  }

  static String _roleLabel(AgentRole role) => switch (role) {
    AgentRole.planner => 'Plan',
    AgentRole.implementer => 'Implement',
    AgentRole.reviewer => 'Review & test',
  };

  static String _commandLine(VerificationCommand command) => <String>[command.executable, ...command.arguments].map((String word) => word.isEmpty || word.contains(RegExp(r'''[\s"'\\|&;<>]''')) ? "'${word.replaceAll("'", r"'\''")}'" : word).join(' ');

  static String _describe(Object error) => switch (error) {
    WorkflowStartException(:final String message) => message,
    StateError(:final String message) => message,
    _ => error.toString(),
  };
}

/// The Home screen's sidebar: New task and the recent workflows. Used docked
/// beside the screen and floating over any screen; [onNewTask] (when set)
/// makes the New task item open the form.
class HomeSidebarContent extends StatelessWidget {
  const HomeSidebarContent({required this.workflow, required this.onOpenWorkflow, this.onNewTask, super.key});

  final VoidCallback? onNewTask;

  final WorkflowController workflow;
  final ValueChanged<String> onOpenWorkflow;

  @override
  Widget build(BuildContext context) => WeaveCard(
    key: const Key('home-sidebar-content'),
    radius: 0,
    surface: WeaveSurface.sunken,
    padding: const EdgeInsets.fromLTRB(WeaveSpacing.s16, WeaveLayout.windowContentTopPadding, WeaveSpacing.s16, WeaveSpacing.s16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Home', style: WeaveTypography.titleSmall),
        const SizedBox(height: WeaveSpacing.s16),
        WeaveCard(
          key: const Key('home-new-task'),
          surface: WeaveSurface.selected,
          onTap: onNewTask,
          padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s12, vertical: WeaveSpacing.s10),
          child: Row(
            children: <Widget>[
              const WeaveIcon(WeaveIcons.plus, size: WeaveIconSize.compact),
              const SizedBox(width: WeaveSpacing.s10),
              Text('New task', style: WeaveTypography.bodyStrong),
            ],
          ),
        ),
        const SizedBox(height: WeaveSpacing.s24),
        Text('RECENT', style: WeaveTypography.overline),
        const SizedBox(height: WeaveSpacing.s8),
        Expanded(
          child: workflow.tasks.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text('No recent workflows', style: WeaveTypography.caption),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: workflow.tasks.length,
                  separatorBuilder: (BuildContext context, int index) => const SizedBox(height: WeaveSpacing.s4),
                  itemBuilder: (BuildContext context, int index) {
                    final WorkflowTask task = workflow.tasks[index];
                    return _RecentWorkflowCard(
                      key: ValueKey<String>('home-recent-${task.id}'),
                      task: task,
                      onOpen: () => onOpenWorkflow(task.id),
                      onDelete: workflow.isRunning(task.id) ? null : () => confirmAndDeleteWorkflow(context, task: task, delete: workflow.delete),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

/// One recent workflow: its title scrolls while the pointer is anywhere on
/// the card, and a delete action appears on hover or keyboard focus.
class _RecentWorkflowCard extends StatefulWidget {
  const _RecentWorkflowCard({required this.task, required this.onOpen, required this.onDelete, super.key});

  final WorkflowTask task;
  final VoidCallback onOpen;

  /// Null while the workflow runs; it must be cancelled first.
  final VoidCallback? onDelete;

  @override
  State<_RecentWorkflowCard> createState() => _RecentWorkflowCardState();
}

class _RecentWorkflowCardState extends State<_RecentWorkflowCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final WorkflowTask task = widget.task;
    final bool showDelete = widget.onDelete != null && (_hovered || _focused);
    return MouseRegion(
      onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
      onExit: (PointerExitEvent _) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (bool focused) => setState(() => _focused = focused),
        child: WeaveCard(
          surface: WeaveSurface.sunken,
          padding: const EdgeInsets.fromLTRB(WeaveSpacing.s12, WeaveSpacing.s8, WeaveSpacing.s8, WeaveSpacing.s8),
          onTap: widget.onOpen,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    WeaveMarqueeText(task.request.split('\n').first, style: WeaveTypography.bodySmall, active: _hovered),
                    const SizedBox(height: WeaveSpacing.s2),
                    Text(path.basename(task.repositoryPath), style: WeaveTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: WeaveSpacing.s4),
              // Kept in the tree so keyboard users can reach it; shown on hover or focus.
              Opacity(
                opacity: showDelete ? 1 : 0,
                child: WeaveIconButton(
                  key: ValueKey<String>('delete-recent-${task.id}'),
                  icon: WeaveIcons.trash,
                  tooltip: 'Delete workflow',
                  size: WeaveLayout.sidebarRowActionSize,
                  iconSize: WeaveIconSize.compact,
                  onPressed: widget.onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _McpChoice {
  const _McpChoice(this.server);

  final McpServerDefinition? server;
}
