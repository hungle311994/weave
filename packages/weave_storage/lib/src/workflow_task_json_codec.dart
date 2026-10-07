import 'package:weave_core/weave_core.dart';

/// Converts [WorkflowTask] values to and from versioned JSON data.
final class WorkflowTaskJsonCodec {
  const WorkflowTaskJsonCodec();

  static const int schemaVersion = 1;

  Map<String, Object> encode(WorkflowTask task) => <String, Object>{
    'schemaVersion': schemaVersion,
    'id': task.id,
    'request': task.request,
    'repositoryPath': task.repositoryPath,
    if (task.additionalRepositoryPaths.isNotEmpty) 'additionalRepositoryPaths': task.additionalRepositoryPaths,
    'status': task.status.name,
    'createdAt': task.createdAt.toUtc().toIso8601String(),
    'updatedAt': task.updatedAt.toUtc().toIso8601String(),
    'reviewCycle': task.reviewCycle,
  };

  WorkflowTask decode(Map<String, Object?> json) {
    try {
      final Object? version = json['schemaVersion'];
      if (version != schemaVersion) {
        throw WorkflowStorageFormatException('Unsupported workflow schema version: $version.');
      }

      return WorkflowTask.restore(
        id: _readString(json, 'id'),
        request: _readString(json, 'request'),
        repositoryPath: _readString(json, 'repositoryPath'),
        additionalRepositoryPaths: _readStrings(json, 'additionalRepositoryPaths'),
        status: WorkflowStatus.values.byName(_readString(json, 'status')),
        createdAt: DateTime.parse(_readString(json, 'createdAt')),
        updatedAt: DateTime.parse(_readString(json, 'updatedAt')),
        reviewCycle: _readInt(json, 'reviewCycle'),
      );
    } on WorkflowStorageFormatException {
      rethrow;
    } on Object catch (error) {
      throw WorkflowStorageFormatException('Invalid workflow task data.', cause: error);
    }
  }

  static String _readString(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is! String) {
      throw WorkflowStorageFormatException('$key must be a string.');
    }
    return value;
  }

  /// An optional list of strings; tasks saved before it existed have none.
  static List<String> _readStrings(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value == null) {
      return const <String>[];
    }
    if (value is! List<Object?> || value.any((Object? item) => item is! String)) {
      throw WorkflowStorageFormatException('$key must be a list of strings.');
    }
    return value.cast<String>();
  }

  static int _readInt(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is! int) {
      throw WorkflowStorageFormatException('$key must be an integer.');
    }
    return value;
  }
}

/// Raised when persisted workflow data does not match the supported schema.
final class WorkflowStorageFormatException implements Exception {
  const WorkflowStorageFormatException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'WorkflowStorageFormatException: $message';
}
