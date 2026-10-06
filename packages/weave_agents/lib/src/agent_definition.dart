import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:weave_security/weave_security.dart';

import 'agent_event.dart';
import 'agent_failure_classifier.dart';
import 'agent_run_request.dart';
import 'mcp_server.dart';

/// How an agent CLI reports progress on stdout.
enum AgentOutputFormat {
  /// Plain text; the whole output becomes the summary on exit code 0.
  text('text'),

  /// `codex exec --json` events.
  codexJsonl('codex-jsonl'),

  /// `claude --print --output-format stream-json` messages.
  claudeStreamJson('claude-stream-json');

  const AgentOutputFormat(this.jsonName);

  final String jsonName;

  static AgentOutputFormat fromJsonName(String name) => values.firstWhere((AgentOutputFormat format) => format.jsonName == name, orElse: () => throw FormatException('Unknown output format "$name".'));
}

/// How an agent CLI receives MCP servers.
enum AgentMcpFormat {
  /// The agent cannot use MCP servers.
  none('none'),

  /// A `{"mcpServers": {...}}` file whose path fills `{mcpConfigFile}` in
  /// `mcpArguments`; `{mcpToolNames}` lists `mcp__<id>` for each server.
  jsonConfigFile('json-config-file'),

  /// One `-c mcp_servers.<id>.<key>=<TOML value>` override per setting.
  codexConfigOverrides('codex-config-overrides');

  const AgentMcpFormat(this.jsonName);

  final String jsonName;

  static AgentMcpFormat fromJsonName(String name) => values.firstWhere((AgentMcpFormat format) => format.jsonName == name, orElse: () => throw FormatException('Unknown MCP format "$name".'));
}

/// Describes how to run one agent CLI, so any tool can be added as data.
///
/// Arguments may contain `{workingDirectory}`, `{model}`, `{sessionId}`, and
/// `{prompt}` placeholders. They are replaced inside each argument
/// separately and never pass through a shell. Without `{prompt}`, the prompt
/// is written to stdin so it does not appear in the process list.
///
/// [sandboxArguments] must be declared for every [SandboxMode], even as an
/// empty list, so each definition states how it confines read-only roles.
final class AgentDefinition {
  AgentDefinition({
    required String id,
    required String displayName,
    required String executable,
    required Map<SandboxMode, List<String>> sandboxArguments,
    List<String> arguments = const <String>[],
    List<String> modelArguments = const <String>['--model', '{model}'],
    List<String> resumeArguments = const <String>[],
    List<String> trailingArguments = const <String>[],
    List<String> versionArguments = const <String>['--version'],
    this.outputFormat = AgentOutputFormat.text,
    this.mcpFormat = AgentMcpFormat.none,
    List<String> mcpArguments = const <String>[],
    List<String> authStatusArguments = const <String>[],
    this.authStatusJsonField,
    List<String> signInCommand = const <String>[],
    Map<AgentFailureKind, List<String>> failurePatterns = const <AgentFailureKind, List<String>>{},
    String? model,
  }) : id = _requireId(id),
       displayName = _requireText(displayName, 'displayName'),
       executable = _requireExecutable(executable),
       arguments = _requireArguments(arguments, 'arguments'),
       sandboxArguments = Map<SandboxMode, List<String>>.unmodifiable(
         <SandboxMode, List<String>>{
           for (final SandboxMode mode in SandboxMode.values)
             mode: _requireArguments(
               sandboxArguments[mode] ?? (throw ArgumentError.value(sandboxArguments, 'sandboxArguments', 'must declare ${mode.name}')),
               'sandboxArguments.${mode.name}',
             ),
         },
       ),
       modelArguments = _requireArguments(modelArguments, 'modelArguments'),
       resumeArguments = _requireArguments(resumeArguments, 'resumeArguments'),
       trailingArguments = _requireArguments(trailingArguments, 'trailingArguments'),
       versionArguments = _requireArguments(versionArguments, 'versionArguments'),
       mcpArguments = _requireArguments(mcpArguments, 'mcpArguments'),
       authStatusArguments = _requireArguments(authStatusArguments, 'authStatusArguments'),
       signInCommand = List<String>.unmodifiable(signInCommand),
       failurePatterns = Map<AgentFailureKind, List<String>>.unmodifiable(<AgentFailureKind, List<String>>{
         for (final MapEntry<AgentFailureKind, List<String>>(:AgentFailureKind key, :List<String> value) in failurePatterns.entries) key: List<String>.unmodifiable(_requirePatterns(value)),
       }),
       model = model == null ? null : _requireText(model, 'model');

  /// OpenAI Codex CLI; Codex enforces the sandbox itself and `exec` never
  /// escalates for approval.
  factory AgentDefinition.codex({String? model}) => AgentDefinition(
    id: 'codex',
    displayName: 'Codex',
    executable: 'codex',
    arguments: const <String>['exec', '--json', '--color', 'never', '--cd', '{workingDirectory}'],
    sandboxArguments: const <SandboxMode, List<String>>{
      SandboxMode.readOnly: <String>['--sandbox', 'read-only'],
      SandboxMode.workspaceWrite: <String>['--sandbox', 'workspace-write'],
    },
    resumeArguments: const <String>['resume', '{sessionId}'],
    trailingArguments: const <String>['-'],
    outputFormat: AgentOutputFormat.codexJsonl,
    mcpFormat: AgentMcpFormat.codexConfigOverrides,
    authStatusArguments: const <String>['login', 'status'],
    signInCommand: const <String>['codex', 'login'],
    model: model,
  );

  /// Claude Code CLI; `--restricted` removes command-running tools and
  /// confines file tools to the working directory, and anything that would
  /// prompt for permission is denied. `--strict-mcp-config` limits MCP to the
  /// servers Weave passes, whose tools are then allowed explicitly.
  factory AgentDefinition.claudeCode({String? model}) => AgentDefinition(
    id: 'claude-code',
    displayName: 'Claude Code',
    executable: 'claude',
    arguments: const <String>['--print', '--output-format', 'stream-json', '--verbose', '--restricted', '--permission-prompts', 'none', '--strict-mcp-config'],
    sandboxArguments: const <SandboxMode, List<String>>{
      SandboxMode.readOnly: <String>['--permission-mode', 'manual', '--disallowedTools', 'Edit,Write,NotebookEdit'],
      SandboxMode.workspaceWrite: <String>['--permission-mode', 'acceptEdits'],
    },
    resumeArguments: const <String>['--resume', '{sessionId}'],
    outputFormat: AgentOutputFormat.claudeStreamJson,
    mcpFormat: AgentMcpFormat.jsonConfigFile,
    mcpArguments: const <String>['--mcp-config', '{mcpConfigFile}', '--allowedTools', '{mcpToolNames}'],
    authStatusArguments: const <String>['auth', 'status'],
    authStatusJsonField: 'loggedIn',
    signInCommand: const <String>['claude', 'auth', 'login'],
    model: model,
  );

  factory AgentDefinition.fromJson(Map<String, Object?> json) {
    List<String> strings(String key, {List<String> fallback = const <String>[]}) {
      final Object? value = json[key];
      if (value == null) {
        return fallback;
      }
      if (value is! List<Object?> || value.any((Object? item) => item is! String)) {
        throw FormatException('$key must be a list of strings.');
      }
      return value.cast<String>();
    }

    String text(String key) {
      final Object? value = json[key];
      if (value is! String) {
        throw FormatException('$key must be a string.');
      }
      return value;
    }

    final Object? sandbox = json['sandboxArguments'];
    if (sandbox is! Map<String, Object?>) {
      throw const FormatException('sandboxArguments must be an object.');
    }
    final Object? model = json['model'];
    final Object? outputFormat = json['outputFormat'];
    final Object? mcpFormat = json['mcpFormat'];
    final Object? authStatusJsonField = json['authStatusJsonField'];
    final Object failurePatterns = json['failurePatterns'] ?? const <String, Object?>{};
    if (failurePatterns is! Map<String, Object?>) {
      throw const FormatException('failurePatterns must be an object.');
    }
    try {
      return AgentDefinition(
        id: text('id'),
        displayName: text('displayName'),
        executable: text('executable'),
        arguments: strings('arguments'),
        sandboxArguments: <SandboxMode, List<String>>{
          for (final SandboxMode mode in SandboxMode.values)
            if (sandbox[mode.name] case final List<Object?> values)
              mode: values.map((Object? value) {
                if (value is! String) {
                  throw FormatException('sandboxArguments.${mode.name} must contain strings.');
                }
                return value;
              }).toList(),
        },
        modelArguments: strings('modelArguments', fallback: const <String>['--model', '{model}']),
        resumeArguments: strings('resumeArguments'),
        trailingArguments: strings('trailingArguments'),
        versionArguments: strings('versionArguments', fallback: const <String>['--version']),
        outputFormat: outputFormat == null ? AgentOutputFormat.text : AgentOutputFormat.fromJsonName(outputFormat as String),
        mcpFormat: mcpFormat == null ? AgentMcpFormat.none : AgentMcpFormat.fromJsonName(mcpFormat as String),
        mcpArguments: strings('mcpArguments'),
        authStatusArguments: strings('authStatusArguments'),
        authStatusJsonField: authStatusJsonField as String?,
        signInCommand: strings('signInCommand'),
        failurePatterns: <AgentFailureKind, List<String>>{
          for (final MapEntry<String, Object?>(:String key, :Object? value) in failurePatterns.entries) AgentFailureKind.values.byName(key): value is List<Object?> && value.every((Object? item) => item is String) ? value.cast<String>() : throw FormatException('failurePatterns.$key must be a list of strings.'),
        },
        model: model as String?,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid agent definition: ${error.message}');
    } on TypeError {
      throw const FormatException('Invalid agent definition field type.');
    }
  }

  final String id;
  final String displayName;

  /// A bare command name searched on `PATH`, or an absolute path.
  final String executable;
  final List<String> arguments;
  final Map<SandboxMode, List<String>> sandboxArguments;
  final List<String> modelArguments;
  final List<String> resumeArguments;
  final List<String> trailingArguments;
  final List<String> versionArguments;
  final AgentOutputFormat outputFormat;
  final AgentMcpFormat mcpFormat;
  final List<String> mcpArguments;

  /// Checks sign-in without touching credentials, e.g. `auth status`; empty
  /// when the agent offers no such command.
  final List<String> authStatusArguments;

  /// A JSON field of the auth status output that must be `true`; when `null`
  /// a zero exit code means signed in.
  final String? authStatusJsonField;

  /// What the user runs in a terminal to sign in, e.g. `claude auth login`.
  final List<String> signInCommand;

  /// Extra regular expressions per failure kind, on top of the built-in ones.
  final Map<AgentFailureKind, List<String>> failurePatterns;

  AgentFailureClassifier get failureClassifier => AgentFailureClassifier(extraPatterns: failurePatterns);
  final String? model;

  bool get supportsMcp => mcpFormat != AgentMcpFormat.none;

  /// Whether the prompt is passed as an argument instead of on stdin.
  bool get takesPromptArgument => <String>[
    ...arguments,
    for (final List<String> values in sandboxArguments.values) ...values,
    ...resumeArguments,
    ...trailingArguments,
  ].any((String argument) => argument.contains('{prompt}'));

  /// The argument list for one run, in a fixed order: base, sandbox, MCP,
  /// model, resume, trailing.
  ///
  /// [mcpConfigFile] is required when the request has MCP servers and the
  /// format is [AgentMcpFormat.jsonConfigFile].
  List<String> buildArguments(AgentRunRequest request, {String? mcpConfigFile}) {
    final List<McpServerDefinition> servers = request.mcpServers;
    if (servers.isNotEmpty && !supportsMcp) {
      throw UnsupportedError('$displayName cannot use MCP servers.');
    }
    if (servers.isNotEmpty && mcpFormat == AgentMcpFormat.jsonConfigFile && mcpConfigFile == null) {
      throw ArgumentError.notNull('mcpConfigFile');
    }
    final Map<String, String> values = <String, String>{
      'workingDirectory': request.workingDirectory,
      'model': ?(request.model ?? model),
      'sessionId': ?request.resumeSessionId,
      'prompt': request.instructions,
      'mcpConfigFile': ?mcpConfigFile,
      'mcpToolNames': servers.map((McpServerDefinition server) => 'mcp__${server.id}').join(','),
    };
    String substitute(String argument) => argument.replaceAllMapped(_placeholder, (Match match) => values[match[1]!] ?? match[0]!);

    return <String>[
      ...arguments.map(substitute),
      ...sandboxArguments[request.sandboxMode]!.map(substitute),
      if (servers.isNotEmpty)
        ...switch (mcpFormat) {
          AgentMcpFormat.none => const <String>[],
          AgentMcpFormat.jsonConfigFile => mcpArguments.map(substitute),
          AgentMcpFormat.codexConfigOverrides => codexMcpOverrides(servers),
        },
      if ((request.model ?? model) != null) ...modelArguments.map(substitute),
      if (request.resumeSessionId != null) ...resumeArguments.map(substitute),
      ...trailingArguments.map(substitute),
    ];
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'displayName': displayName,
    'executable': executable,
    'arguments': arguments,
    'sandboxArguments': <String, List<String>>{
      for (final MapEntry<SandboxMode, List<String>>(:SandboxMode key, :List<String> value) in sandboxArguments.entries) key.name: value,
    },
    'modelArguments': modelArguments,
    'resumeArguments': resumeArguments,
    'trailingArguments': trailingArguments,
    'versionArguments': versionArguments,
    'outputFormat': outputFormat.jsonName,
    'mcpFormat': mcpFormat.jsonName,
    'mcpArguments': mcpArguments,
    'authStatusArguments': authStatusArguments,
    'authStatusJsonField': authStatusJsonField,
    'signInCommand': signInCommand,
    'failurePatterns': <String, List<String>>{for (final MapEntry<AgentFailureKind, List<String>>(:AgentFailureKind key, :List<String> value) in failurePatterns.entries) key.name: value},
    'model': model,
  };

  /// Returns a copy that runs [model], or the CLI default when `null`.
  AgentDefinition withModel(String? model) => AgentDefinition(
    id: id,
    displayName: displayName,
    executable: executable,
    arguments: arguments,
    sandboxArguments: sandboxArguments,
    modelArguments: modelArguments,
    resumeArguments: resumeArguments,
    trailingArguments: trailingArguments,
    versionArguments: versionArguments,
    outputFormat: outputFormat,
    mcpFormat: mcpFormat,
    mcpArguments: mcpArguments,
    authStatusArguments: authStatusArguments,
    authStatusJsonField: authStatusJsonField,
    signInCommand: signInCommand,
    failurePatterns: failurePatterns,
    model: model,
  );

  static final RegExp _placeholder = RegExp(r'\{(\w+)\}');
  static const Set<String> _knownPlaceholders = <String>{'workingDirectory', 'model', 'sessionId', 'prompt', 'mcpConfigFile', 'mcpToolNames'};
  static final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

  static List<String> _requirePatterns(List<String> patterns) {
    for (final String pattern in patterns) {
      try {
        RegExp(pattern);
      } on FormatException {
        throw ArgumentError.value(pattern, 'failurePatterns', 'must be valid regular expressions');
      }
    }
    return patterns;
  }

  static String _requireId(String value) {
    if (!_idPattern.hasMatch(value)) {
      throw ArgumentError.value(value, 'id', 'must be lowercase letters, digits, ".", "_" or "-"');
    }
    return value;
  }

  static String _requireExecutable(String value) {
    final String executable = _requireText(value, 'executable');
    if (!path.isAbsolute(executable) && executable.contains('/')) {
      throw ArgumentError.value(value, 'executable', 'must be a bare command name or an absolute path');
    }
    return executable;
  }

  static List<String> _requireArguments(List<String> values, String name) {
    for (final String value in values) {
      if (value.contains('\x00')) {
        throw ArgumentError.value(value, name, 'must not contain NUL');
      }
      for (final RegExpMatch match in _placeholder.allMatches(value)) {
        if (!_knownPlaceholders.contains(match[1])) {
          throw ArgumentError.value(value, name, 'uses unknown placeholder ${match[0]}');
        }
      }
    }
    return List<String>.unmodifiable(values);
  }

  static String _requireText(String value, String name) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }
}

/// `{"mcpServers": {...}}`, the MCP configuration file format used by Claude
/// Code and other agents.
String encodeMcpConfigFile(Iterable<McpServerDefinition> servers) => jsonEncode(<String, Object?>{
  'mcpServers': <String, Object?>{
    for (final McpServerDefinition server in servers)
      server.id: switch (server.transport) {
        McpStdioTransport(:final String command, :final List<String> arguments, :final Map<String, String> environment) => <String, Object?>{'type': 'stdio', 'command': command, 'args': arguments, 'env': environment},
        McpHttpTransport(:final String url, :final Map<String, String> headers) => <String, Object?>{'type': 'http', 'url': url, 'headers': headers},
      },
  },
});

/// Codex `-c` overrides; JSON strings and arrays are valid TOML values.
List<String> codexMcpOverrides(Iterable<McpServerDefinition> servers) {
  String table(Map<String, String> values) => '{${values.entries.map((MapEntry<String, String> entry) => '${jsonEncode(entry.key)} = ${jsonEncode(entry.value)}').join(', ')}}';
  return <String>[
    for (final McpServerDefinition server in servers)
      ...switch (server.transport) {
        McpStdioTransport(:final String command, :final List<String> arguments, :final Map<String, String> environment) => <String>[
          '-c',
          'mcp_servers.${server.id}.command=${jsonEncode(command)}',
          '-c',
          'mcp_servers.${server.id}.args=${jsonEncode(arguments)}',
          if (environment.isNotEmpty) ...<String>['-c', 'mcp_servers.${server.id}.env=${table(environment)}'],
        ],
        McpHttpTransport(:final String url, :final Map<String, String> headers) => <String>[
          '-c',
          'mcp_servers.${server.id}.url=${jsonEncode(url)}',
          if (headers.isNotEmpty) ...<String>['-c', 'mcp_servers.${server.id}.http_headers=${table(headers)}'],
        ],
      },
  ];
}
