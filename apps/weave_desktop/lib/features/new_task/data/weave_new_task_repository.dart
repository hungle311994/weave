import 'package:weave_git/weave_git.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../domain/loaded_repository.dart';
import '../domain/new_task_repository.dart';

/// Starts workflows and loads repository defaults through [WeaveServices].
final class WeaveNewTaskRepository implements NewTaskRepository {
  WeaveNewTaskRepository(this._services, {this._verifier, GitRepositoryCloner? cloner})
    : _cloner =
          cloner ??
          GitRepositoryCloner(
            runner: ProcessGitCommandRunner(environment: _services.environment, timeout: const Duration(minutes: 10)),
            reader: _services.git,
          );

  final WeaveServices _services;
  final VerificationRunner? _verifier;
  final GitRepositoryCloner _cloner;

  @override
  Future<LoadedRepository> loadRepository(String directory) async {
    final GitRepositorySnapshot snapshot = await _services.git.readSnapshot(directory);
    return LoadedRepository(root: snapshot.rootPath, branch: snapshot.head.branch, settings: await _services.settingsFor(snapshot.rootPath));
  }

  @override
  Future<LoadedRepository> cloneRepository(String url, {required String parentDirectory}) async {
    final GitRepositorySnapshot snapshot = await _cloner.clone(url, parentDirectory: parentDirectory);
    return LoadedRepository(root: snapshot.rootPath, branch: snapshot.head.branch, settings: await _services.settingsFor(snapshot.rootPath));
  }

  @override
  Future<WorkflowRun> startWorkflow({required String request, required String repositoryPath, List<String> additionalRepositoryPaths = const <String>[], required WorkflowSettings settings, required bool saveAsDefaults}) async {
    final String root = await _services.git.findRepositoryRoot(repositoryPath);
    if (saveAsDefaults) {
      await _services.settings.saveProjectDefaults(root, settings);
    }
    return _services.createOrchestrator(verifier: _verifier).start(request: request, repositoryPath: root, additionalRepositoryPaths: additionalRepositoryPaths, settings: settings);
  }
}
