import 'package:weave_git/weave_git.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../domain/workflow_repository.dart';

/// Adapts [WeaveServices] to the workflow presentation boundary.
final class WeaveWorkflowRepository implements WorkflowRepository {
  const WeaveWorkflowRepository(this._services, {this._verifier});

  final WeaveServices _services;
  final VerificationRunner? _verifier;

  @override
  Future<List<WorkflowTask>> listTasks() => _services.tasks.list();

  @override
  WorkflowOrchestrator createOrchestrator() => _services.createOrchestrator(verifier: _verifier);

  @override
  Future<List<WorkflowArtifact>> readArtifacts(String taskId) => _services.artifacts.readArtifacts(taskId);

  @override
  Future<List<WorkflowLogEntry>> readLog(String taskId) => _services.artifacts.readLog(taskId);

  @override
  Future<WorkflowRunState?> loadRunState(String taskId) => _services.runStates.load(taskId);

  @override
  Future<WorkflowSettings?> loadSettings(String taskId) => _services.settings.loadForTask(taskId);

  @override
  Future<GitDiff> readDiff(String repositoryPath) => _services.git.readDiff(repositoryPath);

  @override
  Future<void> deleteWorkflow(String taskId) => _services.deleteWorkflow(taskId);

  @override
  Future<GitCommitResult> commit(String repositoryPath, {required String message, required GitApprovalGate approve}) => _services.gitWriter.commitAll(repositoryPath, message: message, approve: approve);

  @override
  String agentDisplayName(String id) => _services.agents[id]?.displayName ?? id;

  @override
  String mcpDisplayName(String id) => _services.mcp[id]?.displayName ?? id;
}
