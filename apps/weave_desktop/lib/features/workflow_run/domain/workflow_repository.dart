import 'package:weave_git/weave_git.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

/// Persistent and orchestration operations needed by workflow presentation.
abstract interface class WorkflowRepository {
  Future<List<WorkflowTask>> listTasks();

  WorkflowOrchestrator createOrchestrator();

  Future<List<WorkflowArtifact>> readArtifacts(String taskId);

  Future<List<WorkflowLogEntry>> readLog(String taskId);

  Future<WorkflowRunState?> loadRunState(String taskId);

  Future<WorkflowSettings?> loadSettings(String taskId);

  Future<GitDiff> readDiff(String repositoryPath);

  /// Removes a stopped workflow and its history from Weave's storage only.
  Future<void> deleteWorkflow(String taskId);

  Future<GitCommitResult> commit(String repositoryPath, {required String message, required GitApprovalGate approve});

  String agentDisplayName(String id);

  String mcpDisplayName(String id);
}
