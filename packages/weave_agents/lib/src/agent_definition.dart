import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:weave_security/weave_security.dart';

import 'agent_account.dart';
import 'agent_event.dart';
import 'agent_failure_classifier.dart';
import 'agent_plan_usage.dart';
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

/// One provider-published way to install an agent CLI.
final class AgentInstallOption {
  const AgentInstallOption({required this.label, required this.command});

  /// Package manager or distribution channel shown to the user.
  final String label;

  /// Executable and arguments copied as a terminal-ready command.
  final List<String> command;

  String get commandText => command.join(' ');

  Map<String, Object?> toJson() => <String, Object?>{'label': label, 'command': command};
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
    this.vendor,
    this.brand,
    List<String> arguments = const <String>[],
    List<String> modelArguments = const <String>['--model', '{model}'],
    List<String> resumeArguments = const <String>[],
    List<String> trailingArguments = const <String>[],
    List<String> versionArguments = const <String>['--version'],
    this.outputFormat = AgentOutputFormat.text,
    this.mcpFormat = AgentMcpFormat.none,
    List<String> mcpArguments = const <String>[],
    List<String> readableDirectoryArguments = const <String>[],
    List<String> writableDirectoryArguments = const <String>[],
    List<String> authStatusArguments = const <String>[],
    this.authStatusJsonField,
    List<String> planUsageArguments = const <String>[],
    this.planUsageJsonField,
    this.planUsageFormat = AgentPlanUsageFormat.text,
    List<String> installCommand = const <String>[],
    List<AgentInstallOption> installOptions = const <AgentInstallOption>[],
    List<String> signInCommand = const <String>[],
    Map<AgentFailureKind, List<String>> failurePatterns = const <AgentFailureKind, List<String>>{},
    String? model,
    String? accountDirectoryVariable,
    this.accountFormat = AgentAccountFormat.none,
    List<String> accountArguments = const <String>[],
    this.accountEmailJsonField,
    this.accountPlanJsonField,
    Map<String, String> environment = const <String, String>{},
    this.account,
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
       readableDirectoryArguments = _requireArguments(readableDirectoryArguments, 'readableDirectoryArguments'),
       writableDirectoryArguments = _requireArguments(writableDirectoryArguments, 'writableDirectoryArguments'),
       authStatusArguments = _requireArguments(authStatusArguments, 'authStatusArguments'),
       planUsageArguments = _requireArguments(planUsageArguments, 'planUsageArguments'),
       installOptions = _requireInstallOptions(installOptions, installCommand),
       signInCommand = List<String>.unmodifiable(signInCommand),
       failurePatterns = Map<AgentFailureKind, List<String>>.unmodifiable(<AgentFailureKind, List<String>>{
         for (final MapEntry<AgentFailureKind, List<String>>(:AgentFailureKind key, :List<String> value) in failurePatterns.entries) key: List<String>.unmodifiable(_requirePatterns(value)),
       }),
       model = model == null ? null : _requireText(model, 'model'),
       accountDirectoryVariable = accountDirectoryVariable == null ? null : _requireVariable(accountDirectoryVariable, 'accountDirectoryVariable'),
       accountArguments = _requireArguments(accountArguments, 'accountArguments'),
       environment = Map<String, String>.unmodifiable(<String, String>{
         for (final MapEntry<String, String>(:String key, :String value) in environment.entries) _requireVariable(key, 'environment'): value,
       });

  /// OpenAI Codex CLI; Codex enforces the sandbox itself and `exec` never
  /// escalates for approval.
  factory AgentDefinition.codex({String? model}) => AgentDefinition(
    id: 'codex',
    displayName: 'Codex',
    executable: 'codex',
    vendor: 'OpenAI',
    brand: 'openai',
    arguments: const <String>['exec', '--json', '--color', 'never', '--cd', '{workingDirectory}'],
    sandboxArguments: const <SandboxMode, List<String>>{
      SandboxMode.readOnly: <String>['--sandbox', 'read-only'],
      SandboxMode.workspaceWrite: <String>['--sandbox', 'workspace-write'],
    },
    resumeArguments: const <String>['resume', '{sessionId}'],
    trailingArguments: const <String>['-'],
    outputFormat: AgentOutputFormat.codexJsonl,
    mcpFormat: AgentMcpFormat.codexConfigOverrides,
    // Codex can read outside its workspace; only writable repositories are added.
    writableDirectoryArguments: const <String>['--add-dir', '{directory}'],
    authStatusArguments: const <String>['login', 'status'],
    installOptions: const <AgentInstallOption>[
      AgentInstallOption(label: 'Homebrew', command: <String>['brew', 'install', '--cask', 'codex']),
      AgentInstallOption(label: 'npm', command: <String>['npm', 'install', '-g', '@openai/codex@latest']),
    ],
    // The app server answers `account/rateLimits/read` without a model call.
    planUsageArguments: const <String>['app-server'],
    planUsageFormat: AgentPlanUsageFormat.codexAppServer,
    signInCommand: const <String>['codex', 'login'],
    // Each CODEX_HOME holds its own sign-in, so accounts are separate folders.
    accountDirectoryVariable: 'CODEX_HOME',
    accountFormat: AgentAccountFormat.codexAppServer,
    accountArguments: const <String>['app-server'],
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
    vendor: 'Anthropic',
    brand: 'anthropic',
    arguments: const <String>['--print', '--output-format', 'stream-json', '--verbose', '--restricted', '--permission-prompts', 'none', '--strict-mcp-config'],
    sandboxArguments: const <SandboxMode, List<String>>{
      SandboxMode.readOnly: <String>['--permission-mode', 'manual', '--disallowedTools', 'Edit,Write,NotebookEdit'],
      SandboxMode.workspaceWrite: <String>['--permission-mode', 'acceptEdits'],
    },
    resumeArguments: const <String>['--resume', '{sessionId}'],
    outputFormat: AgentOutputFormat.claudeStreamJson,
    mcpFormat: AgentMcpFormat.jsonConfigFile,
    mcpArguments: const <String>['--mcp-config', '{mcpConfigFile}', '--allowedTools', '{mcpToolNames}'],
    // `--restricted` confines file tools to the working directory, so every
    // other repository is added; edits stay subject to the sandbox and Weave's guards.
    readableDirectoryArguments: const <String>['--add-dir', '{directory}'],
    writableDirectoryArguments: const <String>['--add-dir', '{directory}'],
    authStatusArguments: const <String>['auth', 'status'],
    authStatusJsonField: 'loggedIn',
    // `/usage` is a local command in print mode: no model call, no cost.
    planUsageArguments: const <String>['--print', '/usage', '--output-format', 'json'],
    planUsageJsonField: 'result',
    installOptions: const <AgentInstallOption>[
      AgentInstallOption(label: 'Homebrew', command: <String>['brew', 'install', '--cask', 'claude-code']),
    ],
    signInCommand: const <String>['claude', 'auth', 'login'],
    // Each CLAUDE_CONFIG_DIR holds its own sign-in, so accounts are separate folders.
    accountDirectoryVariable: 'CLAUDE_CONFIG_DIR',
    accountFormat: AgentAccountFormat.authStatusJson,
    accountArguments: const <String>['auth', 'status'],
    accountEmailJsonField: 'email',
    accountPlanJsonField: 'subscriptionType',
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

    List<AgentInstallOption> installOptions() {
      final Object? value = json['installOptions'];
      if (value == null) {
        return const <AgentInstallOption>[];
      }
      if (value is! List<Object?>) {
        throw const FormatException('installOptions must be a list.');
      }
      return <AgentInstallOption>[
        for (final Object? item in value)
          if (item case <String, Object?>{'label': final String label, 'command': final List<Object?> command} when command.every((Object? argument) => argument is String)) AgentInstallOption(label: label, command: command.cast<String>()) else throw const FormatException('Each installOptions item must contain a label and a command list of strings.'),
      ];
    }

    final Object? sandbox = json['sandboxArguments'];
    if (sandbox is! Map<String, Object?>) {
      throw const FormatException('sandboxArguments must be an object.');
    }
    final Object? model = json['model'];
    final Object? outputFormat = json['outputFormat'];
    final Object? mcpFormat = json['mcpFormat'];
    final Object? authStatusJsonField = json['authStatusJsonField'];
    final Object? planUsageJsonField = json['planUsageJsonField'];
    final Object? planUsageFormat = json['planUsageFormat'];
    final Object? accountFormat = json['accountFormat'];
    final Object environment = json['environment'] ?? const <String, Object?>{};
    if (environment is! Map<String, Object?> || environment.values.any((Object? value) => value is! String)) {
      throw const FormatException('environment must be an object of strings.');
    }
    final Object failurePatterns = json['failurePatterns'] ?? const <String, Object?>{};
    if (failurePatterns is! Map<String, Object?>) {
      throw const FormatException('failurePatterns must be an object.');
    }
    try {
      return AgentDefinition(
        id: text('id'),
        displayName: text('displayName'),
        executable: text('executable'),
        vendor: json['vendor'] as String?,
        brand: json['brand'] as String?,
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
        readableDirectoryArguments: strings('readableDirectoryArguments'),
        writableDirectoryArguments: strings('writableDirectoryArguments'),
        authStatusArguments: strings('authStatusArguments'),
        authStatusJsonField: authStatusJsonField as String?,
        planUsageArguments: strings('planUsageArguments'),
        planUsageJsonField: planUsageJsonField as String?,
        planUsageFormat: planUsageFormat == null ? AgentPlanUsageFormat.text : AgentPlanUsageFormat.fromJsonName(planUsageFormat as String),
        installCommand: strings('installCommand'),
        installOptions: installOptions(),
        signInCommand: strings('signInCommand'),
        failurePatterns: <AgentFailureKind, List<String>>{
          for (final MapEntry<String, Object?>(:String key, :Object? value) in failurePatterns.entries) AgentFailureKind.values.byName(key): value is List<Object?> && value.every((Object? item) => item is String) ? value.cast<String>() : throw FormatException('failurePatterns.$key must be a list of strings.'),
        },
        model: model as String?,
        accountDirectoryVariable: json['accountDirectoryVariable'] as String?,
        accountFormat: accountFormat == null ? AgentAccountFormat.none : AgentAccountFormat.fromJsonName(accountFormat as String),
        accountArguments: strings('accountArguments'),
        accountEmailJsonField: json['accountEmailJsonField'] as String?,
        accountPlanJsonField: json['accountPlanJsonField'] as String?,
        environment: environment.cast<String, String>(),
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

  /// Who makes the agent, shown under its name, e.g. "OpenAI".
  final String? vendor;

  /// The brand mark to show, by name (e.g. `openai`); the app looks it up
  /// in its own marks, so no agent ID is ever mapped to a logo in code.
  final String? brand;

  final List<String> mcpArguments;

  /// Added once per other repository the agent may only read, with
  /// `{directory}` replaced by its path; empty when the agent reads anywhere.
  final List<String> readableDirectoryArguments;

  /// Added once per other repository the agent may edit, e.g. `--add-dir {directory}`.
  final List<String> writableDirectoryArguments;

  /// Checks sign-in without touching credentials, e.g. `auth status`; empty
  /// when the agent offers no such command.
  final List<String> authStatusArguments;

  /// A JSON field of the auth status output that must be `true`; when `null`
  /// a zero exit code means signed in.
  final String? authStatusJsonField;

  /// Reports subscription plan usage without running a model, e.g. a CLI's
  /// local `/usage` command; empty when the agent offers none.
  final List<String> planUsageArguments;

  /// A JSON field of the plan usage output that holds the report text; when
  /// `null` the whole output is the report. Lines read like
  /// `Current session: 28% used · resets Oct 7 at 8:10pm`.
  final String? planUsageJsonField;

  /// How the output of [planUsageArguments] is read.
  final AgentPlanUsageFormat planUsageFormat;

  bool get reportsPlanUsage => planUsageArguments.isNotEmpty;

  /// Provider-published installation choices. Weave only displays or copies
  /// these commands; it never executes installers.
  final List<AgentInstallOption> installOptions;

  /// The preferred installation command, retained for older integrations.
  List<String> get installCommand => installOptions.isEmpty ? const <String>[] : installOptions.first.command;

  /// What the user runs in a terminal to sign in, e.g. `claude auth login`.
  final List<String> signInCommand;

  /// Extra regular expressions per failure kind, on top of the built-in ones.
  final Map<AgentFailureKind, List<String>> failurePatterns;

  /// An environment variable that points the CLI at its own configuration
  /// folder, e.g. `CLAUDE_CONFIG_DIR`. When set, Weave can add more accounts
  /// of this agent, each signed in inside its own folder.
  final String? accountDirectoryVariable;

  /// How [accountArguments] report who the agent is signed in as.
  final AgentAccountFormat accountFormat;

  /// Reports the signed-in account without running a model, e.g. `auth status`.
  final List<String> accountArguments;

  /// The JSON fields of [accountArguments]' output with the account's email
  /// and plan, for [AgentAccountFormat.authStatusJson].
  final String? accountEmailJsonField;
  final String? accountPlanJsonField;

  /// Extra environment variables for every command of this agent, e.g. the
  /// configuration folder of an [account].
  final Map<String, String> environment;

  /// Set when this definition is one more account of another agent; see
  /// [forAccount].
  final AgentAccount? account;

  /// Whether more accounts of this agent can be added.
  bool get supportsAccounts => accountDirectoryVariable != null && account == null;

  /// What the user runs in a terminal to sign in, with this agent's
  /// [environment] in front, e.g. `CLAUDE_CONFIG_DIR=/… claude auth login`;
  /// `null` when the agent declares no sign-in command.
  String? get signInCommandText => signInCommand.isEmpty
      ? null
      : <String>[
          for (final MapEntry<String, String>(:String key, :String value) in environment.entries) '$key=${shellQuote(value)}',
          ...signInCommand.map(shellQuote),
        ].join(' ');

  /// This agent signed in as [account], whose own configuration lives in
  /// [directory]; it runs as `account.id` and is named after both.
  AgentDefinition forAccount(AgentAccount account, {required String directory}) {
    final String? variable = accountDirectoryVariable;
    if (variable == null || this.account != null) {
      throw StateError('$displayName does not support more accounts.');
    }
    if (account.agentId != id) {
      throw ArgumentError.value(account.agentId, 'account.agentId', 'must be $id');
    }
    return _copy(id: account.id, displayName: '$displayName · ${account.name}', environment: <String, String>{...environment, variable: directory}, account: account, model: model);
  }

  AgentFailureClassifier get failureClassifier => AgentFailureClassifier(extraPatterns: failurePatterns);
  final String? model;

  bool get supportsMcp => mcpFormat != AgentMcpFormat.none;

  /// Terminal-ready presentation of [installCommand], or `null` when the
  /// agent does not declare installation guidance.
  String? get installCommandText => installCommand.isEmpty ? null : installCommand.join(' ');

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
      for (final AgentDirectoryAccess directory in request.additionalDirectories) ...(directory.writable ? writableDirectoryArguments : readableDirectoryArguments).map((String argument) => substitute(argument.replaceAll('{directory}', directory.path))),
      if ((request.model ?? model) != null) ...modelArguments.map(substitute),
      if (request.resumeSessionId != null) ...resumeArguments.map(substitute),
      ...trailingArguments.map(substitute),
    ];
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'displayName': displayName,
    'executable': executable,
    if (vendor != null) 'vendor': vendor,
    if (brand != null) 'brand': brand,
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
    'readableDirectoryArguments': readableDirectoryArguments,
    'writableDirectoryArguments': writableDirectoryArguments,
    'authStatusArguments': authStatusArguments,
    'authStatusJsonField': authStatusJsonField,
    'planUsageArguments': planUsageArguments,
    'planUsageJsonField': planUsageJsonField,
    'planUsageFormat': planUsageFormat.jsonName,
    'installCommand': installCommand,
    'installOptions': <Map<String, Object?>>[for (final AgentInstallOption option in installOptions) option.toJson()],
    'signInCommand': signInCommand,
    'failurePatterns': <String, List<String>>{for (final MapEntry<AgentFailureKind, List<String>>(:AgentFailureKind key, :List<String> value) in failurePatterns.entries) key.name: value},
    'model': model,
    'accountDirectoryVariable': ?accountDirectoryVariable,
    if (accountFormat != AgentAccountFormat.none) 'accountFormat': accountFormat.jsonName,
    if (accountArguments.isNotEmpty) 'accountArguments': accountArguments,
    'accountEmailJsonField': ?accountEmailJsonField,
    'accountPlanJsonField': ?accountPlanJsonField,
    if (environment.isNotEmpty) 'environment': environment,
  };

  /// Returns a copy that runs [model], or the CLI default when `null`.
  AgentDefinition withModel(String? model) => _copy(id: id, displayName: displayName, environment: environment, account: account, model: model);

  AgentDefinition _copy({required String id, required String displayName, required Map<String, String> environment, required AgentAccount? account, required String? model}) => AgentDefinition(
    id: id,
    displayName: displayName,
    executable: executable,
    vendor: vendor,
    brand: brand,
    arguments: arguments,
    sandboxArguments: sandboxArguments,
    modelArguments: modelArguments,
    resumeArguments: resumeArguments,
    trailingArguments: trailingArguments,
    versionArguments: versionArguments,
    outputFormat: outputFormat,
    mcpFormat: mcpFormat,
    mcpArguments: mcpArguments,
    readableDirectoryArguments: readableDirectoryArguments,
    writableDirectoryArguments: writableDirectoryArguments,
    authStatusArguments: authStatusArguments,
    authStatusJsonField: authStatusJsonField,
    planUsageArguments: planUsageArguments,
    planUsageJsonField: planUsageJsonField,
    planUsageFormat: planUsageFormat,
    installOptions: installOptions,
    signInCommand: signInCommand,
    failurePatterns: failurePatterns,
    model: model,
    accountDirectoryVariable: accountDirectoryVariable,
    accountFormat: accountFormat,
    accountArguments: accountArguments,
    accountEmailJsonField: accountEmailJsonField,
    accountPlanJsonField: accountPlanJsonField,
    environment: environment,
    account: account,
  );

  static final RegExp _placeholder = RegExp(r'\{(\w+)\}');
  static const Set<String> _knownPlaceholders = <String>{'workingDirectory', 'model', 'sessionId', 'prompt', 'mcpConfigFile', 'mcpToolNames', 'directory'};
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

  static List<AgentInstallOption> _requireInstallOptions(List<AgentInstallOption> options, List<String> legacyCommand) {
    final List<AgentInstallOption> source = options.isEmpty && legacyCommand.isNotEmpty ? <AgentInstallOption>[AgentInstallOption(label: 'Terminal', command: legacyCommand)] : options;
    return List<AgentInstallOption>.unmodifiable(<AgentInstallOption>[
      for (final AgentInstallOption option in source)
        AgentInstallOption(
          label: _requireText(option.label, 'installOptions.label'),
          command: _requireArguments(option.command, 'installOptions.command'),
        ),
    ]);
  }

  static final RegExp _variablePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static String _requireVariable(String value, String name) => _variablePattern.hasMatch(value) ? value : throw ArgumentError.value(value, name, 'must be an environment variable name');

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
