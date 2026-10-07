import 'package:weave_workflow/weave_workflow.dart';

import 'loaded_repository.dart';

/// Repository and orchestration operations used while creating a task.
abstract interface class NewTaskRepository {
  Future<LoadedRepository> loadRepository(String directory);

  Future<LoadedRepository> cloneRepository(String url, {required String parentDirectory});

  /// Starts a workflow in [repositoryPath]; [additionalRepositoryPaths] are
  /// further repositories the agents may read and, if the user allows it
  /// after planning, edit.
  Future<WorkflowRun> startWorkflow({required String request, required String repositoryPath, List<String> additionalRepositoryPaths = const <String>[], required WorkflowSettings settings, required bool saveAsDefaults});
}
