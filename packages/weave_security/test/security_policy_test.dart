import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_security/weave_security.dart';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceScope scope;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-security-test-');
    final Directory workspace = await Directory(path.join(temporaryDirectory.path, 'work space')).create();
    scope = await WorkspaceScope.resolve(workspace.path);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  group('WorkspaceScope', () {
    test('resolves the canonical root', () async {
      expect(scope.rootPath, await Directory(path.join(temporaryDirectory.path, 'work space')).resolveSymbolicLinks());
    });

    test('rejects relative and missing roots', () async {
      await expectLater(WorkspaceScope.resolve('relative'), throwsA(isA<ArgumentError>()));
      await expectLater(WorkspaceScope.resolve(path.join(temporaryDirectory.path, 'missing')), throwsA(isA<ArgumentError>()));
    });

    test('contains the root and paths below it', () {
      expect(scope.containsPath(scope.rootPath), isTrue);
      expect(scope.containsPath('lib/main.dart'), isTrue);
      expect(scope.containsPath(path.join(scope.rootPath, 'a b.txt')), isTrue);
    });

    test('rejects traversal, siblings, and empty paths', () {
      expect(scope.containsPath('../outside.txt'), isFalse);
      expect(scope.containsPath('lib/../../outside.txt'), isFalse);
      expect(scope.containsPath('${scope.rootPath}-sibling/file'), isFalse);
      expect(scope.containsPath('/etc/passwd'), isFalse);
      expect(scope.containsPath(' '), isFalse);
    });

    test('follows symlinks that point outside the workspace', () async {
      final Directory outside = await Directory(path.join(temporaryDirectory.path, 'outside')).create();
      await Link(path.join(scope.rootPath, 'escape')).create(outside.path);
      await Directory(path.join(scope.rootPath, 'inside')).create();

      expect(scope.containsPath('escape/secret.txt'), isTrue);
      expect(await scope.containsResolvedPath('escape/secret.txt'), isFalse);
      expect(await scope.containsResolvedPath('inside/new file.txt'), isTrue);
      expect(await scope.containsResolvedPath('missing/deep/file'), isTrue);
    });
  });

  group('SecurityPolicy', () {
    PolicyDecision evaluate(SandboxMode mode, GuardedOperation operation, {String? targetPath}) => SecurityPolicy(scope: scope, mode: mode).evaluate(OperationRequest(operation, targetPath: targetPath));

    test('read-only mode never changes the workspace', () {
      for (final GuardedOperation operation in <GuardedOperation>[GuardedOperation.writeFile, GuardedOperation.deleteFile, GuardedOperation.gitWrite, GuardedOperation.gitCommit, GuardedOperation.gitPush, GuardedOperation.gitDestructive]) {
        expect(evaluate(SandboxMode.readOnly, operation), PolicyDecision.deny, reason: operation.name);
      }
      expect(evaluate(SandboxMode.readOnly, GuardedOperation.readFile), PolicyDecision.allow);
      expect(evaluate(SandboxMode.readOnly, GuardedOperation.gitRead), PolicyDecision.allow);
      expect(evaluate(SandboxMode.readOnly, GuardedOperation.runCommand), PolicyDecision.requireApproval);
    });

    test('workspace-write mode allows edits inside the workspace', () {
      for (final GuardedOperation operation in <GuardedOperation>[GuardedOperation.readFile, GuardedOperation.writeFile, GuardedOperation.runCommand, GuardedOperation.gitRead, GuardedOperation.gitWrite]) {
        expect(evaluate(SandboxMode.workspaceWrite, operation, targetPath: 'lib/a.dart'), PolicyDecision.allow, reason: operation.name);
      }
    });

    test('sensitive operations always require approval', () {
      for (final GuardedOperation operation in <GuardedOperation>[GuardedOperation.deleteFile, GuardedOperation.network, GuardedOperation.gitCommit, GuardedOperation.gitPush, GuardedOperation.gitDestructive]) {
        expect(evaluate(SandboxMode.workspaceWrite, operation), PolicyDecision.requireApproval, reason: operation.name);
      }
    });

    test('access outside the workspace requires approval', () {
      expect(evaluate(SandboxMode.workspaceWrite, GuardedOperation.writeFile, targetPath: '../other/file.txt'), PolicyDecision.requireApproval);
      expect(evaluate(SandboxMode.readOnly, GuardedOperation.readFile, targetPath: '/etc/hosts'), PolicyDecision.requireApproval);
      expect(evaluate(SandboxMode.readOnly, GuardedOperation.writeFile, targetPath: '/etc/hosts'), PolicyDecision.deny);
    });
  });

  test('sandbox modes describe write access', () {
    expect(SandboxMode.readOnly.allowsWrites, isFalse);
    expect(SandboxMode.workspaceWrite.allowsWrites, isTrue);
  });
}
