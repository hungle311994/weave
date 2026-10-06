import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'git_exceptions.dart';

/// Captured result of a finished Git command.
final class GitCommandResult {
  const GitCommandResult({required this.exitCode, required this.stdout, required this.stderr});

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Runs Git with an argument list; implementations must never use a shell.
abstract interface class GitCommandRunner {
  Future<GitCommandResult> run(List<String> arguments, {required String workingDirectory});
}

/// Runs the local Git executable as a child process.
///
/// Inherited `GIT_*` variables are removed so a parent environment cannot
/// redirect commands to another repository, index, or object store.
final class ProcessGitCommandRunner implements GitCommandRunner {
  ProcessGitCommandRunner({this.executable = 'git', this.timeout = const Duration(seconds: 30), Map<String, String>? environment}) : _environment = _sanitizeEnvironment(environment ?? Platform.environment);

  final String executable;
  final Duration timeout;
  final Map<String, String> _environment;

  @override
  Future<GitCommandResult> run(List<String> arguments, {required String workingDirectory}) async {
    if (!path.isAbsolute(workingDirectory)) {
      throw GitWorkingDirectoryException(workingDirectory, 'must be an absolute path');
    }

    final Process process;
    try {
      process = await Process.start(executable, List<String>.of(arguments), workingDirectory: workingDirectory, environment: _environment, includeParentEnvironment: false);
    } on ProcessException catch (error, stackTrace) {
      throw GitProcessStartException(executable, cause: error, stackTrace: stackTrace);
    }

    process.stdin.close().ignore();
    final Future<String> stdout = _readAll(process.stdout);
    final Future<String> stderr = _readAll(process.stderr);

    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      stdout.ignore();
      stderr.ignore();
      throw GitCommandTimeoutException(arguments, timeout);
    }

    return GitCommandResult(exitCode: exitCode, stdout: await stdout, stderr: await stderr);
  }

  static Future<String> _readAll(Stream<List<int>> stream) => const Utf8Decoder(allowMalformed: true).bind(stream).join();

  static Map<String, String> _sanitizeEnvironment(Map<String, String> environment) => Map<String, String>.unmodifiable(<String, String>{
    for (final MapEntry<String, String>(:String key, :String value) in environment.entries)
      if (!key.toUpperCase().startsWith('GIT_')) key: value,
    'LC_ALL': 'C',
    'GIT_TERMINAL_PROMPT': '0',
  });
}
