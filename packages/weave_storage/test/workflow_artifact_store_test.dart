import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_security/weave_security.dart';
import 'package:weave_storage/weave_storage.dart';

void main() {
  late Directory temporaryDirectory;
  late String workflowsDirectory;
  late FileWorkflowArtifactStore store;
  final DateTime createdAt = DateTime.utc(2026, 10, 6, 10);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-artifact-test-');
    workflowsDirectory = path.join(temporaryDirectory.path, 'workflows');
    store = FileWorkflowArtifactStore(
      workflowsDirectory: workflowsDirectory,
      redactor: SecretRedactor(knownSecrets: <String>['super-secret-value']),
      maxLogMessageLength: 64,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  group('artifacts', () {
    test('stores artifacts in cycle and phase order', () async {
      await store.writeArtifact('task-1', WorkflowArtifact(kind: WorkflowArtifactKind.review, cycle: 1, content: 'Looks good', createdAt: createdAt));
      await store.writeArtifact('task-1', WorkflowArtifact(kind: WorkflowArtifactKind.plan, cycle: 0, content: '# Plan\n\n- step  one\n', createdAt: createdAt));
      await store.writeArtifact('task-1', WorkflowArtifact(kind: WorkflowArtifactKind.implementation, cycle: 1, content: 'Done', createdAt: createdAt));

      final List<WorkflowArtifact> artifacts = await store.readArtifacts('task-1');

      expect(artifacts.map((WorkflowArtifact artifact) => (artifact.cycle, artifact.kind)), <(int, WorkflowArtifactKind)>[(0, WorkflowArtifactKind.plan), (1, WorkflowArtifactKind.implementation), (1, WorkflowArtifactKind.review)]);
      expect(artifacts.first.content, '# Plan\n\n- step  one\n');
      expect(artifacts.first.createdAt, createdAt);
    });

    test('replaces an artifact with the same kind and cycle', () async {
      await store.writeArtifact('task-1', WorkflowArtifact(kind: WorkflowArtifactKind.plan, cycle: 0, content: 'First', createdAt: createdAt));
      await store.writeArtifact('task-1', WorkflowArtifact(kind: WorkflowArtifactKind.plan, cycle: 0, content: 'Second', createdAt: createdAt));

      expect((await store.readArtifacts('task-1')).single.content, 'Second');
    });

    test('redacts secrets before writing artifacts', () async {
      await store.writeArtifact('task-1', WorkflowArtifact(kind: WorkflowArtifactKind.plan, cycle: 0, content: 'key super-secret-value', createdAt: createdAt));

      final Iterable<File> files = Directory(workflowsDirectory).listSync(recursive: true).whereType<File>();
      for (final File file in files) {
        expect(file.readAsStringSync(), isNot(contains('super-secret-value')));
      }
      expect((await store.readArtifacts('task-1')).single.content, 'key [REDACTED]');
    });

    test('returns no artifacts for an unknown task', () async {
      expect(await store.readArtifacts('missing'), isEmpty);
    });

    test('rejects malformed artifact files', () async {
      await store.writeArtifact('task-1', WorkflowArtifact(kind: WorkflowArtifactKind.plan, cycle: 0, content: 'Plan', createdAt: createdAt));
      final File file = Directory(workflowsDirectory).listSync(recursive: true).whereType<File>().single;
      file.writeAsStringSync('{"schemaVersion": 99}');

      await expectLater(store.readArtifacts('task-1'), throwsA(isA<WorkflowStorageFormatException>()));
    });

    test('rejects negative cycles', () {
      expect(() => WorkflowArtifact(kind: WorkflowArtifactKind.plan, cycle: -1, content: 'Plan', createdAt: createdAt), throwsArgumentError);
    });
  });

  group('log', () {
    WorkflowLogEntry entry(String message, {String source = 'weave'}) => WorkflowLogEntry(timestamp: createdAt, source: source, message: message);

    test('appends entries in order without awaiting each write', () async {
      final List<Future<void>> writes = <Future<void>>[for (int index = 0; index < 50; index++) store.appendLog('task-1', entry('event $index'))];
      await Future.wait(writes);

      final List<WorkflowLogEntry> log = await store.readLog('task-1');

      expect(log.map((WorkflowLogEntry entry) => entry.message), <String>[for (int index = 0; index < 50; index++) 'event $index']);
      expect(log.first.timestamp, createdAt);
    });

    test('redacts and truncates messages', () async {
      await store.appendLog('task-1', entry('token super-secret-value', source: 'planner'));
      await store.appendLog('task-1', entry('x' * 100));

      final List<WorkflowLogEntry> log = await store.readLog('task-1');

      expect(log.first.message, 'token [REDACTED]');
      expect(log.first.source, 'planner');
      expect(log.last.message, '${'x' * 64}\n[truncated]');
    });

    test('ignores a partially written final line', () async {
      await store.appendLog('task-1', entry('complete'));
      final File logFile = Directory(workflowsDirectory).listSync(recursive: true).whereType<File>().single;
      logFile.writeAsStringSync('{"timestamp": "2026', mode: FileMode.append);

      expect((await store.readLog('task-1')).single.message, 'complete');
    });

    test('rejects a corrupt line before the end', () async {
      await store.appendLog('task-1', entry('first'));
      final File logFile = Directory(workflowsDirectory).listSync(recursive: true).whereType<File>().single;
      logFile.writeAsStringSync('not json\n', mode: FileMode.append);
      await store.appendLog('task-1', entry('last'));

      await expectLater(store.readLog('task-1'), throwsA(isA<WorkflowStorageFormatException>()));
    });

    test('keeps task directories inside the workflows directory', () async {
      await store.appendLog('../../escape', entry('event'));

      expect(Directory(path.join(temporaryDirectory.path, 'escape')).existsSync(), isFalse);
      expect((await store.readLog('../../escape')).single.message, 'event');
      expect(() => store.appendLog(' ', entry('event')), throwsArgumentError);
    });
  });
}
