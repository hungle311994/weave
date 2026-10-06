import 'package:test/test.dart';
import 'package:weave_security/weave_security.dart';

void main() {
  void expectClassified(Map<String, GuardedOperation> cases) {
    for (final MapEntry<String, GuardedOperation>(key: String command, value: GuardedOperation expected) in cases.entries) {
      final List<String> arguments = command.isEmpty ? <String>[] : command.split(' ');
      expect(classifyGitArguments(arguments), expected, reason: command);
    }
  }

  test('classifies inspection commands as reads', () {
    expectClassified(<String, GuardedOperation>{
      '': GuardedOperation.gitRead,
      '--version': GuardedOperation.gitRead,
      'status --porcelain=v2 -z': GuardedOperation.gitRead,
      '--no-optional-locks -c core.fsmonitor=false status': GuardedOperation.gitRead,
      '-C /repo log --oneline': GuardedOperation.gitRead,
      'diff --cached': GuardedOperation.gitRead,
      'rev-parse --show-toplevel': GuardedOperation.gitRead,
      'branch': GuardedOperation.gitRead,
      'branch --show-current': GuardedOperation.gitRead,
      'tag --list': GuardedOperation.gitRead,
      'stash list': GuardedOperation.gitRead,
      'worktree list': GuardedOperation.gitRead,
      'clean -n': GuardedOperation.gitRead,
      'config --get user.name': GuardedOperation.gitRead,
      'config user.name': GuardedOperation.gitRead,
    });
  });

  test('classifies commits, pushes, and network access', () {
    expectClassified(<String, GuardedOperation>{'commit -m message': GuardedOperation.gitCommit, '-c user.name=x commit --amend': GuardedOperation.gitCommit, 'push origin main': GuardedOperation.gitPush, 'push --force': GuardedOperation.gitPush, 'fetch': GuardedOperation.network, 'pull --rebase': GuardedOperation.network});
  });

  test('classifies non-destructive local writes', () {
    expectClassified(<String, GuardedOperation>{
      'add --all': GuardedOperation.gitWrite,
      'reset HEAD file.txt': GuardedOperation.gitWrite,
      'checkout main': GuardedOperation.gitWrite,
      'switch -c feature': GuardedOperation.gitWrite,
      'branch feature': GuardedOperation.gitWrite,
      'tag v1.0.0': GuardedOperation.gitWrite,
      'stash push': GuardedOperation.gitWrite,
      'worktree add ../tree': GuardedOperation.gitWrite,
      'config user.name Weave': GuardedOperation.gitWrite,
    });
  });

  test('classifies discarding and history rewriting as destructive', () {
    expectClassified(<String, GuardedOperation>{
      'reset --hard HEAD': GuardedOperation.gitDestructive,
      'clean -fdx': GuardedOperation.gitDestructive,
      'checkout -- file.txt': GuardedOperation.gitDestructive,
      'checkout .': GuardedOperation.gitDestructive,
      'switch --discard-changes main': GuardedOperation.gitDestructive,
      'restore file.txt': GuardedOperation.gitDestructive,
      'rebase -i main': GuardedOperation.gitDestructive,
      'branch -D feature': GuardedOperation.gitDestructive,
      'tag -d v1': GuardedOperation.gitDestructive,
      'stash drop': GuardedOperation.gitDestructive,
      'worktree remove ../tree': GuardedOperation.gitDestructive,
      'rm file.txt': GuardedOperation.gitDestructive,
      'update-ref -d refs/heads/x': GuardedOperation.gitDestructive,
      'unknown-subcommand': GuardedOperation.gitDestructive,
      '-c': GuardedOperation.gitRead,
    });
  });
}
