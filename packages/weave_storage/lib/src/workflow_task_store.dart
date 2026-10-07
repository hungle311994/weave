import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:weave_core/weave_core.dart';

import 'workflow_files.dart';
import 'workflow_task_json_codec.dart';

/// Persistence contract for workflow task state.
abstract interface class WorkflowTaskStore {
  Future<void> save(WorkflowTask task);

  Future<WorkflowTask?> load(String taskId);

  Future<List<WorkflowTask>> list();

  /// Removes the task and everything stored with it (artifacts, event log,
  /// settings, run state). Never touches the repository the task worked on.
  Future<void> delete(String taskId);
}

/// Stores each workflow in a dedicated directory outside source repositories.
final class FileWorkflowTaskStore implements WorkflowTaskStore {
  FileWorkflowTaskStore({required String workflowsDirectory, this.codec = const WorkflowTaskJsonCodec()}) : _workflowsDirectory = Directory(workflowsDirectory);

  final Directory _workflowsDirectory;
  final WorkflowTaskJsonCodec codec;

  @override
  Future<void> save(WorkflowTask task) async {
    final File target = File(path.join(_taskDirectory(task.id).path, 'task.json'));
    try {
      await writeFileAtomically(target, encodePrettyJson(codec.encode(task)));
    } on Object catch (error, stackTrace) {
      throw WorkflowStorageException('Unable to save workflow task ${task.id}.', cause: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<WorkflowTask?> load(String taskId) async {
    final File file = File(path.join(_taskDirectory(taskId).path, 'task.json'));
    if (!await file.exists()) {
      return null;
    }

    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const WorkflowStorageFormatException('Workflow task JSON must be an object.');
      }
      return codec.decode(decoded);
    } on WorkflowStorageFormatException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw WorkflowStorageException('Unable to load workflow task $taskId.', cause: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> delete(String taskId) async {
    final Directory directory = _taskDirectory(taskId);
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on Object catch (error, stackTrace) {
      throw WorkflowStorageException('Unable to delete workflow task $taskId.', cause: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<List<WorkflowTask>> list() async {
    if (!await _workflowsDirectory.exists()) {
      return const <WorkflowTask>[];
    }

    final List<WorkflowTask> tasks = <WorkflowTask>[];
    await for (final FileSystemEntity entity in _workflowsDirectory.list()) {
      if (entity is! Directory) {
        continue;
      }
      final File file = File(path.join(entity.path, 'task.json'));
      if (!await file.exists()) {
        continue;
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const WorkflowStorageFormatException('Workflow task JSON must be an object.');
      }
      tasks.add(codec.decode(decoded));
    }

    tasks.sort((WorkflowTask left, WorkflowTask right) => right.updatedAt.compareTo(left.updatedAt));
    return List<WorkflowTask>.unmodifiable(tasks);
  }

  Directory _taskDirectory(String taskId) => workflowTaskDirectory(_workflowsDirectory.path, taskId);
}

/// Raised when the filesystem cannot complete a workflow storage operation.
final class WorkflowStorageException implements Exception {
  const WorkflowStorageException(this.message, {required this.cause, required this.stackTrace});

  final String message;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'WorkflowStorageException: $message';
}
