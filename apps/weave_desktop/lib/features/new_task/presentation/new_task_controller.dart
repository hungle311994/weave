import 'package:flutter/foundation.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../domain/new_task_repository.dart';
import '../domain/loaded_repository.dart';

/// Coordinates repository loading and workflow creation for the new-task form.
final class NewTaskController {
  NewTaskController(this._repository, {required this._onStarted});

  final NewTaskRepository _repository;
  final ValueChanged<WorkflowRun> _onStarted;

  /// In-memory form state. It survives navigation but is never written to the
  /// repository or application support storage.
  final NewTaskDraft draft = NewTaskDraft();

  Future<LoadedRepository> loadRepository(String directory) => _repository.loadRepository(directory);

  Future<LoadedRepository> cloneRepository(String url, {required String parentDirectory}) => _repository.cloneRepository(url, parentDirectory: parentDirectory);

  Future<String> startWorkflow({required String request, required String repositoryPath, List<String> additionalRepositoryPaths = const <String>[], required WorkflowSettings settings, bool saveAsDefaults = false}) async {
    final WorkflowRun run = await _repository.startWorkflow(request: request, repositoryPath: repositoryPath, additionalRepositoryPaths: additionalRepositoryPaths, settings: settings, saveAsDefaults: saveAsDefaults);
    _onStarted(run);
    return run.task.id;
  }
}

/// The in-progress New Task form, retained while the app is running.
final class NewTaskDraft {
  String request = '';
  String verification = '';
  String maxTokens = '';
  final Map<AgentRole, String?> agents = <AgentRole, String?>{for (final AgentRole role in AgentRole.values) role: null};
  final Map<AgentRole, String> models = <AgentRole, String>{for (final AgentRole role in AgentRole.values) role: ''};
  final Map<AgentRole, String?> fallbacks = <AgentRole, String?>{for (final AgentRole role in AgentRole.values) role: null};
  final Set<String> mcpServerIds = <String>{};
  int maxReviews = 3;
  bool approvePlan = false;
  bool approveChanges = false;
  bool reviewPlan = false;
  bool saveAsDefaults = false;

  /// The task's repositories by root, with their branch, in the order they
  /// were added. The first is the working directory; none is preferred in
  /// the UI, and the user allows edits per repository after planning.
  final Map<String, String?> repositories = <String, String?>{};

  /// Clears only the task-specific request after a workflow starts.
  void clearStartedRequest() {
    request = '';
  }
}
