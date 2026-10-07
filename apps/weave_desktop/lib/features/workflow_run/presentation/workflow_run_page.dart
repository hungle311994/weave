import 'dart:async';

import 'package:flutter/material.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_git/weave_git.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../../../core/design_system/design_system.dart';
import '../domain/diff_document.dart';
import 'code_review_page.dart';
import 'dialogs/agent_unavailable_dialog.dart';
import 'dialogs/cancel_workflow_dialog.dart';
import 'dialogs/delete_workflow_dialog.dart';
import 'plan_approval_page.dart';
import 'repository_access_page.dart';
import 'widgets/status_chip.dart';
import 'workflow_controller.dart';

/// One line of the activity feed, from a live event or the stored log.
final class _ActivityLine {
  const _ActivityLine({required this.timestamp, required this.source, required this.text, this.isError = false, this.isOutput = false});

  final DateTime timestamp;
  final String source;
  final String text;
  final bool isError;
  final bool isOutput;
}

/// Live progress, approvals, artifacts, and changes of one workflow.
class WorkflowRunPage extends StatefulWidget {
  const WorkflowRunPage({required this.controller, required this.taskId, super.key});

  final WorkflowController controller;
  final String taskId;

  @override
  State<WorkflowRunPage> createState() => _WorkflowRunPageState();
}

class _WorkflowRunPageState extends State<WorkflowRunPage> {
  final List<_ActivityLine> _activity = <_ActivityLine>[];
  final Map<String, WorkflowApprovalRequested> _approvals = <String, WorkflowApprovalRequested>{};
  final Map<AgentRole, String> _activeAgents = <AgentRole, String>{};
  StreamSubscription<WorkflowEvent>? _subscription;
  WorkflowChecklist _checklist = WorkflowChecklist(const <ChecklistItem>[]);
  AgentUsage _usage = AgentUsage.zero;
  WorkflowCheckpoint? _checkpoint;
  final Set<String> _shownUnavailableCheckpoints = <String>{};
  late Future<List<WorkflowArtifact>> _artifacts;
  late final Future<WorkflowSettings?> _settings = widget.controller.settingsForTask(widget.taskId);

  /// Bumped on every change; tabs listen to it directly because a
  /// [TabBarView] may keep showing old children while switching tabs.
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  WorkflowController get _controller => widget.controller;

  /// False until a finished workflow's stored log is read; the page stays
  /// invisible until then so its timeline doesn't jump from empty to loaded.
  bool _ready = false;

  /// Whether a completed workflow left uncommitted changes; `null` until
  /// checked, and again after a commit so it is checked anew.
  bool? _hasChanges;
  bool _checkingChanges = false;

  /// Reads the repositories' diffs once the workflow is completed, so Commit
  /// is offered only when there is something to commit.
  Future<void> _checkChanges(WorkflowTask task) async {
    _checkingChanges = true;
    bool hasChanges;
    try {
      hasChanges = (await _controller.readDiffs(task)).any((RepositoryDiff diff) => diff.patch.trim().isNotEmpty);
    } on Object {
      // When Git cannot tell, keep Commit available; it reports "nothing to commit" itself.
      hasChanges = true;
    }
    _checkingChanges = false;
    if (mounted) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  @override
  void initState() {
    super.initState();
    _artifacts = _controller.artifactsFor(widget.taskId);
    if (_attachRun()) {
      _ready = true;
    } else {
      _loadStoredLog();
    }
  }

  /// Follows the live run of this workflow, if any; returns whether it did.
  bool _attachRun() {
    final WorkflowRun? run = _controller.runFor(widget.taskId);
    if (run == null || _subscription != null) {
      return run != null;
    }
    _activity.clear();
    _approvals.clear();
    // History and subscription in one synchronous step: nothing is missed.
    run.history.forEach(_record);
    _checklist = run.checklist;
    _usage = run.usage;
    _checkpoint = run.pendingCheckpoint;
    _subscription = run.events.listen((WorkflowEvent event) {
      if (mounted) {
        setState(() => _record(event));
        _revision.value++;
      }
    });
    _revision.value++;
    return true;
  }

  Future<void> _resume() async {
    try {
      await _controller.resume(widget.taskId);
      if (mounted) {
        setState(_attachRun);
      }
    } on Object catch (error) {
      if (mounted) {
        showWeaveToast(context, message: error is WorkflowStartException ? error.message : 'Could not resume: $error', tone: WeaveToastTone.danger);
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _revision.dispose();
    super.dispose();
  }

  Future<void> _loadStoredLog() async {
    final List<WorkflowLogEntry> entries = await _controller.logFor(widget.taskId);
    final WorkflowRunState? state = await _controller.runStateFor(widget.taskId);
    if (!mounted || _subscription != null) {
      return;
    }
    setState(() {
      _ready = true;
      if (state != null) {
        _checklist = state.checklist;
        _usage = state.totalUsage;
        _activeAgents.addAll(state.activeAgents);
      }
      _activity.addAll(<_ActivityLine>[for (final WorkflowLogEntry entry in entries) _ActivityLine(timestamp: entry.timestamp, source: entry.source, text: entry.message, isOutput: entry.source != 'weave')]);
    });
    _revision.value++;
  }

  void _record(WorkflowEvent event) {
    switch (event) {
      case WorkflowApprovalRequested(:final String approvalId):
        _approvals[approvalId] = event;
      case WorkflowApprovalResolved(:final String approvalId):
        _approvals.remove(approvalId);
      case WorkflowArtifactSaved():
        _artifacts = _controller.artifactsFor(widget.taskId);
      case WorkflowChecklistUpdated(:final WorkflowChecklist checklist):
        _checklist = checklist;
      case WorkflowAgentFinished(:final AgentUsage totalUsage):
        _usage = totalUsage;
      case WorkflowAgentSwitched(:final AgentRole role, :final String toAgentId):
        _activeAgents[role] = toAgentId;
      case WorkflowCheckpointRequested(:final WorkflowCheckpoint checkpoint):
        _checkpoint = checkpoint;
        if (checkpoint.kind == WorkflowCheckpointKind.agentUnavailable) {
          _presentUnavailableCheckpoint(checkpoint);
        }
      case WorkflowCheckpointResolved():
        _checkpoint = null;
      case WorkflowFinished():
        _approvals.clear();
        _checkpoint = null;
      default:
        break;
    }
    _activity.add(
      _ActivityLine(
        timestamp: event.timestamp,
        source: event.source,
        text: event.message,
        isOutput: event is WorkflowAgentOutput,
        isError: event is WorkflowAgentOutput && event.channel == AgentOutputChannel.stderr || event is WorkflowFinished && event.reason != null,
      ),
    );
  }

  void _presentUnavailableCheckpoint(WorkflowCheckpoint checkpoint) {
    if (!_shownUnavailableCheckpoints.add(checkpoint.id)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((Duration _) async {
      if (!mounted || _checkpoint?.id != checkpoint.id) {
        return;
      }
      final AgentUnavailableDecision? decision = await showAgentUnavailableDialog(context: context, checkpoint: checkpoint);
      if (!mounted || decision == null || _checkpoint?.id != checkpoint.id) {
        return;
      }
      _controller.resolveCheckpoint(widget.taskId, checkpoint.id, decision == AgentUnavailableDecision.retry ? CheckpointDecision.approve : CheckpointDecision.cancel);
    });
  }

  Future<void> _confirmCancel(String taskId) async {
    if (await showCancelWorkflowDialog(context) && mounted) {
      await _controller.cancel(taskId);
    }
  }

  Future<void> _commit(WorkflowTask task) async {
    await _commitChanges(task);
    if (mounted) {
      // Whatever was committed is gone from the working tree; check again.
      setState(() => _hasChanges = null);
    }
  }

  Future<void> _commitChanges(WorkflowTask task) async {
    if (task.hasMultipleRepositories) {
      await _commitRepositories(task);
      return;
    }
    final String? message = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _CommitMessageDialog(initialMessage: defaultCommitMessage(task)),
    );
    if (message == null || !mounted) {
      return;
    }
    final (String result, WeaveToastTone tone) = await _commitRepository(task, task.repositoryPath, message);
    if (mounted) {
      showWeaveToast(context, message: result, tone: tone);
    }
  }

  /// One commit per changed repository, each with its own message and its
  /// own approval of the exact file list.
  Future<void> _commitRepositories(WorkflowTask task) async {
    final List<RepositoryDiff> changed = <RepositoryDiff>[
      for (final RepositoryDiff diff in await _controller.readDiffs(task))
        if (diff.patch.trim().isNotEmpty) diff,
    ];
    if (!mounted) {
      return;
    }
    if (changed.isEmpty) {
      showWeaveToast(context, message: 'There are no changes to commit.', tone: WeaveToastTone.info);
      return;
    }
    final Map<String, String>? messages = await showDialog<Map<String, String>>(
      context: context,
      builder: (BuildContext context) => _MultiCommitDialog(repositories: changed, initialMessage: defaultCommitMessage(task)),
    );
    if (messages == null || !mounted) {
      return;
    }
    final Map<String, String> names = <String, String>{for (final RepositoryDiff diff in changed) diff.path: diff.name};
    final List<String> results = <String>[];
    WeaveToastTone tone = WeaveToastTone.success;
    for (final MapEntry<String, String>(:String key, :String value) in messages.entries) {
      final (String result, WeaveToastTone outcome) = await _commitRepository(task, key, value);
      results.add('${names[key]}: $result');
      if (outcome != WeaveToastTone.success) {
        tone = outcome == WeaveToastTone.danger ? WeaveToastTone.danger : (tone == WeaveToastTone.danger ? tone : WeaveToastTone.info);
      }
      if (!mounted) {
        return;
      }
    }
    showWeaveToast(context, message: results.join('\n'), tone: tone);
  }

  /// Commits [repositoryPath] after the user approves the file list.
  Future<(String, WeaveToastTone)> _commitRepository(WorkflowTask task, String repositoryPath, String message) async {
    try {
      final GitCommitResult commit = await _controller.commit(
        task.id,
        message: message,
        repositoryPath: repositoryPath,
        approve: (GitWriteRequest request) async {
          if (!mounted) {
            return false;
          }
          return await showDialog<bool>(
                context: context,
                builder: (BuildContext context) => _CommitApprovalDialog(request: request, message: message),
              ) ??
              false;
        },
      );
      return ('Committed ${commit.commitSha.substring(0, 12)} on ${commit.branch ?? 'detached HEAD'}.', WeaveToastTone.success);
    } on GitApprovalDeniedException {
      return ('Commit cancelled; nothing was changed.', WeaveToastTone.info);
    } on GitNothingToCommitException {
      return ('There are no changes to commit.', WeaveToastTone.info);
    } on GitCommandException catch (error) {
      return ('${error.message}. Check your Git identity and commit hooks.', WeaveToastTone.danger);
    } on Object catch (error) {
      return ('Commit failed: $error', WeaveToastTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    key: const Key('workflow-page-fade'),
    opacity: _ready ? 1 : 0,
    duration: WeaveMotion.standard,
    curve: WeaveMotion.curve,
    child: _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    final WorkflowTask? task = _controller.taskById(widget.taskId);
    if (task == null) {
      return const Center(child: Text('This workflow no longer exists.'));
    }
    final bool isRunning = _controller.isRunning(task.id);
    final WorkflowCheckpoint? checkpoint = _checkpoint;
    if (task.status == WorkflowStatus.completed && _hasChanges == null && !_checkingChanges) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted && !_checkingChanges && _hasChanges == null) {
          _checkChanges(task);
        }
      });
    }

    if (checkpoint != null && checkpoint.kind == WorkflowCheckpointKind.repositories && isRunning) {
      return RepositoryAccessPage(
        key: ValueKey<String>(checkpoint.id),
        checkpoint: checkpoint,
        onDecision: (CheckpointDecision decision, String? feedback, Set<String>? repositories) => _controller.resolveCheckpoint(task.id, checkpoint.id, decision, feedback: feedback, editableRepositories: repositories),
      );
    }
    if (checkpoint != null && checkpoint.kind == WorkflowCheckpointKind.changes && isRunning) {
      return CodeReviewPage(
        // Each revision round is a new checkpoint and must re-read the diff.
        key: ValueKey<String>(checkpoint.id),
        checkpointDetails: checkpoint.details,
        checklist: _checklist,
        settings: _settings,
        loadDiffs: () => _controller.readDiffs(task),
        onDecision: (CheckpointDecision decision, String? feedback) => _controller.resolveCheckpoint(task.id, checkpoint.id, decision, feedback: feedback),
      );
    }
    if (checkpoint != null && checkpoint.kind == WorkflowCheckpointKind.plan && isRunning) {
      return PlanApprovalPage(
        request: task.request,
        plan: checkpoint.details,
        checklist: _checklist,
        settings: _settings,
        onDecision: (CheckpointDecision decision, String? feedback) => _controller.resolveCheckpoint(task.id, checkpoint.id, decision, feedback: feedback),
      );
    }

    return DefaultTabController(
      length: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(WeaveLayout.pageGutter, WeaveLayout.windowContentTopPadding, WeaveSpacing.s28, WeaveSpacing.s20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                WeavePageHeader(
                  breadcrumb: const <String>['Workspace', 'Workflow'],
                  title: _pageTitle(task.status),
                  subtitle: 'Agents work directly in the repository with HEAD, branch, and uncommitted-edit guards.',
                  trailing: Wrap(
                    spacing: WeaveSpacing.s12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      WeaveStatusPill(label: statusLabel(task.status), tone: _statusTone(task.status)),
                      if (_controller.isInterrupted(task.id)) WeaveButton.primary(key: const Key('resume'), label: 'Resume', icon: WeaveIcons.play, onPressed: _resume),
                      if (isRunning) WeaveButton.danger(key: const Key('cancel'), label: 'Cancel', icon: WeaveIcons.stop, onPressed: () => _confirmCancel(task.id)),
                    ],
                  ),
                ),
                if (task.reviewCycle > 0) ...<Widget>[const SizedBox(height: WeaveSpacing.s8), WeaveBadge(label: 'Review round ${task.reviewCycle}', tone: WeaveTone.warning)],
                const SizedBox(height: WeaveSpacing.s12),
                FutureBuilder<WorkflowSettings?>(
                  future: _settings,
                  builder: (BuildContext context, AsyncSnapshot<WorkflowSettings?> snapshot) => snapshot.data == null ? const SizedBox.shrink() : _SettingsSummary(settings: snapshot.data!, controller: _controller, activeAgents: _activeAgents, repositories: task.repositoryPaths),
                ),
                for (final WorkflowApprovalRequested approval in _approvals.values) _ApprovalBanner(approval: approval, onDecision: (ApprovalDecision decision) => _controller.resolveApproval(task.id, approval.approvalId, decision)),
                if (checkpoint != null && checkpoint.kind != WorkflowCheckpointKind.agentUnavailable && isRunning)
                  _CheckpointPanel(
                    key: ValueKey<String>(checkpoint.id),
                    checkpoint: checkpoint,
                    onDecision: (CheckpointDecision decision, String? feedback) => _controller.resolveCheckpoint(task.id, checkpoint.id, decision, feedback: feedback),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(WeaveLayout.pageGutter, 0, WeaveSpacing.s28, isRunning ? WeaveSpacing.s32 : WeaveSpacing.s16),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget timeline = _ExecutionTimeline(task: task, activity: _activity, usage: _usage);
                  final Widget details = _DetailsPanel(
                    activity: _listening(() => _ActivityList(lines: List<_ActivityLine>.of(_activity))),
                    checklist: _listening(() => _ChecklistList(checklist: _checklist, controller: _controller)),
                    plan: _listening(() => _ArtifactList(artifacts: _artifacts, kinds: const <WorkflowArtifactKind>{WorkflowArtifactKind.plan, WorkflowArtifactKind.planReview})),
                    implementation: _listening(() => _ArtifactList(artifacts: _artifacts, kinds: const <WorkflowArtifactKind>{WorkflowArtifactKind.implementation, WorkflowArtifactKind.selfReview})),
                    verification: _listening(() => _ArtifactList(artifacts: _artifacts, kinds: const <WorkflowArtifactKind>{WorkflowArtifactKind.verification})),
                    review: _listening(() => _ArtifactList(artifacts: _artifacts, kinds: const <WorkflowArtifactKind>{WorkflowArtifactKind.review})),
                    changes: _ChangesTab(load: () => _controller.readDiffs(task)),
                  );
                  if (constraints.maxWidth >= WeaveLayout.workflowSplitBreakpoint) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(child: timeline),
                        const SizedBox(width: WeaveSpacing.s24),
                        SizedBox(width: WeaveLayout.chatPanelWidth, child: details),
                      ],
                    );
                  }
                  return Column(
                    children: <Widget>[
                      Expanded(flex: 3, child: timeline),
                      const SizedBox(height: WeaveSpacing.s16),
                      Expanded(flex: 2, child: details),
                    ],
                  );
                },
              ),
            ),
          ),
          // Finishing actions sit at the bottom right, the primary one last.
          if (!isRunning)
            Padding(
              key: const Key('workflow-actions'),
              padding: const EdgeInsets.fromLTRB(WeaveLayout.pageGutter, 0, WeaveSpacing.s28, WeaveSpacing.s24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  WeaveButton(
                    key: const Key('delete-workflow'),
                    label: 'Delete',
                    icon: WeaveIcons.trash,
                    variant: WeaveButtonVariant.ghost,
                    onPressed: () => confirmAndDeleteWorkflow(context, task: task, delete: _controller.delete),
                  ),
                  if (task.status == WorkflowStatus.completed && _hasChanges == true) ...<Widget>[
                    const SizedBox(width: WeaveSpacing.s12),
                    WeaveButton.primary(key: const Key('commit'), label: 'Commit changes', icon: WeaveIcons.gitCommit, onPressed: () => _commit(task)),
                  ] else if (task.status == WorkflowStatus.completed && _hasChanges == false) ...<Widget>[
                    const SizedBox(width: WeaveSpacing.s12),
                    const WeaveBadge(key: Key('no-changes'), label: 'No changes to commit', tone: WeaveTone.neutral),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _pageTitle(WorkflowStatus status) => switch (status) {
    WorkflowStatus.completed => 'Workflow completed',
    WorkflowStatus.failed => 'Workflow failed',
    WorkflowStatus.cancelled => 'Workflow cancelled',
    _ => 'Workflow in progress',
  };

  static WeaveTone _statusTone(WorkflowStatus status) => switch (status) {
    WorkflowStatus.completed => WeaveTone.success,
    WorkflowStatus.failed => WeaveTone.danger,
    WorkflowStatus.cancelled || WorkflowStatus.pending => WeaveTone.neutral,
    WorkflowStatus.changesRequested => WeaveTone.warning,
    _ => WeaveTone.info,
  };
}

extension on _WorkflowRunPageState {
  Widget _listening(Widget Function() build) => ValueListenableBuilder<int>(valueListenable: _revision, builder: (BuildContext context, int _, Widget? _) => build());
}

class _ExecutionTimeline extends StatelessWidget {
  const _ExecutionTimeline({required this.task, required this.activity, required this.usage});

  final WorkflowTask task;
  final List<_ActivityLine> activity;
  final AgentUsage usage;

  @override
  Widget build(BuildContext context) {
    final bool implementationStarted = activity.any((_ActivityLine line) => line.text.startsWith('Status: ${WorkflowStatus.implementing.name}'));
    final bool selfReviewStarted = activity.any((_ActivityLine line) => line.text.contains('self-review'));
    final bool verificationFinished = activity.any((_ActivityLine line) => line.text.startsWith('Verification '));
    final bool stopped = task.status == WorkflowStatus.failed || task.status == WorkflowStatus.cancelled;
    final int activeStep = switch (task.status) {
      WorkflowStatus.pending || WorkflowStatus.planning => 0,
      WorkflowStatus.readyForImplementation || WorkflowStatus.implementing || WorkflowStatus.changesRequested => selfReviewStarted ? 2 : 1,
      WorkflowStatus.readyForReview || WorkflowStatus.reviewing => verificationFinished ? 4 : 3,
      WorkflowStatus.completed => 5,
      WorkflowStatus.failed || WorkflowStatus.cancelled => _lastStartedStep(implementationStarted, selfReviewStarted, verificationFinished),
    };
    // The step a stopped run ended on says so instead of looking in progress.
    final String stoppedLabel = task.status == WorkflowStatus.cancelled ? 'Cancelled' : 'Failed';
    String subtitle(int index, {required String done, required String active, required String waiting}) => index < activeStep
        ? done
        : index == activeStep
        ? (stopped ? stoppedLabel : active)
        : waiting;
    final List<_ActivityLine> output = activity.where((_ActivityLine line) => line.isOutput).toList(growable: false).reversed.take(3).toList(growable: false).reversed.toList(growable: false);
    final List<WeaveStep> steps = <WeaveStep>[
      WeaveStep(
        title: 'Plan',
        subtitle: subtitle(0, done: 'Plan ready', active: 'Creating the implementation plan', waiting: 'Queued'),
        status: _stepStatus(0, activeStep, task.status),
      ),
      WeaveStep(
        title: 'Implement',
        subtitle: subtitle(1, done: 'Implementation complete', active: 'Editing the repository working tree…', waiting: 'Queued'),
        status: _stepStatus(1, activeStep, task.status),
        child: activeStep == 1 && !stopped && output.isNotEmpty
            ? WeaveCard(
                surface: WeaveSurface.sunken,
                padding: const EdgeInsets.all(WeaveSpacing.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[for (final _ActivityLine line in output) Text('› ${line.text.trimRight()}', style: WeaveTypography.code, maxLines: 1, overflow: TextOverflow.ellipsis)],
                ),
              )
            : null,
      ),
      WeaveStep(
        title: 'Self-review',
        subtitle: subtitle(2, done: 'Agent checked its own work', active: 'Reviewing implementation…', waiting: 'Queued'),
        status: _stepStatus(2, activeStep, task.status),
      ),
      WeaveStep(
        title: 'Verify',
        subtitle: subtitle(3, done: 'Validation completed', active: 'Running verification commands…', waiting: 'Waiting for implementation'),
        status: _stepStatus(3, activeStep, task.status),
      ),
      WeaveStep(
        title: 'Final review',
        subtitle: subtitle(4, done: 'Approved', active: 'Reviewer is checking the changes…', waiting: 'Waiting for verification'),
        status: _stepStatus(4, activeStep, task.status),
      ),
    ];
    return WeaveCard(
      padding: const EdgeInsets.all(WeaveSpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Execution timeline', style: WeaveTypography.titleMedium),
                    Text(task.request, style: WeaveTypography.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (usage.totalTokens > 0) WeaveBadge(key: const Key('usage'), label: usage.toString(), icon: WeaveIcons.thinking, tone: WeaveTone.info),
            ],
          ),
          const SizedBox(height: WeaveSpacing.s24),
          Expanded(
            child: SingleChildScrollView(child: WeaveStepTimeline(steps: steps)),
          ),
        ],
      ),
    );
  }

  /// The step a failed or cancelled run had reached.
  static int _lastStartedStep(bool implementationStarted, bool selfReviewStarted, bool verificationFinished) {
    if (verificationFinished) {
      return 4;
    }
    if (selfReviewStarted) {
      return 2;
    }
    return implementationStarted ? 1 : 0;
  }

  static WeaveStepStatus _stepStatus(int index, int activeStep, WorkflowStatus workflowStatus) {
    if (index < activeStep || activeStep == 5) {
      return WeaveStepStatus.done;
    }
    if (index == activeStep) {
      return workflowStatus == WorkflowStatus.failed || workflowStatus == WorkflowStatus.cancelled ? WeaveStepStatus.failed : WeaveStepStatus.active;
    }
    return WeaveStepStatus.pending;
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.activity, required this.checklist, required this.plan, required this.implementation, required this.verification, required this.review, required this.changes});

  final Widget activity;
  final Widget checklist;
  final Widget plan;
  final Widget implementation;
  final Widget verification;
  final Widget review;
  final Widget changes;

  @override
  Widget build(BuildContext context) => WeaveCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: <Widget>[
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: <Tab>[
            Tab(key: Key('activity-tab'), text: 'Activity'),
            Tab(key: Key('checklist-tab'), text: 'Checklist'),
            Tab(key: Key('plan-tab'), text: 'Plan'),
            Tab(key: Key('implementation-tab'), text: 'Implementation'),
            Tab(key: Key('verification-tab'), text: 'Verification'),
            Tab(key: Key('review-tab'), text: 'Review'),
            Tab(key: Key('changes-tab'), text: 'Changes'),
          ],
        ),
        Expanded(child: TabBarView(children: <Widget>[activity, checklist, plan, implementation, verification, review, changes])),
      ],
    ),
  );
}

class _SettingsSummary extends StatelessWidget {
  const _SettingsSummary({required this.settings, required this.controller, required this.activeAgents, required this.repositories});

  /// Every repository of the task, the working directory first.
  final List<String> repositories;

  final WorkflowSettings settings;
  final WorkflowController controller;

  /// Roles that moved to a fallback agent.
  final Map<AgentRole, String> activeAgents;

  @override
  Widget build(BuildContext context) {
    String agent(AgentRole role) {
      final String assigned = settings.assignments.agentIdFor(role);
      final String id = activeAgents[role] ?? assigned;
      final String name = controller.agentDisplayName(id);
      return id == assigned ? name : '$name (fallback for ${controller.agentDisplayName(assigned)})';
    }

    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: <Widget>[
        for (final AgentRole role in AgentRole.values) Text('${role.name}: ${agent(role)}', style: Theme.of(context).textTheme.bodySmall),
        if (settings.mcpServerIds.isNotEmpty) Text('MCP: ${settings.mcpServerIds.map(controller.mcpDisplayName).join(', ')}', style: Theme.of(context).textTheme.bodySmall),
        if (repositories.length > 1) Text('Repositories: ${repositoryNames(repositories).values.join(', ')}', key: const Key('workflow-repositories'), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ApprovalBanner extends StatelessWidget {
  const _ApprovalBanner({required this.approval, required this.onDecision});

  final WorkflowApprovalRequested approval;
  final ValueChanged<ApprovalDecision> onDecision;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: MaterialBanner(
      leading: const WeaveIcon(WeaveIcons.shield, color: WeaveColors.textPrimary),
      content: Text('${approval.role.name} asks to: ${approval.action}\n${approval.details}'),
      actions: <Widget>[
        WeaveButton(key: const Key('deny'), label: 'Deny', onPressed: () => onDecision(ApprovalDecision.deny)),
        WeaveButton.primary(key: const Key('approve'), label: 'Approve', onPressed: () => onDecision(ApprovalDecision.approve)),
      ],
    ),
  );
}

/// The workflow log. It follows new lines while scrolled to the end; once
/// the user scrolls up it stays put, and following resumes at the end again.
class _ActivityList extends StatefulWidget {
  const _ActivityList({required this.lines});

  final List<_ActivityLine> lines;

  @override
  State<_ActivityList> createState() => _ActivityListState();
}

class _ActivityListState extends State<_ActivityList> {
  final ScrollController _scroll = ScrollController();

  /// Whether the view is at the end, so new lines should scroll into view.
  bool _followTail = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final ScrollPosition position = _scroll.position;
      _followTail = position.pixels >= position.maxScrollExtent - WeaveLayout.followTailThreshold;
    });
    _scrollToEnd();
  }

  @override
  void didUpdateWidget(_ActivityList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != oldWidget.lines.length && _followTail) {
      _scrollToEnd();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// After the new lines are laid out, so the end is known.
  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((Duration _) {
    if (mounted && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });

  @override
  Widget build(BuildContext context) {
    final List<_ActivityLine> lines = widget.lines;
    if (lines.isEmpty) {
      return const Center(child: Text('No activity yet.'));
    }
    final ThemeData theme = Theme.of(context);
    final TextStyle mono = theme.textTheme.bodySmall!.copyWith(fontFamily: 'Menlo');
    return SelectionArea(
      child: ListView.builder(
        key: const Key('activity-list'),
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        itemCount: lines.length,
        itemBuilder: (BuildContext context, int index) {
          final _ActivityLine line = lines[index];
          final String time = line.timestamp.toLocal().toString().substring(11, 19);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '$time ',
                    style: mono.copyWith(color: theme.colorScheme.outline),
                  ),
                  TextSpan(
                    text: '[${line.source}] ',
                    style: mono.copyWith(color: theme.colorScheme.primary),
                  ),
                  TextSpan(
                    text: line.text.trimRight(),
                    style: (line.isOutput ? mono : theme.textTheme.bodySmall)?.copyWith(color: line.isError ? theme.colorScheme.error : null),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ArtifactList extends StatelessWidget {
  const _ArtifactList({required this.artifacts, required this.kinds});

  final Future<List<WorkflowArtifact>> artifacts;
  final Set<WorkflowArtifactKind> kinds;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<WorkflowArtifact>>(
    future: artifacts,
    builder: (BuildContext context, AsyncSnapshot<List<WorkflowArtifact>> snapshot) {
      final List<WorkflowArtifact> matching = <WorkflowArtifact>[
        for (final WorkflowArtifact artifact in snapshot.data ?? const <WorkflowArtifact>[])
          if (kinds.contains(artifact.kind)) artifact,
      ];
      if (matching.isEmpty) {
        return Center(child: Text(snapshot.connectionState == ConnectionState.done ? 'Nothing here yet.' : 'Loading...'));
      }
      final ThemeData theme = Theme.of(context);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          for (final WorkflowArtifact artifact in matching)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${_kindLabel(artifact.kind)} · round ${artifact.cycle}', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    SelectableText(artifact.content.trimRight(), style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  static String _kindLabel(WorkflowArtifactKind kind) => switch (kind) {
    WorkflowArtifactKind.plan => 'Plan',
    WorkflowArtifactKind.planReview => 'Plan review',
    WorkflowArtifactKind.implementation => 'Implementation',
    WorkflowArtifactKind.selfReview => 'Self-review',
    WorkflowArtifactKind.verification => 'Verification',
    WorkflowArtifactKind.review => 'Review',
  };
}

/// Reads the repository diff on demand and keeps it while the tab lives.
class _ChangesTab extends StatefulWidget {
  const _ChangesTab({required this.load});

  /// Changes of every repository of the workflow.
  final Future<List<RepositoryDiff>> Function() load;

  @override
  State<_ChangesTab> createState() => _ChangesTabState();
}

class _ChangesTabState extends State<_ChangesTab> {
  Future<List<RepositoryDiff>>? _diff;

  void _load() {
    // A block body: setState must not receive a closure that returns a Future.
    final Future<List<RepositoryDiff>> diff = widget.load();
    setState(() {
      _diff = diff;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Future<List<RepositoryDiff>>? diff = _diff;
    if (diff == null) {
      return Center(
        child: WeaveButton(key: const Key('show-changes'), label: 'Show current changes', icon: WeaveIcons.fileCode, onPressed: _load),
      );
    }
    return FutureBuilder<List<RepositoryDiff>>(
      future: diff,
      builder: (BuildContext context, AsyncSnapshot<List<RepositoryDiff>> snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not read changes: ${snapshot.error}'));
        }
        final List<RepositoryDiff>? diffs = snapshot.data;
        if (diffs == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<RepositoryDiff> changed = <RepositoryDiff>[
          for (final RepositoryDiff diff in diffs)
            if (diff.patch.trim().isNotEmpty) diff,
        ];
        if (changed.isEmpty) {
          return Center(child: Text(diffs.length > 1 ? 'No repository has uncommitted changes.' : 'The working tree has no uncommitted changes.'));
        }
        final bool isTruncated = diffs.any((RepositoryDiff diff) => diff.isTruncated);
        final ThemeData theme = Theme.of(context);
        final TextStyle mono = theme.textTheme.bodySmall!.copyWith(fontFamily: 'Menlo');
        // Several repositories: each patch under a "### Repository" heading.
        final List<String> lines = <String>[
          for (final RepositoryDiff diff in changed) ...<String>[if (diffs.length > 1) '### Repository ${diff.name} (${diff.path})', ...diff.patch.split('\n')],
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(isTruncated ? 'Showing the first part of a large diff.' : (diffs.length > 1 ? 'Uncommitted changes in each repository.' : 'Uncommitted changes in the repository.'), style: theme.textTheme.bodySmall)),
                  WeaveButton(key: const Key('refresh-changes'), label: 'Refresh', icon: WeaveIcons.refresh, variant: WeaveButtonVariant.ghost, size: WeaveButtonSize.small, onPressed: _load),
                ],
              ),
            ),
            Expanded(
              child: SelectionArea(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: lines.length,
                  itemBuilder: (BuildContext context, int index) {
                    final String line = lines[index];
                    final Color? color = line.startsWith('+') && !line.startsWith('+++')
                        ? Colors.green.shade700
                        : line.startsWith('-') && !line.startsWith('---')
                        ? theme.colorScheme.error
                        : line.startsWith('@@')
                        ? theme.colorScheme.tertiary
                        : null;
                    return Text(line, style: mono.copyWith(color: color));
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CommitMessageDialog extends StatefulWidget {
  const _CommitMessageDialog({required this.initialMessage});

  final String initialMessage;

  @override
  State<_CommitMessageDialog> createState() => _CommitMessageDialogState();
}

class _CommitMessageDialogState extends State<_CommitMessageDialog> {
  late final TextEditingController _message = TextEditingController(text: widget.initialMessage);

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Commit changes'),
    content: SizedBox(
      width: 520,
      child: WeaveTextField.multiline(key: const Key('commit-message'), controller: _message, label: 'Commit message', minLines: 3, maxLines: 8),
    ),
    actions: <Widget>[
      WeaveButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
      WeaveButton.primary(
        key: const Key('commit-next'),
        label: 'Review files',
        onPressed: () {
          if (_message.text.trim().isNotEmpty) {
            Navigator.of(context).pop(_message.text);
          }
        },
      ),
    ],
  );
}

/// Chooses which changed repositories to commit, each with its own message.
class _MultiCommitDialog extends StatefulWidget {
  const _MultiCommitDialog({required this.repositories, required this.initialMessage});

  final List<RepositoryDiff> repositories;
  final String initialMessage;

  @override
  State<_MultiCommitDialog> createState() => _MultiCommitDialogState();
}

class _MultiCommitDialogState extends State<_MultiCommitDialog> {
  late final Map<String, TextEditingController> _messages = <String, TextEditingController>{for (final RepositoryDiff diff in widget.repositories) diff.path: TextEditingController(text: widget.initialMessage)};
  late final Set<String> _selected = <String>{for (final RepositoryDiff diff in widget.repositories) diff.path};

  @override
  void dispose() {
    for (final TextEditingController message in _messages.values) {
      message.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> result = <String, String>{
      for (final RepositoryDiff diff in widget.repositories)
        if (_selected.contains(diff.path) && _messages[diff.path]!.text.trim().isNotEmpty) diff.path: _messages[diff.path]!.text,
    };
    return AlertDialog(
      title: Text(widget.repositories.length == 1 ? 'Commit ${widget.repositories.single.name}' : 'Commit ${widget.repositories.length} repositories'),
      content: SizedBox(
        width: WeaveLayout.dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Each repository gets its own commit; you approve the exact files of each one next. Weave never pushes.', style: WeaveTypography.bodySmall),
              for (final RepositoryDiff diff in widget.repositories) ...<Widget>[
                const SizedBox(height: WeaveSpacing.s16),
                Row(
                  children: <Widget>[
                    WeaveCheckbox(
                      key: ValueKey<String>('commit-include-${diff.name}'),
                      value: _selected.contains(diff.path),
                      semanticLabel: 'Commit ${diff.name}',
                      onChanged: (bool include) => setState(() => include ? _selected.add(diff.path) : _selected.remove(diff.path)),
                    ),
                    const SizedBox(width: WeaveSpacing.s10),
                    Text(diff.name, style: WeaveTypography.bodyStrong),
                    const SizedBox(width: WeaveSpacing.s8),
                    Expanded(
                      child: Text('${DiffDocument.parse(diff.patch).files.length} files · ${diff.path}', style: WeaveTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: WeaveSpacing.s8),
                WeaveTextField.multiline(key: ValueKey<String>('commit-message-${diff.name}'), controller: _messages[diff.path], enabled: _selected.contains(diff.path), minLines: 2, maxLines: 5, onChanged: (String _) => setState(() {})),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        WeaveButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        WeaveButton.primary(key: const Key('commit-next'), label: 'Review files', onPressed: result.isEmpty ? null : () => Navigator.of(context).pop(result)),
      ],
    );
  }
}

/// The approval step: shows exactly what will be committed.
class _CommitApprovalDialog extends StatelessWidget {
  const _CommitApprovalDialog({required this.request, required this.message});

  final GitWriteRequest request;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(request.summary),
      content: SizedBox(
        width: 520,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SelectableText(request.repositoryRoot, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: <Widget>[for (final String path in request.paths) Text(path, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo'))],
              ),
            ),
            const Divider(),
            Text(message, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      actions: <Widget>[
        WeaveButton(key: const Key('commit-deny'), label: 'Cancel', onPressed: () => Navigator.of(context).pop(false)),
        WeaveButton.primary(key: const Key('commit-approve'), label: 'Commit', onPressed: () => Navigator.of(context).pop(true)),
      ],
    );
  }
}

/// A pause waiting for the user: approve, revise with feedback, or cancel.
class _CheckpointPanel extends StatefulWidget {
  const _CheckpointPanel({required this.checkpoint, required this.onDecision, super.key});

  final WorkflowCheckpoint checkpoint;
  final void Function(CheckpointDecision decision, String? feedback) onDecision;

  @override
  State<_CheckpointPanel> createState() => _CheckpointPanelState();
}

class _CheckpointPanelState extends State<_CheckpointPanel> {
  final TextEditingController _feedback = TextEditingController();

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WorkflowCheckpoint checkpoint = widget.checkpoint;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                WeaveIcon(checkpoint.kind == WorkflowCheckpointKind.agentUnavailable ? WeaveIcons.alertTriangle : WeaveIcons.user, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(child: Text(checkpoint.title, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(child: SelectableText(checkpoint.details.trimRight(), style: theme.textTheme.bodySmall)),
            ),
            if (checkpoint.allowsRevision) ...<Widget>[
              const SizedBox(height: 8),
              WeaveTextField.multiline(key: const Key('checkpoint-feedback'), controller: _feedback, hintText: 'What should change? (for Revise)', minLines: 1, maxLines: 4),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.end,
              children: <Widget>[
                WeaveButton(key: const Key('checkpoint-cancel'), label: 'Cancel workflow', variant: WeaveButtonVariant.ghost, onPressed: () => widget.onDecision(CheckpointDecision.cancel, null)),
                if (checkpoint.allowsRevision) WeaveButton(key: const Key('checkpoint-revise'), label: 'Revise', onPressed: () => widget.onDecision(CheckpointDecision.revise, _feedback.text)),
                WeaveButton.primary(key: const Key('checkpoint-approve'), label: checkpoint.allowsRevision ? 'Approve' : 'Retry', onPressed: () => widget.onDecision(CheckpointDecision.approve, null)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The plan's tasks and test cases, their status, and who worked on them.
class _ChecklistList extends StatelessWidget {
  const _ChecklistList({required this.checklist, required this.controller});

  final WorkflowChecklist checklist;
  final WorkflowController controller;

  @override
  Widget build(BuildContext context) {
    if (checklist.isEmpty) {
      return const Center(child: Text('The plan has no checklist yet.'));
    }
    final ThemeData theme = Theme.of(context);
    String agent(String? id) => id == null ? '' : controller.agentDisplayName(id);
    Widget section(String title, List<ChecklistItem> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(title, style: theme.textTheme.titleSmall),
        ),
        for (final ChecklistItem item in items)
          Card(
            child: ListTile(
              dense: true,
              leading: Text(item.id, style: theme.textTheme.labelLarge),
              title: Text(item.title),
              subtitle: Text(
                <String>[
                  if (item.implementedBy != null) 'Implemented by ${agent(item.implementedBy)}',
                  if (item.reviewedBy != null) 'reviewed by ${agent(item.reviewedBy)}',
                  ?item.note,
                ].join(' · '),
              ),
              trailing: _ChecklistStatusChip(item.status),
            ),
          ),
      ],
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (checklist.tasks.isNotEmpty) section('Tasks', checklist.tasks),
        if (checklist.testCases.isNotEmpty) section('Test cases', checklist.testCases),
      ],
    );
  }
}

class _ChecklistStatusChip extends StatelessWidget {
  const _ChecklistStatusChip(this.status);

  final ChecklistItemStatus status;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final (String label, Color background, Color foreground) = switch (status) {
      ChecklistItemStatus.pending => ('Pending', colors.surfaceContainerHighest, colors.onSurfaceVariant),
      ChecklistItemStatus.inProgress => ('In progress', colors.tertiaryContainer, colors.onTertiaryContainer),
      ChecklistItemStatus.done => ('Done', colors.secondaryContainer, colors.onSecondaryContainer),
      ChecklistItemStatus.notDone => ('Not done', colors.errorContainer, colors.onErrorContainer),
      ChecklistItemStatus.verified => ('Verified', colors.primaryContainer, colors.onPrimaryContainer),
      ChecklistItemStatus.needsChanges => ('Needs changes', colors.errorContainer, colors.onErrorContainer),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground)),
      ),
    );
  }
}
