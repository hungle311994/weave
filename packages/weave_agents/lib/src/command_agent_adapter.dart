import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:weave_security/weave_security.dart';

import 'agent_account.dart';
import 'agent_adapter.dart';
import 'agent_availability.dart';
import 'agent_definition.dart';
import 'agent_event.dart';
import 'agent_executable_locator.dart';
import 'agent_plan_usage.dart';
import 'agent_run_request.dart';
import 'claude_code_output_parser.dart';
import 'codex_output_parser.dart';
import 'codex_plan_usage.dart';
import 'mcp_server.dart';
import 'process_agent_execution.dart';

/// Runs any agent CLI described by an [AgentDefinition].
final class CommandAgentAdapter implements AgentAdapter {
  CommandAgentAdapter(
    this.definition, {
    AgentExecutableLocator? locator,
    Map<String, String>? environment,
    this.executionTimeout = const Duration(hours: 1),
    this._startProcess = Process.start,
  }) : _baseEnvironment = environment ?? Platform.environment,
       _locator = locator ?? AgentExecutableLocator(environment: environment);

  final AgentDefinition definition;
  final Duration executionTimeout;
  final Map<String, String> _baseEnvironment;
  final AgentExecutableLocator _locator;
  final ProcessStarter _startProcess;
  int _executionCount = 0;

  @override
  String get id => definition.id;

  @override
  String get displayName => definition.displayName;

  @override
  bool get supportsMcp => definition.supportsMcp;

  @override
  Future<AgentAvailability> checkAvailability() async {
    final String? executable = await _locator.locate(definition.executable);
    if (executable == null) {
      return AgentAvailability.unavailable(reason: '${definition.executable} was not found on this machine.');
    }

    try {
      final ProcessResult result = await Process.run(
        executable,
        definition.versionArguments,
        environment: _environment,
        includeParentEnvironment: false,
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      ).timeout(const Duration(seconds: 15));

      final String version = (result.stdout as String).trim();
      if (result.exitCode != 0 || version.isEmpty) {
        return AgentAvailability.unavailable(
          reason:
              '${definition.executable} version check exited with '
              '${result.exitCode}.',
          executablePath: executable,
        );
      }

      final String firstLine = version.split('\n').first;
      if (await _isSignedIn(executable) == false) {
        final String signIn = definition.signInCommandText ?? 'sign in to ${definition.executable}';
        return AgentAvailability.signInRequired(version: firstLine, executablePath: executable, signInCommand: signIn);
      }
      return AgentAvailability.available(version: firstLine, executablePath: executable);
    } on Object {
      return AgentAvailability.unavailable(reason: '${definition.executable} could not report its version.', executablePath: executable);
    }
  }

  @override
  bool get reportsPlanUsage => definition.reportsPlanUsage;

  /// Runs [AgentDefinition.planUsageArguments]. The report may name the
  /// account, so only the parsed percentages are kept; nothing is logged.
  @override
  Future<AgentPlanUsage> readPlanUsage() async {
    if (!definition.reportsPlanUsage) {
      throw AgentPlanUsageException('${definition.displayName} does not report plan usage.');
    }
    final String? executable = await _locator.locate(definition.executable);
    if (executable == null) {
      throw AgentPlanUsageException('${definition.executable} was not found on this machine.');
    }
    final List<AgentPlanUsageWindow> windows = switch (definition.planUsageFormat) {
      AgentPlanUsageFormat.text => await _readTextPlanUsage(executable),
      AgentPlanUsageFormat.codexAppServer => await _readCodexPlanUsage(executable),
    };
    if (windows.isEmpty) {
      // E.g. API-key billing, which has no plan windows.
      throw AgentPlanUsageException('${definition.displayName} reported no plan limits for this sign-in.');
    }
    return AgentPlanUsage(windows: windows, checkedAt: DateTime.now());
  }

  Future<List<AgentPlanUsageWindow>> _readTextPlanUsage(String executable) async {
    final ProcessResult result;
    try {
      result = await Process.run(executable, definition.planUsageArguments, environment: _environment, includeParentEnvironment: false, stdoutEncoding: const Utf8Codec(allowMalformed: true), stderrEncoding: const Utf8Codec(allowMalformed: true)).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw AgentPlanUsageException('${definition.displayName} took too long to report its usage.');
    } on ProcessException {
      throw AgentPlanUsageException('${definition.executable} could not be started.');
    }
    if (result.exitCode != 0) {
      throw AgentPlanUsageException('${definition.displayName} could not report its usage (exit ${result.exitCode}).');
    }
    String report = (result.stdout as String).trim();
    final String? field = definition.planUsageJsonField;
    if (field != null) {
      try {
        final Object? decoded = jsonDecode(report);
        report = decoded is Map<String, Object?> && decoded[field] is String ? decoded[field]! as String : '';
      } on FormatException {
        report = '';
      }
    }
    return AgentPlanUsage.parseWindows(report);
  }

  /// Asks the app server started by [AgentDefinition.planUsageArguments] for
  /// its rate limits over JSON-RPC on stdio, then stops it.
  Future<List<AgentPlanUsageWindow>> _readCodexPlanUsage(String executable) async {
    try {
      return parseCodexPlanUsage(await _appServerResponse(executable, definition.planUsageArguments, codexPlanUsageRequests, codexPlanUsageRequestId));
    } on ProcessException {
      throw AgentPlanUsageException('${definition.executable} could not be started.');
    } on TimeoutException {
      throw AgentPlanUsageException('${definition.displayName} took too long to report its usage.');
    } on StateError {
      throw AgentPlanUsageException('${definition.displayName} stopped before reporting its usage.');
    }
  }

  /// Starts an app server with [arguments], sends [requests] as JSON-RPC
  /// lines on stdin, and returns the response to [responseId]; the server is
  /// stopped afterwards.
  Future<Map<String, Object?>> _appServerResponse(String executable, List<String> arguments, List<Map<String, Object?>> requests, int responseId) async {
    final Process process = await Process.start(executable, List<String>.of(arguments), environment: _environment, includeParentEnvironment: false);
    unawaited(process.stderr.drain<void>());
    try {
      for (final Map<String, Object?> request in requests) {
        process.stdin.writeln(jsonEncode(request));
      }
      await process.stdin.flush();
      return await process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .map((String line) {
            try {
              final Object? decoded = jsonDecode(line);
              return decoded is Map<String, Object?> ? decoded : null;
            } on FormatException {
              return null;
            }
          })
          .firstWhere((Map<String, Object?>? message) => message?['id'] == responseId)
          .timeout(const Duration(seconds: 20))
          .then((Map<String, Object?>? message) => message!);
    } finally {
      process.kill();
      await process.stdin.close().catchError((Object _) {});
    }
  }

  @override
  AgentAccount? get account => definition.account;

  @override
  bool get supportsAccounts => definition.supportsAccounts;

  /// Runs [AgentDefinition.accountArguments]; only the email and plan are
  /// kept, and nothing is logged. Any failure reads as "unknown".
  @override
  Future<AgentAccountInfo?> readAccount() async {
    if (definition.accountFormat == AgentAccountFormat.none || definition.accountArguments.isEmpty) {
      return null;
    }
    final String? executable = await _locator.locate(definition.executable);
    if (executable == null) {
      return null;
    }
    try {
      switch (definition.accountFormat) {
        case AgentAccountFormat.none:
          return null;
        case AgentAccountFormat.authStatusJson:
          final ProcessResult result = await Process.run(executable, definition.accountArguments, environment: _environment, includeParentEnvironment: false, stdoutEncoding: const Utf8Codec(allowMalformed: true), stderrEncoding: const Utf8Codec(allowMalformed: true)).timeout(const Duration(seconds: 15));
          final Object? status = jsonDecode((result.stdout as String).trim());
          if (status is! Map<String, Object?>) {
            return null;
          }
          String? field(String? name) => name != null && status[name] is String && (status[name]! as String).isNotEmpty ? status[name]! as String : null;
          final AgentAccountInfo info = AgentAccountInfo(email: field(definition.accountEmailJsonField), plan: field(definition.accountPlanJsonField));
          return info.isEmpty ? null : info;
        case AgentAccountFormat.codexAppServer:
          return parseCodexAccount(await _appServerResponse(executable, definition.accountArguments, codexAccountRequests, codexAccountRequestId));
      }
    } on Object {
      return null;
    }
  }

  /// `true` or `false` from the agent's own auth status command, or `null`
  /// when the agent has none or its answer cannot be read. The output may
  /// name the account, so it is neither logged nor kept.
  Future<bool?> _isSignedIn(String executable) async {
    if (definition.authStatusArguments.isEmpty) {
      return null;
    }
    try {
      final ProcessResult result = await Process.run(executable, definition.authStatusArguments, environment: _environment, includeParentEnvironment: false, stdoutEncoding: const Utf8Codec(allowMalformed: true), stderrEncoding: const Utf8Codec(allowMalformed: true)).timeout(const Duration(seconds: 15));
      final String? field = definition.authStatusJsonField;
      if (field == null) {
        return result.exitCode == 0;
      }
      final Object? status = jsonDecode((result.stdout as String).trim());
      return status is Map<String, Object?> ? status[field] == true : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<AgentExecution> start(AgentRunRequest request) async {
    final String? executable = await _locator.locate(definition.executable);
    if (executable == null) {
      throw AgentStartException(
        '${definition.executable} was not found on this machine.',
        cause: StateError('missing executable'),
        stackTrace: StackTrace.current,
      );
    }

    // The MCP file may hold resolved tokens, so it lives in a private
    // temporary directory outside the repository and is removed afterwards.
    final Directory? mcpDirectory = request.mcpServers.isNotEmpty && definition.mcpFormat == AgentMcpFormat.jsonConfigFile ? await Directory.systemTemp.createTemp('weave-mcp-') : null;
    Future<void> cleanUp() async {
      if (mcpDirectory != null && await mcpDirectory.exists()) {
        await mcpDirectory.delete(recursive: true);
      }
    }

    try {
      String? mcpConfigFile;
      if (mcpDirectory != null) {
        final File file = File(path.join(mcpDirectory.path, 'mcp.json'));
        await file.writeAsString(encodeMcpConfigFile(request.mcpServers), flush: true);
        mcpConfigFile = file.path;
      }
      final Map<String, String> environment = _environment;
      _executionCount++;
      return await ProcessAgentExecution.start(
        executionId:
            '$id-${request.task.id}-${request.role.name}-'
            '$_executionCount',
        executable: executable,
        arguments: definition.buildArguments(request, mcpConfigFile: mcpConfigFile),
        workingDirectory: request.workingDirectory,
        input: definition.takesPromptArgument ? '' : request.instructions,
        parser: createOutputParser(definition.outputFormat),
        environment: environment,
        startProcess: _startProcess,
        timeout: executionTimeout,
        redactor: SecretRedactor.fromEnvironment(environment, additionalSecrets: <String>[for (final McpServerDefinition server in request.mcpServers) ...server.transport.secretValues]),
        onFinished: cleanUp,
        classifier: definition.failureClassifier,
      );
    } on Object {
      await cleanUp();
      rethrow;
    }
  }

  /// Parent environment without `GIT_*` overrides, with an extended `PATH`.
  Map<String, String> get _environment => <String, String>{
    for (final MapEntry<String, String>(:String key, :String value) in _baseEnvironment.entries)
      if (!key.toUpperCase().startsWith('GIT_')) key: value,
    ...definition.environment,
    'PATH': _locator.searchPath,
  };
}

/// A new parser for one execution in [format].
AgentOutputParser createOutputParser(AgentOutputFormat format) => switch (format) {
  AgentOutputFormat.text => TextOutputParser(),
  AgentOutputFormat.codexJsonl => CodexOutputParser(),
  AgentOutputFormat.claudeStreamJson => ClaudeCodeOutputParser(),
};

/// Streams every line and uses the whole output as the summary.
final class TextOutputParser implements AgentOutputParser {
  final StringBuffer _output = StringBuffer();

  @override
  Iterable<AgentEvent> parseLine(String line, DateTime timestamp) {
    _output.writeln(line);
    return line.trim().isEmpty ? const <AgentEvent>[] : <AgentEvent>[AgentOutputEvent(timestamp: timestamp, text: '$line\n')];
  }

  @override
  AgentEvent finish(int exitCode, DateTime timestamp) {
    final String output = _output.toString().trim();
    if (exitCode != 0) {
      return AgentFailedEvent(
        timestamp: timestamp,
        message: 'Agent exited with code $exitCode.',
        exitCode: exitCode,
      );
    }
    return AgentCompletedEvent(
      timestamp: timestamp,
      summary: output.isEmpty ? 'Agent finished without output.' : output,
    );
  }
}
