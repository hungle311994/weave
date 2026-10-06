import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_git/weave_git.dart';

const String _sha = '0123456789abcdef0123456789abcdef01234567';
const String _hashes = '100644 100644 100644 $_sha $_sha';

final class _FakeGitCommandRunner implements GitCommandRunner {
  _FakeGitCommandRunner({this.topLevel, this.status = const GitCommandResult(exitCode: 0, stdout: '', stderr: '')});

  final GitCommandResult? topLevel;
  final GitCommandResult status;
  final List<({List<String> arguments, String workingDirectory})> calls = <({List<String> arguments, String workingDirectory})>[];

  @override
  Future<GitCommandResult> run(List<String> arguments, {required String workingDirectory}) async {
    calls.add((arguments: arguments, workingDirectory: workingDirectory));
    if (arguments.contains('rev-parse')) {
      return topLevel ?? GitCommandResult(exitCode: 0, stdout: '$workingDirectory\n', stderr: '');
    }
    if (arguments.contains('status')) {
      return status;
    }
    throw StateError('Unexpected Git command.');
  }
}

GitCommandResult _status(List<String> records) => GitCommandResult(exitCode: 0, stdout: records.map((String record) => '$record\x00').join(), stderr: '');

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-git-service-test-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  group('repository detection', () {
    test('returns the repository root reported by Git', () async {
      final _FakeGitCommandRunner runner = _FakeGitCommandRunner(
        topLevel: const GitCommandResult(exitCode: 0, stdout: '/projects/my repo\n', stderr: ''),
      );
      final GitRepositoryService service = GitRepositoryService(runner: runner);

      final String root = await service.findRepositoryRoot(temporaryDirectory.path);

      expect(root, '/projects/my repo');
      expect(await service.isRepository(temporaryDirectory.path), isTrue);
      expect(runner.calls.first.workingDirectory, temporaryDirectory.path);
      expect(runner.calls.first.arguments, <String>['--no-optional-locks', '-c', 'core.fsmonitor=false', 'rev-parse', '--show-toplevel']);
    });

    test('reports a non-repository directory', () async {
      final GitRepositoryService service = GitRepositoryService(
        runner: _FakeGitCommandRunner(
          topLevel: const GitCommandResult(
            exitCode: 128,
            stdout: '',
            stderr:
                'fatal: not a git repository (or any of the parent '
                'directories): .git\n',
          ),
        ),
      );

      expect(await service.isRepository(temporaryDirectory.path), isFalse);
      await expectLater(service.findRepositoryRoot(temporaryDirectory.path), throwsA(isA<GitNotRepositoryException>()));
      await expectLater(service.readSnapshot(temporaryDirectory.path), throwsA(isA<GitNotRepositoryException>()));
    });

    test('raises a command failure for other rev-parse errors', () async {
      final GitRepositoryService service = GitRepositoryService(
        runner: _FakeGitCommandRunner(
          topLevel: const GitCommandResult(exitCode: 128, stdout: '', stderr: 'fatal: detected dubious ownership in repository\n'),
        ),
      );

      await expectLater(service.isRepository(temporaryDirectory.path), throwsA(isA<GitCommandException>().having((GitCommandException error) => error.exitCode, 'exitCode', 128)));
    });

    test('rejects an invalid repository root', () async {
      final GitRepositoryService service = GitRepositoryService(
        runner: _FakeGitCommandRunner(
          topLevel: const GitCommandResult(exitCode: 0, stdout: 'relative/root\n', stderr: ''),
        ),
      );

      await expectLater(service.findRepositoryRoot(temporaryDirectory.path), throwsA(isA<GitOutputFormatException>()));
    });

    test('validates the working directory before running Git', () async {
      final _FakeGitCommandRunner runner = _FakeGitCommandRunner();
      final GitRepositoryService service = GitRepositoryService(runner: runner);
      final File file = File(path.join(temporaryDirectory.path, 'file.txt'))..writeAsStringSync('content');

      for (final String directory in <String>['', '   ', 'relative/path', '/tmp/with\x00nul', path.join(temporaryDirectory.path, 'missing'), file.path]) {
        await expectLater(service.isRepository(directory), throwsA(isA<GitWorkingDirectoryException>()), reason: directory);
      }
      expect(runner.calls, isEmpty);
    });
  });

  group('snapshot', () {
    Future<GitRepositorySnapshot> readSnapshot(List<String> records) => GitRepositoryService(runner: _FakeGitCommandRunner(status: _status(records))).readSnapshot(temporaryDirectory.path);

    test('runs a read-only machine-readable status at the root', () async {
      final _FakeGitCommandRunner runner = _FakeGitCommandRunner(status: _status(<String>['# branch.oid $_sha', '# branch.head main']));

      await GitRepositoryService(runner: runner).readSnapshot(temporaryDirectory.path);

      expect(runner.calls.last.workingDirectory, temporaryDirectory.path);
      expect(runner.calls.last.arguments, <String>['--no-optional-locks', '-c', 'core.fsmonitor=false', 'status', '--porcelain=v2', '--branch', '-z', '--untracked-files=all']);
    });

    test('reads a clean repository on a branch', () async {
      final GitRepositorySnapshot snapshot = await readSnapshot(<String>['# branch.oid $_sha', '# branch.head feature/login', '# branch.upstream origin/feature/login', '# branch.ab +1 -0']);

      expect(snapshot.rootPath, temporaryDirectory.path);
      expect(snapshot.head.branch, 'feature/login');
      expect(snapshot.head.commitSha, _sha);
      expect(snapshot.head.isDetached, isFalse);
      expect(snapshot.head.isUnborn, isFalse);
      expect(snapshot.isClean, isTrue);
    });

    test('reads a detached HEAD', () async {
      final GitRepositorySnapshot snapshot = await readSnapshot(<String>['# branch.oid $_sha', '# branch.head (detached)']);

      expect(snapshot.head.branch, isNull);
      expect(snapshot.head.commitSha, _sha);
      expect(snapshot.head.isDetached, isTrue);
    });

    test('reads an unborn branch before the first commit', () async {
      final GitRepositorySnapshot snapshot = await readSnapshot(<String>['# branch.oid (initial)', '# branch.head main', '? README.md']);

      expect(snapshot.head.branch, 'main');
      expect(snapshot.head.commitSha, isNull);
      expect(snapshot.head.isUnborn, isTrue);
      expect(snapshot.untrackedFiles.single.path, 'README.md');
    });

    test('separates staged, unstaged, and untracked changes', () async {
      final GitRepositorySnapshot snapshot = await readSnapshot(<String>['# branch.oid $_sha', '# branch.head main', '1 A. N... 000000 100644 100644 $_sha $_sha lib/added.dart', '1 .M N... $_hashes lib/edited.dart', '1 MD N... $_hashes lib/both.dart', '1 .T N... $_hashes tool/link', '? notes/todo.md']);

      expect(snapshot.isClean, isFalse);
      expect(snapshot.stagedChanges.map((GitTrackedChange change) => change.path), orderedEquals(<String>['lib/added.dart', 'lib/both.dart']));
      expect(snapshot.unstagedChanges.map((GitTrackedChange change) => change.path), orderedEquals(<String>['lib/edited.dart', 'lib/both.dart', 'tool/link']));
      expect(snapshot.untrackedFiles.single.path, 'notes/todo.md');

      final GitTrackedChange both = snapshot.entries[2] as GitTrackedChange;
      expect(both.stagedChange, GitChangeType.modified);
      expect(both.unstagedChange, GitChangeType.deleted);
      expect((snapshot.entries[3] as GitTrackedChange).unstagedChange, GitChangeType.typeChanged);
    });

    test('preserves spaces in file names and rename sources', () async {
      final GitRepositorySnapshot snapshot = await readSnapshot(<String>['# branch.oid $_sha', '# branch.head main', '1 .M N... $_hashes docs/release notes.md', '2 R. N... $_hashes R100 new  name .txt', ' old name.txt', '? untracked dir/ leading space']);

      expect(snapshot.entries.map((GitStatusEntry entry) => entry.path), orderedEquals(<String>['docs/release notes.md', 'new  name .txt', 'untracked dir/ leading space']));
      final GitTrackedChange renamed = snapshot.entries[1] as GitTrackedChange;
      expect(renamed.stagedChange, GitChangeType.renamed);
      expect(renamed.originalPath, ' old name.txt');
    });

    test('reads conflicted files separately from staged changes', () async {
      final GitRepositorySnapshot snapshot = await readSnapshot(<String>['# branch.oid $_sha', '# branch.head main', 'u UU N... 100644 100644 100644 100644 $_sha $_sha $_sha a file.dart']);

      expect(snapshot.stagedChanges, isEmpty);
      expect(snapshot.unstagedChanges, isEmpty);
      expect(snapshot.conflictedFiles.single.path, 'a file.dart');
      expect(snapshot.conflictedFiles.single.conflict, GitConflictType.bothModified);
    });

    test('raises a command failure without exposing Git output', () async {
      final GitRepositoryService service = GitRepositoryService(
        runner: _FakeGitCommandRunner(
          status: const GitCommandResult(exitCode: 128, stdout: '', stderr: 'fatal: index file corrupt: secret/path.txt'),
        ),
      );

      await expectLater(service.readSnapshot(temporaryDirectory.path), throwsA(isA<GitCommandException>().having((GitCommandException error) => error.exitCode, 'exitCode', 128).having((GitCommandException error) => error.toString(), 'toString', allOf(contains('git status'), isNot(contains('secret'))))));
    });

    test('rejects malformed status output', () async {
      const List<String> head = <String>['# branch.oid $_sha', '# branch.head main'];
      final List<List<String>> malformedOutputs = <List<String>>[
        <String>[],
        <String>['# branch.head main'],
        <String>['# branch.oid not-a-sha', '# branch.head main'],
        <String>['# branch.oid (initial)', '# branch.head (detached)'],
        <String>[...head, '1 .M N... too few fields'],
        <String>[...head, '1 .X N... $_hashes file.txt'],
        <String>[...head, '2 R. N... $_hashes R100 missing-source'],
        <String>[...head, 'u ZZ N... 100644 100644 100644 100644 $_sha $_sha $_sha f'],
        <String>[...head, 'x unknown'],
      ];

      for (final List<String> records in malformedOutputs) {
        await expectLater(readSnapshot(records), throwsA(isA<GitOutputFormatException>()), reason: records.join(' | '));
      }
    });
  });

  test('describes commands without option values', () {
    expect(describeGitCommand(<String>['-c', 'user.name=secret', 'status', '--short']), 'git status');
    expect(describeGitCommand(<String>['--version']), 'git');
  });
}
