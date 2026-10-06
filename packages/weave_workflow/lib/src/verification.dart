import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:weave_agents/weave_agents.dart';
import 'package:weave_security/weave_security.dart';

/// A command Weave runs itself, such as an analyzer or test suite, so review
/// never depends on an agent claiming that checks passed.
final class VerificationCommand {
  VerificationCommand({
    required String executable,
    List<String> arguments = const <String>[],
    String? label,
    this.timeout = const Duration(minutes: 10),
  }) : executable = _requireText(executable, 'executable'),
       arguments = List<String>.unmodifiable(arguments),
       label = label == null ? <String>[executable.trim(), ...arguments].join(' ') : _requireText(label, 'label') {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
  }

  /// Splits [commandLine] into an executable and arguments without a shell.
  factory VerificationCommand.parse(
    String commandLine, {
    String? label,
    Duration timeout = const Duration(minutes: 10),
  }) {
    final List<String> words = splitCommandLine(commandLine);
    if (words.isEmpty) {
      throw const FormatException('A verification command must not be empty.');
    }
    return VerificationCommand(
      executable: words.first,
      arguments: words.skip(1).toList(),
      label: label,
      timeout: timeout,
    );
  }

  factory VerificationCommand.fromJson(Map<String, Object?> json) {
    final Object? executable = json['executable'];
    final Object arguments = json['arguments'] ?? const <Object?>[];
    final Object? label = json['label'];
    final Object timeoutSeconds = json['timeoutSeconds'] ?? 600;
    if (executable is! String || //
        arguments is! List<Object?> ||
        arguments.any((Object? argument) => argument is! String) ||
        (label != null && label is! String) ||
        timeoutSeconds is! int) {
      throw const FormatException('Invalid verification command.');
    }
    try {
      return VerificationCommand(
        executable: executable,
        arguments: arguments.cast<String>(),
        label: label as String?,
        timeout: Duration(seconds: timeoutSeconds),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid verification command: ${error.message}');
    }
  }

  final String executable;
  final List<String> arguments;
  final String label;
  final Duration timeout;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'executable': executable,
    'arguments': arguments,
    'timeoutSeconds': timeout.inSeconds,
  };

  static String _requireText(String value, String name) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }
}

/// Splits a command line into words with POSIX-like quoting only.
///
/// Single quotes are literal, double quotes allow `\"` and `\\`, and a
/// backslash outside quotes escapes the next character. Nothing is expanded,
/// and unquoted shell operators are rejected instead of being passed on.
List<String> splitCommandLine(String commandLine) {
  final List<String> words = <String>[];
  final StringBuffer current = StringBuffer();
  bool inWord = false;
  bool quoted = false;
  String? quote;

  void finishWord() {
    if (!inWord) {
      return;
    }
    final String word = current.toString();
    if (!quoted && _shellOperators.contains(word)) {
      throw FormatException('Shell operator "$word" is not supported; add each command separately.');
    }
    words.add(word);
    current.clear();
    inWord = false;
    quoted = false;
  }

  for (int index = 0; index < commandLine.length; index++) {
    final String character = commandLine[index];
    if (quote == "'") {
      character == "'" ? quote = null : current.write(character);
    } else if (quote == '"') {
      if (character == '"') {
        quote = null;
      } else if (character == r'\' && //
          index + 1 < commandLine.length &&
          (commandLine[index + 1] == '"' || commandLine[index + 1] == r'\')) {
        current.write(commandLine[++index]);
      } else {
        current.write(character);
      }
    } else if (character == "'" || character == '"') {
      quote = character;
      inWord = true;
      quoted = true;
    } else if (character == r'\') {
      if (index + 1 >= commandLine.length) {
        throw const FormatException('A command line must not end with a backslash.');
      }
      current.write(commandLine[++index]);
      inWord = true;
      quoted = true;
    } else if (character.trim().isEmpty) {
      finishWord();
    } else {
      current.write(character);
      inWord = true;
    }
  }

  if (quote != null) {
    throw const FormatException('A command line has an unterminated quote.');
  }
  finishWord();
  return words;
}

const Set<String> _shellOperators = <String>{'|', '||', '&', '&&', ';', '>', '>>', '<', '<<', '2>', '2>&1', '&>'};

/// The outcome of one [VerificationCommand].
final class VerificationResult {
  const VerificationResult({
    required this.command,
    required this.exitCode,
    required this.output,
    required this.duration,
    this.timedOut = false,
    this.startError,
  });

  final VerificationCommand command;

  /// `null` when the command could not start.
  final int? exitCode;

  /// The redacted tail of combined stdout and stderr.
  final String output;
  final Duration duration;
  final bool timedOut;
  final String? startError;

  bool get passed => exitCode == 0 && !timedOut && startError == null;
}

/// Runs verification commands for a workflow.
abstract interface class VerificationRunner {
  Future<VerificationResult> run(VerificationCommand command, {required String workingDirectory});
}

/// Runs verification commands as child processes, never through a shell.
final class ProcessVerificationRunner implements VerificationRunner {
  ProcessVerificationRunner({
    Map<String, String>? environment,
    SecretRedactor? redactor,
    this.maxOutputCharacters = 8000,
    this.cancelGracePeriod = const Duration(seconds: 5),
  }) : _environment = environment ?? Platform.environment,
       _redactor = redactor ?? SecretRedactor.fromEnvironment(environment ?? Platform.environment) {
    if (maxOutputCharacters <= 0) {
      throw ArgumentError.value(maxOutputCharacters, 'maxOutputCharacters', 'must be positive');
    }
  }

  final Map<String, String> _environment;
  final SecretRedactor _redactor;
  final int maxOutputCharacters;
  final Duration cancelGracePeriod;

  @override
  Future<VerificationResult> run(
    VerificationCommand command, {
    required String workingDirectory,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final AgentExecutableLocator locator = AgentExecutableLocator(environment: _environment);
    final String? executable = await locator.locate(command.executable);
    if (executable == null) {
      return VerificationResult(
        command: command,
        exitCode: null,
        output: '',
        duration: stopwatch.elapsed,
        startError: '${command.executable} was not found.',
      );
    }

    final Process process;
    try {
      process = await Process.start(
        executable,
        command.arguments,
        workingDirectory: workingDirectory,
        environment: <String, String>{
          for (final MapEntry<String, String>(:String key, :String value) in _environment.entries)
            if (!key.toUpperCase().startsWith('GIT_')) key: value,
          'PATH': locator.searchPath,
        },
        includeParentEnvironment: false,
      );
    } on ProcessException catch (error) {
      return VerificationResult(
        command: command,
        exitCode: null,
        output: '',
        duration: stopwatch.elapsed,
        startError: 'Unable to start ${command.executable}: ${error.message}',
      );
    }

    process.stdin.close().ignore();
    final _TailBuffer output = _TailBuffer(maxOutputCharacters);
    final Utf8Decoder decoder = const Utf8Decoder(allowMalformed: true);
    final Future<List<void>> streams = Future.wait(
      <Future<void>>[
        process.stdout.transform(decoder).forEach(output.add),
        process.stderr.transform(decoder).forEach(output.add),
      ],
    );

    bool timedOut = false;
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(command.timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill(ProcessSignal.sigterm);
      exitCode = await process.exitCode.timeout(
        cancelGracePeriod,
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return process.exitCode;
        },
      );
    }
    // Grandchildren may keep the pipes open after a timeout.
    await streams.timeout(cancelGracePeriod, onTimeout: () => const <void>[]);

    return VerificationResult(
      command: command,
      exitCode: exitCode,
      output: _redactor.redact(output.toString()),
      duration: stopwatch.elapsed,
      timedOut: timedOut,
    );
  }
}

/// Keeps only the last characters of a long output.
final class _TailBuffer {
  _TailBuffer(this.limit);

  final int limit;
  final StringBuffer _buffer = StringBuffer();
  bool _truncated = false;

  void add(String text) {
    _buffer.write(text);
    if (_buffer.length > limit * 2) {
      final String tail = _buffer.toString().substring(_buffer.length - limit);
      _buffer
        ..clear()
        ..write(tail);
      _truncated = true;
    }
  }

  @override
  String toString() {
    final String text = _buffer.toString();
    if (!_truncated && text.length <= limit) {
      return text;
    }
    return '[earlier output truncated]\n${text.substring(text.length - limit.clamp(0, text.length))}';
  }
}

/// Markdown summary of [results] for the reviewer and the stored artifact.
String formatVerificationReport(List<VerificationResult> results) {
  if (results.isEmpty) {
    return 'No verification commands are configured.\n';
  }
  final StringBuffer report = StringBuffer();
  for (final VerificationResult result in results) {
    final String status = result.passed ? 'PASS' : 'FAIL';
    final String detail = result.startError ?? (result.timedOut ? 'timed out after ${result.command.timeout.inSeconds}s' : 'exit ${result.exitCode}');
    report.writeln('- $status `${result.command.label}` — $detail (${(result.duration.inMilliseconds / 1000).toStringAsFixed(1)}s)');
    if (!result.passed && result.output.trim().isNotEmpty) {
      report
        ..writeln()
        ..writeln('```text')
        ..writeln(result.output.trimRight())
        ..writeln('```');
    }
  }
  return report.toString();
}
