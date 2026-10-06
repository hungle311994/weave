import 'dart:async';

import 'package:flutter/material.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_git/weave_git.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../weave_controller.dart';
import 'status_chip.dart';

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
class WorkflowView extends StatefulWidget {
  const WorkflowView({required this.controller, required this.taskId, super.key});

  final WeaveController controller;
  final String taskId;

  @override
  State<WorkflowView> createState() => _WorkflowViewState();
}

class _WorkflowViewState extends State<WorkflowView> {
  final List<_ActivityLine> _activity = <_ActivityLine>[];
  final Map<String, WorkflowApprovalRequested> _approvals = <String, WorkflowApprovalRequested>{};
  final Map<AgentRole, String> _activeAgents = <AgentRole, String>{};
  StreamSubscription<WorkflowEvent>? _subscription;
  WorkflowChecklist _checklist = WorkflowChecklist(const <ChecklistItem>[]);
  AgentUsage _usage = AgentUsage.zero;
  WorkflowCheckpoint? _checkpoint;
  late Future<List<WorkflowArtifact>> _artifacts;
  late final Future<WorkflowSettings?> _settings = widget.controller.settingsForTask(widget.taskId);

  /// Bumped on every change; tabs listen to it directly because a
  /// [TabBarView] may keep showing old children while switching tabs.
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  WeaveController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _artifacts = _controller.artifactsFor(widget.taskId);
    if (!_attachRun()) {
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
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await _controller.resume(widget.taskId);
      if (mounted) {
        setState(_attachRun);
      }
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error is WorkflowStartException ? error.message : 'Could not resume: $error')));
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

  Future<void> _commit(WorkflowTask task) async {
    final String? message = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _CommitMessageDialog(initialMessage: defaultCommitMessage(task)),
    );
    if (message == null || !mounted) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    String result;
    try {
      final GitCommitResult commit = await _controller.commit(
        task.id,
        message: message,
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
      result = 'Committed ${commit.commitSha.substring(0, 12)} on ${commit.branch ?? 'detached HEAD'}.';
    } on GitApprovalDeniedException {
      result = 'Commit cancelled; nothing was changed.';
    } on GitNothingToCommitException {
      result = 'There are no changes to commit.';
    } on GitCommandException catch (error) {
      result = '${error.message}. Check your Git identity and commit hooks.';
    } on Object catch (error) {
      result = 'Commit failed: $error';
    }
    messenger.showSnackBar(SnackBar(content: Text(result)));
  }

  @override
  Widget build(BuildContext context) {
    final WorkflowTask? task = _controller.taskById(widget.taskId);
    if (task == null) {
      return const Center(child: Text('This workflow no longer exists.'));
    }
    final ThemeData theme = Theme.of(context);
    final bool isRunning = _controller.isRunning(task.id);
    final WorkflowCheckpoint? checkpoint = _checkpoint;

    return DefaultTabController(
      length: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    StatusChip(task.status),
                    if (task.reviewCycle > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text('Review round ${task.reviewCycle}', style: theme.textTheme.labelMedium),
                      ),
                    const SizedBox(width: 12),
                    Expanded(child: SelectableText(task.repositoryPath, style: theme.textTheme.bodySmall)),
                    if (_usage.totalTokens > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(_usage.toString(), key: const Key('usage'), style: theme.textTheme.bodySmall),
                      ),
                    if (_controller.isInterrupted(task.id)) FilledButton.icon(key: const Key('resume'), onPressed: _resume, icon: const Icon(Icons.play_arrow), label: const Text('Resume')),
                    if (isRunning) OutlinedButton.icon(key: const Key('cancel'), onPressed: () => _controller.cancel(task.id), icon: const Icon(Icons.stop), label: const Text('Cancel')),
                    if (task.status == WorkflowStatus.completed) FilledButton.icon(key: const Key('commit'), onPressed: () => _commit(task), icon: const Icon(Icons.check), label: const Text('Commit changes')),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(task.request, style: theme.textTheme.titleMedium, maxLines: 4),
                const SizedBox(height: 12),
                _PhaseBar(status: task.status),
                const SizedBox(height: 8),
                FutureBuilder<WorkflowSettings?>(
                  future: _settings,
                  builder: (BuildContext context, AsyncSnapshot<WorkflowSettings?> snapshot) => snapshot.data == null ? const SizedBox.shrink() : _SettingsSummary(settings: snapshot.data!, controller: _controller, activeAgents: _activeAgents),
                ),
                for (final WorkflowApprovalRequested approval in _approvals.values) _ApprovalBanner(approval: approval, onDecision: (ApprovalDecision decision) => _controller.resolveApproval(task.id, approval.approvalId, decision)),
                if (checkpoint != null && isRunning)
                  _CheckpointPanel(
                    key: ValueKey<String>(checkpoint.id),
                    checkpoint: checkpoint,
                    onDecision: (CheckpointDecision decision, String? feedback) => _controller.resolveCheckpoint(task.id, checkpoint.id, decision, feedback: feedback),
                  ),
              ],
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Tab>[
              Tab(text: 'Activity'),
              Tab(text: 'Checklist'),
              Tab(text: 'Plan'),
              Tab(text: 'Implementation'),
              Tab(text: 'Verification'),
              Tab(text: 'Review'),
              Tab(text: 'Changes'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _listening(() => _ActivityList(lines: List<_ActivityLine>.of(_activity))),
                _listening(() => _ChecklistList(checklist: _checklist, controller: _controller)),
                _listening(() => _ArtifactList(artifacts: _artifacts, kinds: const <WorkflowArtifactKind>{WorkflowArtifactKind.plan, WorkflowArtifactKind.planReview})),
                _listening(() => _ArtifactList(artifacts: _artifacts, kinds: const <WorkflowArtifactKind>{WorkflowArtifactKind.implementation, WorkflowArtifactKind.selfReview})),
                _listening(() => _ArtifactList(artifacts: _artifacts, kinds: const <WorkflowArtifactKind>{WorkflowArtifactKind.verification})),
                _listening(() => _ArtifactList(artifacts: _artifacts, kinds: const <WorkflowArtifactKind>{WorkflowArtifactKind.review})),
                _ChangesTab(load: () => _controller.readDiff(task.repositoryPath)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension on _WorkflowViewState {
  Widget _listening(Widget Function() build) => ValueListenableBuilder<int>(valueListenable: _revision, builder: (BuildContext context, int _, Widget? _) => build());
}

class _PhaseBar extends StatelessWidget {
  const _PhaseBar({required this.status});

  final WorkflowStatus status;

  @override
  Widget build(BuildContext context) {
    final int? current = switch (status) {
      WorkflowStatus.pending || WorkflowStatus.planning => 0,
      WorkflowStatus.readyForImplementation || WorkflowStatus.implementing || WorkflowStatus.changesRequested => 1,
      WorkflowStatus.readyForReview || WorkflowStatus.reviewing => 2,
      WorkflowStatus.completed => 3,
      WorkflowStatus.failed || WorkflowStatus.cancelled => null,
    };
    final ColorScheme colors = Theme.of(context).colorScheme;
    const List<String> phases = <String>['Plan', 'Implement', 'Review', 'Done'];
    return Row(
      children: <Widget>[
        for (int index = 0; index < phases.length; index++) ...<Widget>[
          if (index > 0) Expanded(child: Divider(color: current != null && index <= current ? colors.primary : colors.outlineVariant)),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(phases[index]),
            backgroundColor: current == index ? colors.primaryContainer : null,
            avatar: current != null && index < current ? Icon(Icons.check, size: 16, color: colors.primary) : null,
          ),
        ],
      ],
    );
  }
}

class _SettingsSummary extends StatelessWidget {
  const _SettingsSummary({required this.settings, required this.controller, required this.activeAgents});

  final WorkflowSettings settings;
  final WeaveController controller;

  /// Roles that moved to a fallback agent.
  final Map<AgentRole, String> activeAgents;

  @override
  Widget build(BuildContext context) {
    String agent(AgentRole role) {
      final String assigned = settings.assignments.agentIdFor(role);
      final String id = activeAgents[role] ?? assigned;
      final String name = controller.services.agents[id]?.displayName ?? id;
      return id == assigned ? name : '$name (fallback for ${controller.services.agents[assigned]?.displayName ?? assigned})';
    }

    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: <Widget>[
        for (final AgentRole role in AgentRole.values) Text('${role.name}: ${agent(role)}', style: Theme.of(context).textTheme.bodySmall),
        if (settings.mcpServerIds.isNotEmpty) Text('MCP: ${settings.mcpServerIds.map((String id) => controller.mcp[id]?.displayName ?? id).join(', ')}', style: Theme.of(context).textTheme.bodySmall),
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
      leading: const Icon(Icons.verified_user_outlined),
      content: Text('${approval.role.name} asks to: ${approval.action}\n${approval.details}'),
      actions: <Widget>[
        TextButton(key: const Key('deny'), onPressed: () => onDecision(ApprovalDecision.deny), child: const Text('Deny')),
        FilledButton(key: const Key('approve'), onPressed: () => onDecision(ApprovalDecision.approve), child: const Text('Approve')),
      ],
    ),
  );
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.lines});

  final List<_ActivityLine> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const Center(child: Text('No activity yet.'));
    }
    final ThemeData theme = Theme.of(context);
    final TextStyle mono = theme.textTheme.bodySmall!.copyWith(fontFamily: 'Menlo');
    return SelectionArea(
      child: ListView.builder(
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

  final Future<GitDiff> Function() load;

  @override
  State<_ChangesTab> createState() => _ChangesTabState();
}

class _ChangesTabState extends State<_ChangesTab> {
  Future<GitDiff>? _diff;

  void _load() {
    // A block body: setState must not receive a closure that returns a Future.
    final Future<GitDiff> diff = widget.load();
    setState(() {
      _diff = diff;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Future<GitDiff>? diff = _diff;
    if (diff == null) {
      return Center(
        child: OutlinedButton.icon(key: const Key('show-changes'), onPressed: _load, icon: const Icon(Icons.difference_outlined), label: const Text('Show current changes')),
      );
    }
    return FutureBuilder<GitDiff>(
      future: diff,
      builder: (BuildContext context, AsyncSnapshot<GitDiff> snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not read changes: ${snapshot.error}'));
        }
        final GitDiff? value = snapshot.data;
        if (value == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (value.isEmpty) {
          return const Center(child: Text('The working tree has no uncommitted changes.'));
        }
        final ThemeData theme = Theme.of(context);
        final TextStyle mono = theme.textTheme.bodySmall!.copyWith(fontFamily: 'Menlo');
        final List<String> lines = value.patch.split('\n');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(value.isTruncated ? 'Showing the first part of a large diff.' : 'Uncommitted changes in the repository.', style: theme.textTheme.bodySmall)),
                  TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
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
      child: TextField(
        key: const Key('commit-message'),
        controller: _message,
        minLines: 3,
        maxLines: 8,
        decoration: const InputDecoration(labelText: 'Commit message', border: OutlineInputBorder()),
      ),
    ),
    actions: <Widget>[
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        key: const Key('commit-next'),
        onPressed: () {
          if (_message.text.trim().isNotEmpty) {
            Navigator.of(context).pop(_message.text);
          }
        },
        child: const Text('Review files'),
      ),
    ],
  );
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
        TextButton(key: const Key('commit-deny'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(key: const Key('commit-approve'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Commit')),
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
                Icon(checkpoint.kind == WorkflowCheckpointKind.agentUnavailable ? Icons.warning_amber : Icons.front_hand_outlined, color: theme.colorScheme.onSecondaryContainer),
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
              TextField(
                key: const Key('checkpoint-feedback'),
                controller: _feedback,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'What should change? (for Revise)', border: OutlineInputBorder(), isDense: true),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.end,
              children: <Widget>[
                TextButton(key: const Key('checkpoint-cancel'), onPressed: () => widget.onDecision(CheckpointDecision.cancel, null), child: const Text('Cancel workflow')),
                if (checkpoint.allowsRevision) OutlinedButton(key: const Key('checkpoint-revise'), onPressed: () => widget.onDecision(CheckpointDecision.revise, _feedback.text), child: const Text('Revise')),
                FilledButton(key: const Key('checkpoint-approve'), onPressed: () => widget.onDecision(CheckpointDecision.approve, null), child: Text(checkpoint.allowsRevision ? 'Approve' : 'Retry')),
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
  final WeaveController controller;

  @override
  Widget build(BuildContext context) {
    if (checklist.isEmpty) {
      return const Center(child: Text('The plan has no checklist yet.'));
    }
    final ThemeData theme = Theme.of(context);
    String agent(String? id) => id == null ? '' : controller.services.agents[id]?.displayName ?? id;
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
