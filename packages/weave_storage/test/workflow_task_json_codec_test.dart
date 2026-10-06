import 'package:test/test.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_storage/weave_storage.dart';

void main() {
  const WorkflowTaskJsonCodec codec = WorkflowTaskJsonCodec();
  final DateTime createdAt = DateTime.utc(2026, 10, 6, 10);
  final DateTime updatedAt = createdAt.add(const Duration(minutes: 5));
  final WorkflowTask task = WorkflowTask.restore(id: 'task-1', request: 'Build Weave', repositoryPath: '/projects/weave', status: WorkflowStatus.changesRequested, createdAt: createdAt, updatedAt: updatedAt, reviewCycle: 2);

  test('round-trips every workflow task field', () {
    final WorkflowTask result = codec.decode(codec.encode(task));

    expect(result.id, task.id);
    expect(result.request, task.request);
    expect(result.repositoryPath, task.repositoryPath);
    expect(result.status, task.status);
    expect(result.createdAt, task.createdAt);
    expect(result.updatedAt, task.updatedAt);
    expect(result.reviewCycle, task.reviewCycle);
  });

  test('writes the current schema version', () {
    expect(codec.encode(task)['schemaVersion'], WorkflowTaskJsonCodec.schemaVersion);
  });

  test('rejects an unsupported schema version', () {
    final Map<String, Object> json = codec.encode(task)..['schemaVersion'] = 999;

    expect(() => codec.decode(json), throwsA(isA<WorkflowStorageFormatException>()));
  });

  test('rejects an unknown workflow status', () {
    final Map<String, Object> json = codec.encode(task)..['status'] = 'unknown';

    expect(() => codec.decode(json), throwsA(isA<WorkflowStorageFormatException>()));
  });
}
