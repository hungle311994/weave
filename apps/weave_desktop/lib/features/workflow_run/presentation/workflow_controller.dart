import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_git/weave_git.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../domain/diff_document.dart';
import '../domain/workflow_repository.dart';

/// Owns workflow history, live runs and workflow-level actions.
final class WorkflowController extends ChangeNotifier {
  WorkflowController(this._repository, {required this._onWorkflowSelected, this._onWorkflowDeleted});

  final WorkflowRepository _repository;
  final ValueChanged<String> _onWorkflowSelected;

  /// Lets navigation leave a page whose workflow no longer exists.
  final ValueChanged<String>? _onWorkflowDeleted;
  final Map<String, WorkflowRun> _runs = <String, WorkflowRun>{};
  final Map<String, StreamSubscription<WorkflowEvent>> _subscriptions = <String, StreamSubscription<WorkflowEvent>>{};
  final Set<String> _interrupted = <String>{};
  List<WorkflowTask> _tasks = const <WorkflowTask>[];
  bool _disposed = false;

  List<WorkflowTask> get tasks => _tasks;

  WorkflowTask? taskById(String taskId) {
    for (final WorkflowTask task in _tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  WorkflowRun? runFor(String taskId) => _runs[taskId];

  /// A run is over once its task reaches a final status: the finishing event
  /// arrives before the run marks itself finished, so checking only the run
  /// would keep showing actions such as Cancel.
  bool isRunning(String taskId) => _runs[taskId]?.isFinished == false && taskById(taskId)?.isTerminal != true;

  bool isInterrupted(String taskId) => _interrupted.contains(taskId) && !isRunning(taskId);

  Future<void> initialize() => refreshTasks();

  Future<void> refreshTasks() async {
    _tasks = await _repository.listTasks();
    final WorkflowOrchestrator orchestrator = _repository.createOrchestrator();
    _interrupted
      ..clear()
      ..addAll(<String>[
        for (final WorkflowTask task in _tasks)
          if (!isRunning(task.id) && await orchestrator.isInterrupted(task)) task.id,
      ]);
    _notify();
  }

  /// Adds a run started by another feature to the live workflow collection.
  void track(WorkflowRun run) {
    _runs[run.task.id] = run;
    _upsert(run.task);
    _onWorkflowSelected(run.task.id);
    _notify();
    unawaited(_subscriptions.remove(run.task.id)?.cancel());
    // Rebuild once the run has fully finished, after its last event.
    unawaited(run.result.then((WorkflowTask _) => _notify(), onError: (Object _) => _notify()));
    _subscriptions[run.task.id] = run.events.listen((WorkflowEvent event) {
      switch (event) {
        case WorkflowStatusChanged(:final WorkflowTask task) || WorkflowFinished(:final WorkflowTask task):
          _upsert(task);
          _notify();
        case WorkflowApprovalRequested() || WorkflowApprovalResolved() || WorkflowArtifactSaved() || WorkflowCheckpointRequested() || WorkflowCheckpointResolved() || WorkflowAgentSwitched():
          _notify();
        default:
          break;
      }
    });
  }

  Future<void> resume(String taskId) async {
    final WorkflowRun run = await _repository.createOrchestrator().resume(taskId);
    _interrupted.remove(taskId);
    track(run);
  }

  Future<void> cancel(String taskId) async => _runs[taskId]?.cancel();

  /// Deletes a workflow that is not running from Weave's storage and the list.
  /// The repository it worked on is not touched.
  Future<void> delete(String taskId) async {
    if (isRunning(taskId)) {
      throw StateError('Cancel this workflow before deleting it.');
    }
    await _repository.deleteWorkflow(taskId);
    _tasks = <WorkflowTask>[
      for (final WorkflowTask task in _tasks)
        if (task.id != taskId) task,
    ];
    _runs.remove(taskId);
    _interrupted.remove(taskId);
    unawaited(_subscriptions.remove(taskId)?.cancel());
    _onWorkflowDeleted?.call(taskId);
    _notify();
  }

  Future<void> resolveApproval(String taskId, String approvalId, ApprovalDecision decision) async {
    await _runs[taskId]?.resolveApproval(approvalId, decision);
    _notify();
  }

  /// [editableRepositories] answers a repositories checkpoint.
  void resolveCheckpoint(String taskId, String checkpointId, CheckpointDecision decision, {String? feedback, Set<String>? editableRepositories}) {
    _runs[taskId]?.resolveCheckpoint(checkpointId, decision, feedback: feedback, editableRepositories: editableRepositories);
    _notify();
  }

  Future<List<WorkflowArtifact>> artifactsFor(String taskId) => _repository.readArtifacts(taskId);

  Future<List<WorkflowLogEntry>> logFor(String taskId) => _repository.readLog(taskId);

  Future<WorkflowRunState?> runStateFor(String taskId) => _repository.loadRunState(taskId);

  Future<WorkflowSettings?> settingsForTask(String taskId) => _repository.loadSettings(taskId);

  Future<GitDiff> readDiff(String repositoryPath) => _repository.readDiff(repositoryPath);

  /// The uncommitted changes of every repository of [task], in order.
  Future<List<RepositoryDiff>> readDiffs(WorkflowTask task) async {
    final Map<String, String> names = repositoryNames(task.repositoryPaths);
    return <RepositoryDiff>[
      for (final String repository in task.repositoryPaths)
        if (await _repository.readDiff(repository) case final GitDiff diff) RepositoryDiff(name: names[repository]!, path: repository, patch: diff.patch, isTruncated: diff.isTruncated),
    ];
  }

  /// Commits [repositoryPath] (default: the task's working directory) after
  /// [approve] accepted the exact file list; only completed workflows commit.
  Future<GitCommitResult> commit(String taskId, {required String message, required GitApprovalGate approve, String? repositoryPath}) {
    final WorkflowTask? task = taskById(taskId);
    if (task == null || task.status != WorkflowStatus.completed) {
      throw StateError('Only completed workflows can be committed.');
    }
    final String repository = repositoryPath ?? task.repositoryPath;
    if (!task.repositoryPaths.contains(repository)) {
      throw StateError('$repository is not part of this workflow.');
    }
    return _repository.commit(repository, message: message, approve: approve);
  }

  String agentDisplayName(String id) => _repository.agentDisplayName(id);

  String mcpDisplayName(String id) => _repository.mcpDisplayName(id);

  void _upsert(WorkflowTask task) {
    _tasks = <WorkflowTask>[
      task,
      for (final WorkflowTask existing in _tasks)
        if (existing.id != task.id) existing,
    ]..sort((WorkflowTask left, WorkflowTask right) => right.updatedAt.compareTo(left.updatedAt));
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final StreamSubscription<WorkflowEvent> subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    for (final WorkflowRun run in _runs.values) {
      if (!run.task.isTerminal && !run.isFinished) {
        unawaited(run.cancel());
      }
    }
    super.dispose();
  }
}
