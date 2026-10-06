import 'security_policy.dart';

/// Classifies a Git argument list (without the `git` executable).
///
/// Unknown subcommands are treated as destructive so they always need
/// approval.
GuardedOperation classifyGitArguments(List<String> arguments) {
  final List<String> remaining = _skipGlobalOptions(arguments);
  if (remaining.isEmpty) {
    return GuardedOperation.gitRead;
  }

  final String subcommand = remaining.first;
  final List<String> options = remaining.skip(1).toList();
  bool has(Iterable<String> flags) => options.any(flags.contains);
  final Iterable<String> positionals = options.where((String option) => !option.startsWith('-'));

  return switch (subcommand) {
    '--version' || 'version' || 'help' || '--help' => GuardedOperation.gitRead,
    _ when _readSubcommands.contains(subcommand) => GuardedOperation.gitRead,
    'commit' => GuardedOperation.gitCommit,
    'push' => GuardedOperation.gitPush,
    'fetch' || 'pull' || 'clone' || 'ls-remote' => GuardedOperation.network,
    'add' || 'mv' || 'merge' || 'cherry-pick' || 'revert' || 'am' => GuardedOperation.gitWrite,
    'rm' || 'restore' || 'rebase' || 'gc' || 'prune' || 'filter-branch' || 'update-ref' => GuardedOperation.gitDestructive,
    'clean' => has(<String>['-n', '--dry-run']) ? GuardedOperation.gitRead : GuardedOperation.gitDestructive,
    'reset' => has(<String>['--hard', '--merge', '--keep']) ? GuardedOperation.gitDestructive : GuardedOperation.gitWrite,
    'checkout' || 'switch' => has(<String>['-f', '--force', '--', '.', '--discard-changes', '-B', '-C']) ? GuardedOperation.gitDestructive : GuardedOperation.gitWrite,
    'branch' =>
      has(<String>['-d', '-D', '--delete', '-f', '--force', '-M', '-m', '--move'])
          ? GuardedOperation.gitDestructive
          : positionals.isEmpty
          ? GuardedOperation.gitRead
          : GuardedOperation.gitWrite,
    'tag' =>
      has(<String>['-d', '--delete', '-f', '--force'])
          ? GuardedOperation.gitDestructive
          : positionals.isEmpty || has(<String>['-l', '--list'])
          ? GuardedOperation.gitRead
          : GuardedOperation.gitWrite,
    'stash' => switch (positionals.firstOrNull) {
      'list' || 'show' => GuardedOperation.gitRead,
      'drop' || 'clear' || 'pop' => GuardedOperation.gitDestructive,
      _ => GuardedOperation.gitWrite,
    },
    'worktree' => switch (positionals.firstOrNull) {
      'list' => GuardedOperation.gitRead,
      'add' || 'lock' || 'unlock' => GuardedOperation.gitWrite,
      _ => GuardedOperation.gitDestructive,
    },
    'config' => has(<String>['--get', '--get-all', '--get-regexp', '-l', '--list']) || (positionals.length == 1 && !has(<String>['--unset', '--unset-all'])) ? GuardedOperation.gitRead : GuardedOperation.gitWrite,
    _ => GuardedOperation.gitDestructive,
  };
}

const Set<String> _readSubcommands = <String>{'status', 'diff', 'log', 'show', 'rev-parse', 'rev-list', 'ls-files', 'ls-tree', 'cat-file', 'blame', 'describe', 'shortlog', 'grep', 'merge-base', 'show-ref', 'for-each-ref', 'reflog', 'symbolic-ref'};

const Set<String> _globalOptionsWithValue = <String>{'-c', '-C', '--git-dir', '--work-tree', '--namespace'};

List<String> _skipGlobalOptions(List<String> arguments) {
  int index = 0;
  while (index < arguments.length) {
    final String argument = arguments[index];
    if (_globalOptionsWithValue.contains(argument)) {
      index += 2;
    } else if (argument.startsWith('-') && argument != '--version' && argument != '--help') {
      index++;
    } else {
      break;
    }
  }
  return arguments.sublist(index.clamp(0, arguments.length));
}
