import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:weave_security/weave_security.dart';

import 'workflow_files.dart';
import 'workflow_task_json_codec.dart';
import 'workflow_task_store.dart';

/// A document a workflow phase produces.
enum WorkflowArtifactKind { plan, planReview, implementation, selfReview, verification, review }

/// One phase result, numbered by the review cycle it belongs to.
final class WorkflowArtifact {
  WorkflowArtifact({
    required this.kind,
    required this.cycle,
    required this.content,
    required DateTime createdAt,
  }) : createdAt = createdAt.toUtc() {
    if (cycle < 0) {
      throw ArgumentError.value(cycle, 'cycle', 'must not be negative');
    }
  }

  final WorkflowArtifactKind kind;
  final int cycle;
  final String content;
  final DateTime createdAt;
}

/// One line of a workflow's event log.
final class WorkflowLogEntry {
  WorkflowLogEntry({
    required DateTime timestamp,
    required this.source,
    required this.message,
  }) : timestamp = timestamp.toUtc();

  final DateTime timestamp;

  /// `weave` for orchestration events, or the role that produced the output.
  final String source;
  final String message;
}

/// Persistence for workflow artifacts and event logs.
abstract interface class WorkflowArtifactStore {
  Future<void> writeArtifact(String taskId, WorkflowArtifact artifact);

  /// Artifacts ordered by cycle, then by phase order.
  Future<List<WorkflowArtifact>> readArtifacts(String taskId);

  Future<void> appendLog(String taskId, WorkflowLogEntry entry);

  Future<List<WorkflowLogEntry>> readLog(String taskId);
}

/// Stores artifacts and an append-only JSON Lines log next to each task.
///
/// Every stored text passes through [SecretRedactor], and oversized log
/// messages are truncated so a noisy agent cannot fill the disk.
final class FileWorkflowArtifactStore implements WorkflowArtifactStore {
  FileWorkflowArtifactStore({
    required this._workflowsDirectory,
    SecretRedactor? redactor,
    this.maxLogMessageLength = 16 * 1024,
  }) : _redactor = redactor ?? SecretRedactor.fromEnvironment(Platform.environment);

  static const int schemaVersion = 1;

  final String _workflowsDirectory;
  final SecretRedactor _redactor;
  final int maxLogMessageLength;
  final Map<String, Future<void>> _logWrites = <String, Future<void>>{};

  @override
  Future<void> writeArtifact(String taskId, WorkflowArtifact artifact) async {
    final File file = File(path.join(_artifactsDirectory(taskId).path, '${artifact.cycle.toString().padLeft(3, '0')}-${artifact.kind.name}.json'));
    try {
      await writeFileAtomically(
        file,
        encodePrettyJson(
          <String, Object>{
            'schemaVersion': schemaVersion,
            'kind': artifact.kind.name,
            'cycle': artifact.cycle,
            'createdAt': artifact.createdAt.toIso8601String(),
            'content': _redactor.redact(
              artifact.content,
            ),
          },
        ),
      );
    } on Object catch (error, stackTrace) {
      throw WorkflowStorageException('Unable to save ${artifact.kind.name} for workflow $taskId.', cause: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<List<WorkflowArtifact>> readArtifacts(String taskId) async {
    final Directory directory = _artifactsDirectory(taskId);
    if (!await directory.exists()) {
      return const <WorkflowArtifact>[];
    }

    final List<WorkflowArtifact> artifacts = <WorkflowArtifact>[];
    await for (final FileSystemEntity entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        artifacts.add(_decodeArtifact(await _readJsonObject(entity)));
      }
    }
    artifacts.sort((WorkflowArtifact left, WorkflowArtifact right) {
      final int byCycle = left.cycle.compareTo(right.cycle);
      return byCycle != 0 ? byCycle : left.kind.index.compareTo(right.kind.index);
    });
    return List<WorkflowArtifact>.unmodifiable(artifacts);
  }

  @override
  Future<void> appendLog(String taskId, WorkflowLogEntry entry) {
    final File file = _logFile(taskId);
    String message = _redactor.redact(entry.message);
    if (message.length > maxLogMessageLength) {
      message = '${message.substring(0, maxLogMessageLength)}\n[truncated]';
    }
    final String line = '${jsonEncode(<String, String>{'timestamp': entry.timestamp.toIso8601String(), 'source': entry.source, 'message': message})}\n';

    // Appends for one task run in order even when callers do not await them.
    final Future<void> previous = _logWrites[taskId] ?? Future<void>.value();
    final Future<Null> write = previous.then((_) async {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      } on Object catch (error, stackTrace) {
        throw WorkflowStorageException('Unable to append to the log of workflow $taskId.', cause: error, stackTrace: stackTrace);
      }
    });
    _logWrites[taskId] = write.catchError((Object _) {});
    return write;
  }

  @override
  Future<List<WorkflowLogEntry>> readLog(String taskId) async {
    await _logWrites[taskId];
    final File file = _logFile(taskId);
    if (!await file.exists()) {
      return const <WorkflowLogEntry>[];
    }

    final List<String> lines = (await file.readAsLines()).where((String line) => line.trim().isNotEmpty).toList();
    final List<WorkflowLogEntry> entries = <WorkflowLogEntry>[];
    for (int index = 0; index < lines.length; index++) {
      try {
        final Object? json = jsonDecode(lines[index]);
        if (json is! Map<String, Object?>) {
          throw const FormatException('Log line must be an object.');
        }
        entries.add(
          WorkflowLogEntry(
            timestamp: DateTime.parse(json['timestamp']! as String),
            source: json['source']! as String,
            message: json['message']! as String,
          ),
        );
      } on Object catch (error) {
        // A crash can leave the final line partially written.
        if (index == lines.length - 1) {
          break;
        }
        throw WorkflowStorageFormatException('Invalid log line ${index + 1} for workflow $taskId.', cause: error);
      }
    }
    return List<WorkflowLogEntry>.unmodifiable(entries);
  }

  Directory _artifactsDirectory(String taskId) => Directory(path.join(workflowTaskDirectory(_workflowsDirectory, taskId).path, 'artifacts'));

  File _logFile(String taskId) => File(path.join(workflowTaskDirectory(_workflowsDirectory, taskId).path, 'events.jsonl'));

  static Future<Map<String, Object?>> _readJsonObject(File file) async {
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const WorkflowStorageFormatException('Artifact JSON must be an object.');
    }
    return decoded;
  }

  static WorkflowArtifact _decodeArtifact(Map<String, Object?> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw WorkflowStorageFormatException('Unsupported artifact schema version: ${json['schemaVersion']}.');
    }
    try {
      return WorkflowArtifact(
        kind: WorkflowArtifactKind.values.byName(json['kind']! as String),
        cycle: json['cycle']! as int,
        content: json['content']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
      );
    } on Object catch (error) {
      throw WorkflowStorageFormatException('Invalid artifact data.', cause: error);
    }
  }
}
