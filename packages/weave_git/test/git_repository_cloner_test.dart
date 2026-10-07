import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_git/weave_git.dart';

const String _sha = '0123456789abcdef0123456789abcdef01234567';

final class _CloneRunner implements GitCommandRunner {
  _CloneRunner({this.cloneResult = const GitCommandResult(exitCode: 0, stdout: '', stderr: '')});

  final GitCommandResult cloneResult;
  final List<({List<String> arguments, String workingDirectory})> calls = <({List<String> arguments, String workingDirectory})>[];

  @override
  Future<GitCommandResult> run(List<String> arguments, {required String workingDirectory}) async {
    calls.add((arguments: List<String>.of(arguments), workingDirectory: workingDirectory));
    if (arguments.first == 'clone') {
      if (cloneResult.exitCode == 0) {
        await Directory(arguments.last).create();
      }
      return cloneResult;
    }
    if (arguments.contains('rev-parse')) {
      return GitCommandResult(exitCode: 0, stdout: '$workingDirectory\n', stderr: '');
    }
    if (arguments.contains('status')) {
      return const GitCommandResult(exitCode: 0, stdout: '# branch.oid $_sha\x00# branch.head main\x00', stderr: '');
    }
    throw StateError('Unexpected Git command.');
  }
}

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-git-cloner-test-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('clones into a new child and verifies the repository', () async {
    final _CloneRunner runner = _CloneRunner();
    final GitRepositoryCloner cloner = GitRepositoryCloner(
      runner: runner,
      reader: GitRepositoryService(runner: runner),
    );

    final GitRepositorySnapshot snapshot = await cloner.clone('https://github.com/example/weave.git', parentDirectory: temporaryDirectory.path);

    final String target = path.join(temporaryDirectory.path, 'weave');
    expect(snapshot.rootPath, target);
    expect(snapshot.head.branch, 'main');
    expect(runner.calls.first.arguments, <String>['clone', '--', 'https://github.com/example/weave.git', target]);
    expect(runner.calls.first.workingDirectory, temporaryDirectory.path);
  });

  test('chooses a non-conflicting target directory', () async {
    await Directory(path.join(temporaryDirectory.path, 'weave')).create();
    final _CloneRunner runner = _CloneRunner();
    final GitRepositoryCloner cloner = GitRepositoryCloner(
      runner: runner,
      reader: GitRepositoryService(runner: runner),
    );

    final GitRepositorySnapshot snapshot = await cloner.clone('git@example.com:team/weave.git', parentDirectory: temporaryDirectory.path);

    expect(snapshot.rootPath, path.join(temporaryDirectory.path, 'weave-2'));
  });

  test('rejects URLs that can carry credentials or options', () async {
    final _CloneRunner runner = _CloneRunner();
    final GitRepositoryCloner cloner = GitRepositoryCloner(
      runner: runner,
      reader: GitRepositoryService(runner: runner),
    );

    for (final String url in <String>[
      '',
      '-upload-pack=program',
      'http://github.com/example/weave.git',
      'https://token@github.com/example/weave.git',
      'https://github.com/example/weave.git?token=secret',
      'ssh://git:secret@example.com/team/weave.git',
    ]) {
      await expectLater(cloner.clone(url, parentDirectory: temporaryDirectory.path), throwsA(isA<FormatException>()), reason: url);
    }
    expect(runner.calls, isEmpty);
  });

  test('requires an existing absolute parent directory', () async {
    final _CloneRunner runner = _CloneRunner();
    final GitRepositoryCloner cloner = GitRepositoryCloner(
      runner: runner,
      reader: GitRepositoryService(runner: runner),
    );

    await expectLater(cloner.clone('https://github.com/example/weave.git', parentDirectory: 'relative'), throwsA(isA<FormatException>()));
    await expectLater(cloner.clone('https://github.com/example/weave.git', parentDirectory: path.join(temporaryDirectory.path, 'missing')), throwsA(isA<FormatException>()));
    expect(runner.calls, isEmpty);
  });

  test('does not expose Git stderr when cloning fails', () async {
    final _CloneRunner runner = _CloneRunner(
      cloneResult: const GitCommandResult(exitCode: 128, stdout: '', stderr: 'secret output'),
    );
    final GitRepositoryCloner cloner = GitRepositoryCloner(
      runner: runner,
      reader: GitRepositoryService(runner: runner),
    );

    await expectLater(
      cloner.clone('https://github.com/example/weave.git', parentDirectory: temporaryDirectory.path),
      throwsA(isA<GitCommandException>().having((GitCommandException error) => error.toString(), 'message', isNot(contains('secret output')))),
    );
  });
}
