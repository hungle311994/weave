import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_git/weave_git.dart';
import 'package:weave_security/weave_security.dart';

/// Exercises real Git inside disposable directories only.
void main() {
  late Directory temporaryDirectory;
  late Directory home;
  late Map<String, String> environment;
  late GitRepositoryService service;

  Future<String> git(List<String> arguments, String workingDirectory) async {
    final ProcessResult result = await Process.run('git', <String>['-c', 'user.name=Weave Test', '-c', 'user.email=weave@example.com', '-c', 'commit.gpgsign=false', ...arguments], workingDirectory: workingDirectory, environment: environment, includeParentEnvironment: false);
    if (result.exitCode != 0) {
      fail('git ${arguments.first} failed: ${result.stderr}');
    }
    return result.stdout as String;
  }

  Future<Directory> createRepository() async {
    final Directory repository = await Directory(path.join(temporaryDirectory.path, 'my repo')).create();
    await git(<String>['init', '--quiet', '--initial-branch=main'], repository.path);
    return repository;
  }

  Future<void> commitAll(Directory repository, String message) async {
    await git(<String>['add', '--all'], repository.path);
    await git(<String>['commit', '--quiet', '-m', message], repository.path);
  }

  File fileIn(Directory repository, String name) => File(path.join(repository.path, name));

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-git-process-test-');
    home = await Directory(path.join(temporaryDirectory.path, 'home')).create();
    environment = <String, String>{'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin', 'HOME': home.path, 'XDG_CONFIG_HOME': home.path};
    service = GitRepositoryService(runner: ProcessGitCommandRunner(environment: environment));
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('detects a directory outside any repository', () async {
    final Directory outside = await Directory(path.join(temporaryDirectory.path, 'outside')).create();

    expect(await service.isRepository(outside.path), isFalse);
  });

  test('finds the root from a nested directory with spaces', () async {
    final Directory repository = await createRepository();
    final Directory nested = await Directory(path.join(repository.path, 'nested dir', 'deeper')).create(recursive: true);

    final String root = await service.findRepositoryRoot(nested.path);

    expect(await service.isRepository(nested.path), isTrue);
    expect(root, await repository.resolveSymbolicLinks());
  });

  test('reads an unborn branch with untracked files', () async {
    final Directory repository = await createRepository();
    fileIn(repository, 'first file.txt').writeAsStringSync('hello');

    final GitRepositorySnapshot snapshot = await service.readSnapshot(repository.path);

    expect(snapshot.head.branch, 'main');
    expect(snapshot.head.isUnborn, isTrue);
    expect(snapshot.untrackedFiles.single.path, 'first file.txt');
  });

  test('reads a clean branch and its HEAD commit', () async {
    final Directory repository = await createRepository();
    fileIn(repository, 'README.md').writeAsStringSync('weave');
    await commitAll(repository, 'Initial commit');
    final String headSha = (await git(<String>['rev-parse', 'HEAD'], repository.path)).trim();

    final GitRepositorySnapshot snapshot = await service.readSnapshot(repository.path);

    expect(snapshot.head.branch, 'main');
    expect(snapshot.head.commitSha, headSha);
    expect(snapshot.head.isDetached, isFalse);
    expect(snapshot.isClean, isTrue);
  });

  test('reads a detached HEAD', () async {
    final Directory repository = await createRepository();
    fileIn(repository, 'README.md').writeAsStringSync('weave');
    await commitAll(repository, 'Initial commit');
    final String headSha = (await git(<String>['rev-parse', 'HEAD'], repository.path)).trim();
    await git(<String>['checkout', '--quiet', '--detach'], repository.path);

    final GitRepositorySnapshot snapshot = await service.readSnapshot(repository.path);

    expect(snapshot.head.isDetached, isTrue);
    expect(snapshot.head.branch, isNull);
    expect(snapshot.head.commitSha, headSha);
  });

  test('reads staged, unstaged, and untracked files with spaces', () async {
    final Directory repository = await createRepository();
    fileIn(repository, 'tracked file.txt').writeAsStringSync('one');
    fileIn(repository, 'old name.txt').writeAsStringSync('rename me');
    await commitAll(repository, 'Initial commit');

    fileIn(repository, 'tracked file.txt').writeAsStringSync('two');
    await git(<String>['add', 'tracked file.txt'], repository.path);
    fileIn(repository, 'tracked file.txt').writeAsStringSync('three');
    await git(<String>['mv', 'old name.txt', 'new  name.txt'], repository.path);
    await Directory(path.join(repository.path, 'new dir')).create();
    fileIn(repository, 'new dir/ note .md').writeAsStringSync('draft');

    final GitRepositorySnapshot snapshot = await service.readSnapshot(repository.path);

    expect(snapshot.stagedChanges.map((GitTrackedChange change) => change.path), unorderedEquals(<String>['tracked file.txt', 'new  name.txt']));
    expect(snapshot.unstagedChanges.map((GitTrackedChange change) => change.path), <String>['tracked file.txt']);
    expect(snapshot.untrackedFiles.single.path, 'new dir/ note .md');
    final GitTrackedChange renamed = snapshot.stagedChanges.firstWhere((GitTrackedChange change) => change.path == 'new  name.txt');
    expect(renamed.stagedChange, GitChangeType.renamed);
    expect(renamed.originalPath, 'old name.txt');
  });

  test('does not modify the repository', () async {
    final Directory repository = await createRepository();
    fileIn(repository, 'tracked.txt').writeAsStringSync('one');
    await commitAll(repository, 'Initial commit');
    // A stat-only change makes a plain `git status` rewrite the index.
    fileIn(repository, 'tracked.txt')
      ..writeAsStringSync('one')
      ..setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    final String gitDirectory = path.join(repository.path, '.git');
    final Uint8List indexBefore = File(path.join(gitDirectory, 'index')).readAsBytesSync();
    final Set<String> entriesBefore = Directory(gitDirectory).listSync(recursive: true).map((FileSystemEntity entity) => entity.path).toSet();

    await service.readSnapshot(repository.path);

    expect(File(path.join(gitDirectory, 'index')).readAsBytesSync(), indexBefore);
    expect(Directory(gitDirectory).listSync(recursive: true).map((FileSystemEntity entity) => entity.path).toSet(), entriesBefore);
    expect(Directory(path.join(repository.path, '.agents')).existsSync(), isFalse);
  });

  group('readDiff', () {
    test('returns staged, unstaged, and untracked patches', () async {
      final Directory repository = await createRepository();
      fileIn(repository, 'staged file.txt').writeAsStringSync('one\n');
      fileIn(repository, 'edited.txt').writeAsStringSync('one\n');
      await commitAll(repository, 'Initial commit');
      fileIn(repository, 'staged file.txt').writeAsStringSync('two\n');
      await git(<String>['add', 'staged file.txt'], repository.path);
      fileIn(repository, 'edited.txt').writeAsStringSync('changed\n');
      fileIn(repository, 'new file.txt').writeAsStringSync('brand new\n');

      final GitDiff diff = await service.readDiff(repository.path);

      expect(diff.staged, allOf(contains('staged file.txt'), contains('+two')));
      expect(diff.unstaged, allOf(contains('edited.txt'), contains('+changed')));
      expect(diff.untracked, allOf(contains('new file.txt'), contains('+brand new')));
      expect(diff.isTruncated, isFalse);
      expect(diff.patch, startsWith('diff --git'));
    });

    test('reads an empty diff for a clean repository', () async {
      final Directory repository = await createRepository();
      fileIn(repository, 'README.md').writeAsStringSync('weave');
      await commitAll(repository, 'Initial commit');

      final GitDiff diff = await service.readDiff(repository.path);

      expect(diff.isEmpty, isTrue);
      expect(diff.patch, isEmpty);
    });

    test('reads staged files before the first commit', () async {
      final Directory repository = await createRepository();
      fileIn(repository, 'first.txt').writeAsStringSync('first\n');
      await git(<String>['add', 'first.txt'], repository.path);

      expect((await service.readDiff(repository.path)).staged, contains('+first'));
    });

    test('never runs repository-configured diff programs', () async {
      final Directory repository = await createRepository();
      final File marker = File(path.join(temporaryDirectory.path, 'external-diff-ran'));
      final File script = File(path.join(temporaryDirectory.path, 'external-diff.sh'))..writeAsStringSync('#!/bin/sh\ntouch "${marker.path}"\n');
      await Process.run('chmod', <String>['755', script.path]);
      fileIn(repository, '.gitattributes').writeAsStringSync('*.txt diff=custom\n');
      fileIn(repository, 'a.txt').writeAsStringSync('one\n');
      await commitAll(repository, 'Initial commit');
      await git(<String>['config', 'diff.external', script.path], repository.path);
      await git(<String>['config', 'diff.custom.textconv', script.path], repository.path);
      fileIn(repository, 'a.txt').writeAsStringSync('two\n');
      fileIn(repository, 'b.txt').writeAsStringSync('new\n');

      final GitDiff diff = await service.readDiff(repository.path);

      expect(diff.unstaged, contains('+two'));
      expect(diff.untracked, contains('+new'));
      expect(marker.existsSync(), isFalse);
    });

    test('skips untracked symlinks that point outside the repository', () async {
      final Directory repository = await createRepository();
      final File secret = File(path.join(temporaryDirectory.path, 'secret.txt'))..writeAsStringSync('outside secret\n');
      await Link(path.join(repository.path, 'link.txt')).create(secret.path);
      fileIn(repository, 'regular.txt').writeAsStringSync('regular\n');

      final GitDiff diff = await service.readDiff(repository.path);

      expect(diff.untracked, contains('+regular'));
      expect(diff.patch, isNot(contains('outside secret')));
    });

    test('truncates large patches', () async {
      final Directory repository = await createRepository();
      for (int index = 0; index < 5; index++) {
        fileIn(repository, 'file $index.txt').writeAsStringSync('${'x' * 200}\n');
      }

      final GitDiff diff = await service.readDiff(repository.path, maxCharacters: 300);

      expect(diff.isTruncated, isTrue);
      expect(diff.patch.length, lessThanOrEqualTo(300));
      expect(() => service.readDiff(repository.path, maxCharacters: 0), throwsArgumentError);
    });
  });

  group('GitWriteService', () {
    late GitWriteService writer;
    final List<GitWriteRequest> requests = <GitWriteRequest>[];

    setUp(() {
      requests.clear();
      final ProcessGitCommandRunner runner = ProcessGitCommandRunner(environment: environment);
      writer = GitWriteService(
        runner: runner,
        reader: GitRepositoryService(runner: runner),
      );
    });

    Future<Directory> repositoryWithIdentity() async {
      final Directory repository = await createRepository();
      await git(<String>['config', 'user.name', 'Weave Test'], repository.path);
      await git(<String>['config', 'user.email', 'weave@example.com'], repository.path);
      await git(<String>['config', 'commit.gpgsign', 'false'], repository.path);
      return repository;
    }

    test('commits every change after approval', () async {
      final Directory repository = await repositoryWithIdentity();
      fileIn(repository, 'README.md').writeAsStringSync('weave');
      await commitAll(repository, 'Initial commit');
      fileIn(repository, 'README.md').writeAsStringSync('changed');
      fileIn(repository, 'new file.txt').writeAsStringSync('new');
      const String message = 'Add "quoted" \$(whoami); `rm -rf /`\n\nBody line';

      final GitCommitResult result = await writer.commitAll(
        repository.path,
        message: message,
        approve: (GitWriteRequest request) async {
          requests.add(request);
          return true;
        },
      );

      expect(requests.single.operation, GuardedOperation.gitCommit);
      expect(requests.single.summary, 'Commit 2 files to main');
      expect(requests.single.paths, <String>['README.md', 'new file.txt']);
      expect(result.branch, 'main');
      expect(result.commitSha, (await git(<String>['rev-parse', 'HEAD'], repository.path)).trim());
      expect(await git(<String>['log', '-1', '--format=%B'], repository.path), '$message\n\n');
      expect(await git(<String>['status', '--porcelain'], repository.path), isEmpty);
    });

    test('leaves the repository untouched when the commit is denied', () async {
      final Directory repository = await repositoryWithIdentity();
      fileIn(repository, 'new.txt').writeAsStringSync('new');

      await expectLater(writer.commitAll(repository.path, message: 'Add new.txt', approve: (GitWriteRequest request) async => false), throwsA(isA<GitApprovalDeniedException>()));

      expect(await git(<String>['status', '--porcelain'], repository.path), '?? new.txt\n');
      expect(File(path.join(repository.path, '.git', 'index')).existsSync(), isFalse);
    });

    test('refuses empty messages and clean repositories', () async {
      final Directory repository = await repositoryWithIdentity();
      fileIn(repository, 'README.md').writeAsStringSync('weave');
      await commitAll(repository, 'Initial commit');

      await expectLater(writer.commitAll(repository.path, message: 'Nothing', approve: (GitWriteRequest request) async => true), throwsA(isA<GitNothingToCommitException>()));
      await expectLater(writer.commitAll(repository.path, message: '  ', approve: (GitWriteRequest request) async => true), throwsArgumentError);
    });
  });

  test('ignores inherited Git environment overrides', () async {
    final Directory repository = await createRepository();
    final Directory outside = await Directory(path.join(temporaryDirectory.path, 'outside')).create();
    final GitRepositoryService redirected = GitRepositoryService(runner: ProcessGitCommandRunner(environment: <String, String>{...environment, 'GIT_DIR': path.join(repository.path, '.git'), 'GIT_WORK_TREE': repository.path}));

    expect(await redirected.isRepository(outside.path), isFalse);
  });

  test('raises a typed error when Git cannot start', () async {
    final ProcessGitCommandRunner runner = ProcessGitCommandRunner(executable: path.join(temporaryDirectory.path, 'missing-git'), environment: environment);

    await expectLater(runner.run(<String>['--version'], workingDirectory: temporaryDirectory.path), throwsA(isA<GitProcessStartException>()));
  });

  test('returns the exit code of a failing command', () async {
    final ProcessGitCommandRunner runner = ProcessGitCommandRunner(environment: environment);

    final GitCommandResult result = await runner.run(<String>['rev-parse', '--verify', '--quiet', 'refs/heads/missing'], workingDirectory: (await createRepository()).path);

    expect(result.exitCode, isNot(0));
  });

  test('stops a command that exceeds its timeout', () async {
    final ProcessGitCommandRunner runner = ProcessGitCommandRunner(executable: 'sleep', timeout: const Duration(milliseconds: 100), environment: environment);

    await expectLater(runner.run(<String>['5'], workingDirectory: temporaryDirectory.path), throwsA(isA<GitCommandTimeoutException>()));
  });

  test('rejects a relative working directory', () async {
    final ProcessGitCommandRunner runner = ProcessGitCommandRunner(environment: environment);

    await expectLater(runner.run(<String>['--version'], workingDirectory: 'relative'), throwsA(isA<GitWorkingDirectoryException>()));
  });
}
