import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_storage/weave_storage.dart';

void main() {
  late Directory temporaryDirectory;
  late FileWorkflowTaskStore store;
  final DateTime createdAt = DateTime.utc(2026, 10, 6, 10);

  WorkflowTask createTask({String id = 'task-1', DateTime? updatedAt}) => WorkflowTask.restore(id: id, request: 'Build Weave', repositoryPath: '/projects/weave', status: WorkflowStatus.pending, createdAt: createdAt, updatedAt: updatedAt ?? createdAt, reviewCycle: 0);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-storage-test-');
    store = FileWorkflowTaskStore(workflowsDirectory: path.join(temporaryDirectory.path, 'workflows'));
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('deletes a task with everything stored beside it and leaves other tasks', () async {
    await store.save(createTask(id: 'keep'));
    await store.save(createTask(id: 'drop'));
    final Directory dropped = workflowTaskDirectory(path.join(temporaryDirectory.path, 'workflows'), 'drop');
    await File(path.join(dropped.path, 'artifacts', 'plan-0.md')).create(recursive: true);
    await File(path.join(dropped.path, 'events.jsonl')).writeAsString('{}\n');

    await store.delete('drop');

    expect(await dropped.exists(), isFalse);
    expect(await store.load('drop'), isNull);
    expect((await store.list()).map((WorkflowTask task) => task.id), <String>['keep']);
  });

  test('deleting an unknown task does nothing', () async {
    await store.delete('missing');
    expect(await store.list(), isEmpty);
  });

  test('saves and loads a workflow task', () async {
    final WorkflowTask task = createTask();

    await store.save(task);
    final WorkflowTask? loaded = await store.load(task.id);

    expect(loaded, isNotNull);
    expect(loaded!.id, task.id);
    expect(loaded.request, task.request);
    expect(loaded.status, task.status);
  });

  test('returns null when a workflow does not exist', () async {
    expect(await store.load('missing-task'), isNull);
  });

  test('overwrites an existing task atomically', () async {
    final WorkflowTask task = createTask();
    await store.save(task);
    final WorkflowTask updated = task.transitionTo(WorkflowStatus.planning, at: createdAt.add(const Duration(minutes: 1)));

    await store.save(updated);
    final WorkflowTask? loaded = await store.load(task.id);

    expect(loaded!.status, WorkflowStatus.planning);
    expect(loaded.updatedAt, updated.updatedAt);
  });

  test('lists tasks with the newest update first', () async {
    final WorkflowTask older = createTask(id: 'older');
    final WorkflowTask newer = createTask(id: 'newer', updatedAt: createdAt.add(const Duration(minutes: 1)));
    await store.save(older);
    await store.save(newer);

    final List<WorkflowTask> tasks = await store.list();

    expect(tasks.map((WorkflowTask task) => task.id), <String>['newer', 'older']);
  });

  test('encodes task IDs instead of using them as paths', () async {
    final WorkflowTask task = createTask(id: '../../outside');

    await store.save(task);

    expect(await store.load(task.id), isNotNull);
    expect(await File(path.join(temporaryDirectory.path, 'outside', 'task.json')).exists(), isFalse);
  });

  test('rejects an empty task ID when loading', () async {
    expect(() => store.load(' '), throwsArgumentError);
  });
}
