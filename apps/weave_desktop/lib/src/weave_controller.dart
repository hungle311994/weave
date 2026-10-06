import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_git/weave_git.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

/// What the main pane shows.
sealed class WeaveSelection {
  const WeaveSelection();
}

final class NewWorkflowSelection extends WeaveSelection {
  const NewWorkflowSelection();
}

final class AgentsSelection extends WeaveSelection {
  const AgentsSelection();
}

final class McpSelection extends WeaveSelection {
  const McpSelection();
}

final class WorkflowSelection extends WeaveSelection {
  const WorkflowSelection(this.taskId);

  final String taskId;
}

/// Application state shared by every desktop view.
///
/// Status changes notify listeners; streamed agent output does not, so long
/// runs never rebuild the whole window. Views that show output listen to
/// [WorkflowRun.events] directly.
final class WeaveController extends ChangeNotifier {
  WeaveController(this.services, {this._verifier});

  final WeaveServices services;
  final VerificationRunner? _verifier;
  final Map<String, WorkflowRun> _runs = <String, WorkflowRun>{};
  final Map<String, AgentAvailability> _availability = <String, AgentAvailability>{};
  final Set<String> _interrupted = <String>{};
  List<WorkflowTask> _tasks = const <WorkflowTask>[];
  WeaveSelection _selection = const NewWorkflowSelection();
  bool _disposed = false;

  List<WorkflowTask> get tasks => _tasks;

  WeaveSelection get selection => _selection;

  Iterable<AgentAdapter> get agents => services.agents.adapters;

  /// `null` until [refreshAgents] has checked the agent.
  AgentAvailability? availabilityOf(String agentId) => _availability[agentId];

  /// The live run of [taskId] started in this session, if any.
  WorkflowRun? runFor(String taskId) => _runs[taskId];

  bool isRunning(String taskId) => _runs[taskId]?.isFinished == false;

  /// Unfinished workflows that no Weave process is running, e.g. after the
  /// app was closed or the network dropped.
  bool isInterrupted(String taskId) => _interrupted.contains(taskId) && !isRunning(taskId);

  /// Whether no agent is ready, so the user must install or sign in first.
  bool get needsSetup => _availability.isNotEmpty && !_availability.values.any((AgentAvailability availability) => availability.isAvailable);

  WorkflowTask? taskById(String taskId) {
    for (final WorkflowTask task in _tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  Future<void> initialize() => Future.wait(<Future<void>>[refreshTasks(), refreshAgents()]);

  Future<void> refreshTasks() async {
    _tasks = await services.tasks.list();
    final WorkflowOrchestrator orchestrator = services.createOrchestrator(verifier: _verifier);
    _interrupted
      ..clear()
      ..addAll(<String>[
        for (final WorkflowTask task in _tasks)
          if (!isRunning(task.id) && await orchestrator.isInterrupted(task)) task.id,
      ]);
    _notify();
  }

  Future<void> refreshAgents() async {
    final List<AgentAdapter> adapters = services.agents.adapters.toList();
    final List<AgentAvailability> results = await Future.wait(
      <Future<AgentAvailability>>[for (final AgentAdapter adapter in adapters) adapter.checkAvailability()],
    );
    for (int index = 0; index < adapters.length; index++) {
      _availability[adapters[index].id] = results[index];
    }
    _notify();
  }

  void select(WeaveSelection selection) {
    _selection = selection;
    _notify();
  }

  /// The repository root containing [directory] and its saved or default
  /// settings.
  Future<(String root, WorkflowSettings settings)> loadRepository(String directory) async {
    final String root = await services.git.findRepositoryRoot(directory);
    return (root, await services.settingsFor(root));
  }

  /// Starts a workflow, selects it, and returns its ID.
  Future<String> startWorkflow({
    required String request,
    required String repositoryPath,
    required WorkflowSettings settings,
    bool saveAsDefaults = false,
  }) async {
    final String root = await services.git.findRepositoryRoot(repositoryPath);
    if (saveAsDefaults) {
      await services.settings.saveProjectDefaults(root, settings);
    }
    final WorkflowRun run = await services.createOrchestrator(verifier: _verifier).start(request: request, repositoryPath: root, settings: settings);
    _track(run);
    return run.task.id;
  }

  /// Continues an interrupted workflow and selects it.
  Future<void> resume(String taskId) async {
    final WorkflowRun run = await services.createOrchestrator(verifier: _verifier).resume(taskId);
    _interrupted.remove(taskId);
    _track(run);
  }

  void _track(WorkflowRun run) {
    _runs[run.task.id] = run;
    _upsert(run.task);
    _selection = WorkflowSelection(run.task.id);
    _notify();
    run.events.listen((WorkflowEvent event) {
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

  Future<void> cancel(String taskId) async => _runs[taskId]?.cancel();

  Future<void> resolveApproval(String taskId, String approvalId, ApprovalDecision decision) async {
    await _runs[taskId]?.resolveApproval(approvalId, decision);
    _notify();
  }

  Future<List<WorkflowArtifact>> artifactsFor(String taskId) => services.artifacts.readArtifacts(taskId);

  Future<List<WorkflowLogEntry>> logFor(String taskId) => services.artifacts.readLog(taskId);

  /// Checklist, usage, and agents of a workflow, as last saved.
  Future<WorkflowRunState?> runStateFor(String taskId) => services.runStates.load(taskId);

  void resolveCheckpoint(String taskId, String checkpointId, CheckpointDecision decision, {String? feedback}) {
    _runs[taskId]?.resolveCheckpoint(checkpointId, decision, feedback: feedback);
    _notify();
  }

  Future<WorkflowSettings?> settingsForTask(String taskId) => services.settings.loadForTask(taskId);

  /// Uncommitted changes in [repositoryPath], read without modifying it.
  Future<GitDiff> readDiff(String repositoryPath) => services.git.readDiff(repositoryPath);

  /// Commits a completed workflow's changes once [approve] allows it.
  Future<GitCommitResult> commit(String taskId, {required String message, required GitApprovalGate approve}) {
    final WorkflowTask? task = taskById(taskId);
    if (task == null || task.status != WorkflowStatus.completed) {
      throw StateError('Only completed workflows can be committed.');
    }
    return services.gitWriter.commitAll(task.repositoryPath, message: message, approve: approve);
  }

  McpRegistry get mcp => services.mcp;

  /// MCP servers to offer for links in [request] that [enabledIds] miss.
  List<McpServerDefinition> mcpSuggestions(String request, Iterable<String> enabledIds) => services.mcp.suggestionsFor(request, enabledIds: enabledIds);

  /// IDs from `mcp.json`, which can be removed; presets cannot.
  Future<Set<String>> customMcpIds() async => <String>{
    for (final McpServerDefinition server in await loadCustomMcpServers(services.paths)) server.id,
  };

  /// Adds [server] to `mcp.json`, replacing a server with the same ID.
  Future<void> saveMcpServer(McpServerDefinition server) async {
    final List<McpServerDefinition> custom = await loadCustomMcpServers(services.paths);
    await saveCustomMcpServers(
      services.paths,
      <McpServerDefinition>[
        for (final McpServerDefinition existing in custom)
          if (existing.id != server.id) existing,
        server,
      ],
    );
    await services.reloadMcp();
    _notify();
  }

  Future<void> removeMcpServer(String id) async {
    final List<McpServerDefinition> custom = await loadCustomMcpServers(services.paths);
    await saveCustomMcpServers(
      services.paths,
      <McpServerDefinition>[
        for (final McpServerDefinition existing in custom)
          if (existing.id != id) existing,
      ],
    );
    await services.reloadMcp();
    _notify();
  }

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
    for (final WorkflowRun run in _runs.values) {
      unawaited(run.cancel());
    }
    super.dispose();
  }
}
