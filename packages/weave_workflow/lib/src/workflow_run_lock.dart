import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:weave_storage/weave_storage.dart';

/// Marks a workflow as running in one process, so the CLI and the desktop
/// app never run or resume the same workflow at once.
final class WorkflowRunLock {
  WorkflowRunLock({required this._workflowsDirectory});

  final String _workflowsDirectory;

  File _file(String taskId) => File(path.join(workflowTaskDirectory(_workflowsDirectory, taskId).path, 'run.lock'));

  /// Whether a live process other than this one holds the lock.
  Future<bool> isHeldElsewhere(String taskId) async {
    final int? owner = await _owner(taskId);
    return owner != null && owner != pid && await _isAlive(owner);
  }

  /// Takes the lock, replacing one left by a process that no longer runs.
  Future<bool> acquire(String taskId) async {
    if (await isHeldElsewhere(taskId)) {
      return false;
    }
    await writeFileAtomically(_file(taskId), '$pid\n');
    return true;
  }

  Future<void> release(String taskId) async {
    final File file = _file(taskId);
    if (await _owner(taskId) == pid && await file.exists()) {
      await file.delete();
    }
  }

  Future<int?> _owner(String taskId) async {
    final File file = _file(taskId);
    if (!await file.exists()) {
      return null;
    }
    return int.tryParse((await file.readAsString()).trim());
  }

  /// `kill -0` only checks that the process exists; it sends no signal.
  static Future<bool> _isAlive(int processId) async {
    try {
      return (await Process.run('kill', <String>['-0', '$processId'])).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
