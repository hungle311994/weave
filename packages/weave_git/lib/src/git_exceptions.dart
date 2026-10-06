/// Base type for every failure raised by `weave_git`.
///
/// Messages never include Git output, so repository contents stay out of logs.
sealed class GitException implements Exception {
  const GitException(this.message);

  final String message;
}

/// Raised when a working directory is not usable for Git commands.
final class GitWorkingDirectoryException extends GitException {
  const GitWorkingDirectoryException(this.path, String reason) : super(reason);

  final String path;

  @override
  String toString() => 'GitWorkingDirectoryException: $path $message.';
}

/// Raised when a directory is not inside a Git working tree.
final class GitNotRepositoryException extends GitException {
  const GitNotRepositoryException(this.path) : super('Directory is not inside a Git repository');

  final String path;

  @override
  String toString() => 'GitNotRepositoryException: $message: $path';
}

/// Raised when the Git executable cannot be started.
final class GitProcessStartException extends GitException {
  const GitProcessStartException(this.executable, {required this.cause, required this.stackTrace}) : super('Unable to start Git');

  final String executable;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'GitProcessStartException: $message ($executable).';
}

/// Raised when a Git command exits with an unexpected status.
final class GitCommandException extends GitException {
  GitCommandException(List<String> arguments, this.exitCode) : arguments = List<String>.unmodifiable(arguments), super('${describeGitCommand(arguments)} exited with code $exitCode');

  final List<String> arguments;
  final int exitCode;

  @override
  String toString() => 'GitCommandException: $message.';
}

/// Raised when a Git command does not finish before its timeout.
final class GitCommandTimeoutException extends GitException {
  GitCommandTimeoutException(List<String> arguments, this.timeout)
    : arguments = List<String>.unmodifiable(arguments),
      super(
        '${describeGitCommand(arguments)} did not finish within '
        '${timeout.inMilliseconds} ms',
      );

  final List<String> arguments;
  final Duration timeout;

  @override
  String toString() => 'GitCommandTimeoutException: $message.';
}

/// Raised when Git output does not match the expected machine format.
final class GitOutputFormatException extends GitException {
  const GitOutputFormatException(super.message);

  @override
  String toString() => 'GitOutputFormatException: $message';
}

/// Names a Git command by its subcommand only, omitting option values.
String describeGitCommand(List<String> arguments) {
  for (int index = 0; index < arguments.length; index++) {
    final String argument = arguments[index];
    if (argument == '-c' || argument == '-C') {
      index++;
      continue;
    }
    if (!argument.startsWith('-')) {
      return 'git $argument';
    }
  }
  return 'git';
}
