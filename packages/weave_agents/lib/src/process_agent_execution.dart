import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:weave_security/weave_security.dart';

import 'agent_adapter.dart';
import 'agent_event.dart';
import 'agent_failure_classifier.dart';

/// Starts a child process; [Process.start] satisfies this signature.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
});

/// Converts one agent's stdout protocol into [AgentEvent]s.
abstract interface class AgentOutputParser {
  /// Non-terminal events for one stdout line, without its line terminator.
  Iterable<AgentEvent> parseLine(String line, DateTime timestamp);

  /// The single terminal event once the process has exited.
  AgentEvent finish(int exitCode, DateTime timestamp);
}

/// Raised when an agent process cannot be started.
final class AgentStartException implements Exception {
  const AgentStartException(this.message, {required this.cause, required this.stackTrace});

  final String message;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'AgentStartException: $message';
}

/// An agent running as a local child process.
///
/// The prompt is written to stdin so it never appears in the process list.
/// Every emitted event passes through a [SecretRedactor], and the stream
/// always ends with exactly one [AgentCompletedEvent] or [AgentFailedEvent].
final class ProcessAgentExecution implements AgentExecution {
  ProcessAgentExecution._({
    required this.executionId,
    required this._process,
    required this._parser,
    required this._redactor,
    required this._cancelGracePeriod,
    required this._clock,
    required this._classifier,
  });

  static Future<ProcessAgentExecution> start({
    required String executionId,
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required String input,
    required AgentOutputParser parser,
    Map<String, String>? environment,
    ProcessStarter startProcess = Process.start,
    SecretRedactor? redactor,
    Duration timeout = const Duration(hours: 1),
    Duration cancelGracePeriod = const Duration(seconds: 5),
    DateTime Function() clock = DateTime.now,
    Future<void> Function()? onFinished,
    AgentFailureClassifier? classifier,
  }) async {
    final Process process;
    try {
      process = await startProcess(
        executable,
        List<String>.of(arguments),
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: environment == null,
      );
    } on ProcessException catch (error, stackTrace) {
      throw AgentStartException('Unable to start $executable.', cause: error, stackTrace: stackTrace);
    }

    final ProcessAgentExecution execution = ProcessAgentExecution._(
      executionId: executionId,
      process: process,
      parser: parser,
      redactor: redactor ?? SecretRedactor.fromEnvironment(environment ?? Platform.environment),
      cancelGracePeriod: cancelGracePeriod,
      clock: clock,
      classifier: classifier ?? AgentFailureClassifier(),
    );
    execution._run(input, timeout, onFinished);
    return execution;
  }

  @override
  final String executionId;

  final Process _process;
  final AgentOutputParser _parser;
  final SecretRedactor _redactor;
  final Duration _cancelGracePeriod;
  final DateTime Function() _clock;
  final AgentFailureClassifier _classifier;
  final StreamController<AgentEvent> _events = StreamController<AgentEvent>();
  String? _stopReason;
  AgentFailureKind _stopKind = AgentFailureKind.unknown;

  /// The end of stderr, kept to classify a failure; never emitted again.
  final StringBuffer _diagnostics = StringBuffer();

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> resolveApproval({required String approvalId, required ApprovalDecision decision}) async {
    throw UnsupportedError('This agent runs non-interactively and never requests approval.');
  }

  @override
  Future<void> cancel() => _stop('Cancelled by user.', AgentFailureKind.cancelled);

  /// [onFinished] runs once the process has exited, before the terminal event,
  /// so temporary files are gone when listeners see the result.
  Future<void> _run(String input, Duration timeout, Future<void> Function()? onFinished) async {
    final Timer timer = Timer(timeout, () => _stop('Timed out after ${timeout.inSeconds} seconds.', AgentFailureKind.timeout));

    _process.stdin.add(utf8.encode(input));
    _process.stdin.close().ignore();

    final Future<void> stdoutDone = _process.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).forEach((String line) {
      if (_stopReason == null) {
        _parser.parseLine(line, _clock()).forEach(_emit);
      }
    });
    final Future<void> stderrDone = _process.stderr.transform(const Utf8Decoder(allowMalformed: true)).forEach((String text) {
      _diagnostics.write(text);
      if (_diagnostics.length > 8192) {
        final String tail = _diagnostics.toString().substring(_diagnostics.length - 4096);
        _diagnostics
          ..clear()
          ..write(tail);
      }
      if (_stopReason == null && text.trim().isNotEmpty) {
        _emit(AgentOutputEvent(timestamp: _clock(), text: text, channel: AgentOutputChannel.stderr));
      }
    });

    AgentEvent terminal;
    try {
      final int exitCode = await _process.exitCode;
      await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
      final String? stopReason = _stopReason;
      terminal = stopReason == null ? _classified(_parser.finish(exitCode, _clock())) : AgentFailedEvent(timestamp: _clock(), message: stopReason, exitCode: exitCode, kind: _stopKind);
    } on Object {
      _process.kill(ProcessSignal.sigkill);
      terminal = AgentFailedEvent(timestamp: _clock(), message: 'Agent output could not be processed.');
    } finally {
      timer.cancel();
    }

    try {
      await onFinished?.call();
    } on Object {
      // Cleanup is best effort and must not change the agent's result.
    }
    _emit(terminal);
    await _events.close();
  }

  /// Fills in the failure kind from the message and recent stderr.
  AgentEvent _classified(AgentEvent event) => switch (event) {
    AgentFailedEvent(kind: AgentFailureKind.unknown, :final DateTime timestamp, :final String message, :final int? exitCode, :final String? sessionId, :final AgentUsage? usage) => AgentFailedEvent(
      timestamp: timestamp,
      message: message,
      exitCode: exitCode,
      kind: _classifier.classify('$message\n$_diagnostics'),
      sessionId: sessionId,
      usage: usage,
    ),
    _ => event,
  };

  Future<void> _stop(String reason, AgentFailureKind kind) async {
    if (_stopReason != null) {
      await _process.exitCode;
      return;
    }
    _stopReason = reason;
    _stopKind = kind;
    _process.kill(ProcessSignal.sigterm);
    await _process.exitCode.timeout(
      _cancelGracePeriod,
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return _process.exitCode;
      },
    );
  }

  void _emit(AgentEvent event) {
    if (!_events.isClosed) {
      _events.add(redactAgentEvent(event, _redactor));
    }
  }
}

/// Returns [event] with every free-text field passed through [redactor].
AgentEvent redactAgentEvent(AgentEvent event, SecretRedactor redactor) => switch (event) {
  AgentOutputEvent(
    :final DateTime timestamp,
    :final String text,
    :final AgentOutputChannel channel,
  ) =>
    AgentOutputEvent(
      timestamp: timestamp,
      text: redactor.redact(text),
      channel: channel,
    ),
  AgentApprovalRequestedEvent(
    :final DateTime timestamp,
    :final String approvalId,
    :final String action,
    :final String details,
  ) =>
    AgentApprovalRequestedEvent(
      timestamp: timestamp,
      approvalId: approvalId,
      action: redactor.redact(action),
      details: redactor.redact(details),
    ),
  AgentCompletedEvent(:final DateTime timestamp, :final String summary, :final String? sessionId, :final AgentUsage? usage) => AgentCompletedEvent(timestamp: timestamp, summary: redactor.redact(summary), sessionId: sessionId, usage: usage),
  AgentFailedEvent(:final DateTime timestamp, :final String message, :final int? exitCode, :final AgentFailureKind kind, :final String? sessionId, :final AgentUsage? usage) => AgentFailedEvent(timestamp: timestamp, message: redactor.redact(message), exitCode: exitCode, kind: kind, sessionId: sessionId, usage: usage),
};
