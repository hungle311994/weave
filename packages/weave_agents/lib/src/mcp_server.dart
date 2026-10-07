import 'dart:convert';

/// How an agent reaches an MCP server.
sealed class McpTransport {
  const McpTransport();

  Map<String, Object?> toJson();

  /// Values that may hold credentials and must be redacted from output.
  Iterable<String> get secretValues;
}

/// A local MCP server started by the agent as a child process.
final class McpStdioTransport extends McpTransport {
  McpStdioTransport({required String command, List<String> arguments = const <String>[], Map<String, String> environment = const <String, String>{}}) : command = _requireText(command, 'command'), arguments = List<String>.unmodifiable(arguments), environment = Map<String, String>.unmodifiable(environment);

  final String command;
  final List<String> arguments;
  final Map<String, String> environment;

  @override
  Iterable<String> get secretValues => environment.values;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'type': 'stdio', 'command': command, 'arguments': arguments, 'environment': environment};
}

/// A remote or local MCP server reached over streamable HTTP.
final class McpHttpTransport extends McpTransport {
  McpHttpTransport({required String url, Map<String, String> headers = const <String, String>{}}) : url = _requireUrl(url), headers = Map<String, String>.unmodifiable(headers);

  final String url;
  final Map<String, String> headers;

  @override
  Iterable<String> get secretValues => headers.values;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'type': 'http', 'url': url, 'headers': headers};
}

/// An MCP server agents may use during a workflow, such as Figma.
///
/// Text values may reference environment variables as `${NAME}`; they are
/// expanded only when an agent starts, so `mcp.json` never needs to hold a
/// token itself.
final class McpServerDefinition {
  McpServerDefinition({required String id, required String displayName, required this.transport, List<String> linkPatterns = const <String>[], String? setupHint, String? description, this.brand})
    : id = _requireId(id),
      description = description == null || description.trim().isEmpty ? null : description.trim(),
      displayName = _requireText(displayName, 'displayName'),
      linkPatterns = List<String>.unmodifiable(linkPatterns),
      setupHint = setupHint == null ? null : _requireText(setupHint, 'setupHint'),
      _linkExpressions = <RegExp>[for (final String pattern in linkPatterns) _compile(pattern)];

  /// Figma's hosted MCP server; the agent completes Figma sign-in itself.
  factory McpServerDefinition.figma() => McpServerDefinition(
    id: 'figma',
    displayName: 'Figma',
    transport: McpHttpTransport(url: 'https://mcp.figma.com/mcp'),
    linkPatterns: const <String>[_figmaLinkPattern],
    setupHint: 'Uses Figma\'s hosted MCP server. Sign in to Figma from your agent the first time it connects.',
    description: 'Design context from figma.com links',
    brand: 'figma',
  );

  /// The MCP server built into the Figma desktop app.
  factory McpServerDefinition.figmaDesktop() => McpServerDefinition(
    id: 'figma-desktop',
    displayName: 'Figma (desktop app)',
    transport: McpHttpTransport(url: 'http://127.0.0.1:3845/mcp'),
    linkPatterns: const <String>[_figmaLinkPattern],
    setupHint: 'Open the Figma desktop app and enable its MCP server in Preferences before starting the workflow.',
    description: 'Design context from the open Figma desktop app',
    brand: 'figma',
  );

  factory McpServerDefinition.fromJson(Map<String, Object?> json) {
    String text(String key) => json[key] is String ? json[key]! as String : throw FormatException('$key must be a string.');
    List<String> strings(Object? value, String key) => value == null
        ? const <String>[]
        : value is List<Object?> && value.every((Object? item) => item is String)
        ? value.cast<String>()
        : throw FormatException('$key must be a list of strings.');
    Map<String, String> stringMap(Object? value, String key) => value == null
        ? const <String, String>{}
        : value is Map<String, Object?> && value.values.every((Object? item) => item is String)
        ? value.cast<String, String>()
        : throw FormatException('$key must map names to strings.');

    final Object? transport = json['transport'];
    if (transport is! Map<String, Object?>) {
      throw const FormatException('transport must be an object.');
    }
    final Object? setupHint = json['setupHint'];
    try {
      return McpServerDefinition(
        id: text('id'),
        displayName: text('displayName'),
        transport: switch (transport['type']) {
          'stdio' => McpStdioTransport(command: transport['command'] is String ? transport['command']! as String : throw const FormatException('transport.command must be a string.'), arguments: strings(transport['arguments'], 'transport.arguments'), environment: stringMap(transport['environment'], 'transport.environment')),
          'http' => McpHttpTransport(url: transport['url'] is String ? transport['url']! as String : throw const FormatException('transport.url must be a string.'), headers: stringMap(transport['headers'], 'transport.headers')),
          final Object? type => throw FormatException('Unknown MCP transport "$type".'),
        },
        linkPatterns: strings(json['linkPatterns'], 'linkPatterns'),
        setupHint: setupHint is String ? setupHint : null,
        description: json['description'] is String ? json['description']! as String : null,
        brand: json['brand'] is String ? json['brand']! as String : null,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid MCP server: ${error.message}');
    }
  }

  static const String _figmaLinkPattern = r'https?://(?:www\.)?figma\.com/(?:file|design|proto|board|slides|make|deck)/[A-Za-z0-9]+';

  /// Letters, digits, `_`, and `-`; agents use it in tool names like
  /// `mcp__<id>__tool`.
  final String id;

  /// One line on what the server provides, e.g. "Design context from figma.com links".
  final String? description;

  /// The brand mark to show, by name (e.g. `figma`); looked up by the app,
  /// never mapped from an ID in code.
  final String? brand;
  final String displayName;
  final McpTransport transport;

  /// Regular expressions for links this server can open, used to suggest it.
  final List<String> linkPatterns;
  final String? setupHint;
  final List<RegExp> _linkExpressions;

  /// Whether [text] contains a link this server handles.
  bool matchesLinkIn(String text) => _linkExpressions.any((RegExp expression) => expression.hasMatch(text));

  /// Whether [text] explicitly mentions MCP and names this server.
  ///
  /// This is only a suggestion signal. Callers must still ask the user before
  /// enabling the server.
  bool matchesMentionIn(String text) {
    final String normalized = text.toLowerCase();
    if (!RegExp(r'\bmcp\b', caseSensitive: false).hasMatch(normalized)) {
      return false;
    }
    final Set<String> ignored = <String>{'app', 'desktop', 'mcp', 'server'};
    final Set<String> names = <String>{
      ...id.toLowerCase().split(RegExp(r'[-_]')),
      ...displayName.toLowerCase().split(RegExp(r'[^a-z0-9]+')),
    }..removeWhere((String name) => name.length < 3 || ignored.contains(name));
    return names.any((String name) => RegExp('\\b${RegExp.escape(name)}\\b', caseSensitive: false).hasMatch(normalized));
  }

  /// Every distinct link in [text] that this server handles.
  Set<String> linksIn(String text) => <String>{
    for (final RegExp expression in _linkExpressions)
      for (final RegExpMatch match in expression.allMatches(text)) match[0]!,
  };

  /// A copy with every `${NAME}` replaced from [environment].
  ///
  /// Throws a [StateError] naming the first missing variable.
  McpServerDefinition resolve(Map<String, String> environment) {
    String expand(String value) => value.replaceAllMapped(_variable, (Match match) => environment[match[1]!] ?? (throw StateError('MCP server "$id" needs the environment variable ${match[1]}.')));
    Map<String, String> expandMap(Map<String, String> values) => <String, String>{for (final MapEntry<String, String>(:String key, :String value) in values.entries) key: expand(value)};

    return McpServerDefinition(
      id: id,
      displayName: displayName,
      transport: switch (transport) {
        McpStdioTransport(:final String command, :final List<String> arguments, :final Map<String, String> environment) => McpStdioTransport(command: expand(command), arguments: arguments.map(expand).toList(), environment: expandMap(environment)),
        McpHttpTransport(:final String url, :final Map<String, String> headers) => McpHttpTransport(url: expand(url), headers: expandMap(headers)),
      },
      linkPatterns: linkPatterns,
      setupHint: setupHint,
      description: description,
      brand: brand,
    );
  }

  /// Names of the `${NAME}` environment variables the server needs.
  Set<String> get environmentVariables {
    final List<String> values = switch (transport) {
      McpStdioTransport(:final String command, :final List<String> arguments, :final Map<String, String> environment) => <String>[command, ...arguments, ...environment.values],
      McpHttpTransport(:final String url, :final Map<String, String> headers) => <String>[url, ...headers.values],
    };
    return <String>{
      for (final String value in values)
        for (final RegExpMatch match in _variable.allMatches(value)) match[1]!,
    };
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'displayName': displayName,
    'description': ?description,
    'brand': ?brand,
    'transport': transport.toJson(),
    'linkPatterns': linkPatterns,
    'setupHint': setupHint,
  };

  static final RegExp _variable = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
  static final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

  static RegExp _compile(String pattern) {
    try {
      return RegExp(pattern, caseSensitive: false);
    } on FormatException {
      throw ArgumentError.value(pattern, 'linkPatterns', 'must be valid regular expressions');
    }
  }

  static String _requireId(String value) {
    if (!_idPattern.hasMatch(value)) {
      throw ArgumentError.value(value, 'id', 'must be lowercase letters, digits, "_" or "-"');
    }
    return value;
  }
}

/// Built-in MCP presets plus those in `mcp.json`, keyed by ID.
final class McpRegistry {
  McpRegistry(Iterable<McpServerDefinition> servers) : _servers = Map<String, McpServerDefinition>.unmodifiable(<String, McpServerDefinition>{for (final McpServerDefinition server in servers) server.id: server});

  /// Presets plus [customServers]; a custom server with a preset ID replaces it.
  factory McpRegistry.withBuiltIns({Iterable<McpServerDefinition> customServers = const <McpServerDefinition>[]}) => McpRegistry(<McpServerDefinition>[...builtInServers, ...customServers]);

  static List<McpServerDefinition> get builtInServers => <McpServerDefinition>[McpServerDefinition.figma(), McpServerDefinition.figmaDesktop()];

  final Map<String, McpServerDefinition> _servers;

  Iterable<McpServerDefinition> get servers => _servers.values;

  Iterable<String> get ids => _servers.keys;

  McpServerDefinition? operator [](String id) => _servers[id];

  McpServerDefinition require(String id) => _servers[id] ?? (throw StateError('Unknown MCP server "$id". Available servers: ${ids.join(', ')}.'));

  /// Servers that handle a link in [text] that no server in [enabledIds]
  /// handles yet.
  ///
  /// Every candidate is returned, e.g. both remote and desktop Figma, so the
  /// user can pick one.
  List<McpServerDefinition> suggestionsFor(String text, {Iterable<String> enabledIds = const <String>[]}) {
    final Set<String> enabled = enabledIds.toSet();
    final bool mentionedServerIsEnabled = servers.any((McpServerDefinition server) => enabled.contains(server.id) && server.matchesMentionIn(text));
    final Set<String> coveredLinks = <String>{
      for (final McpServerDefinition server in servers)
        if (enabled.contains(server.id)) ...server.linksIn(text),
    };
    return <McpServerDefinition>[
      for (final McpServerDefinition server in servers)
        if (!enabled.contains(server.id) && (server.linksIn(text).any((String link) => !coveredLinks.contains(link)) || (!mentionedServerIsEnabled && server.matchesMentionIn(text)))) server,
    ];
  }
}

/// Parses an `mcp.json` document: `{"schemaVersion": 1, "servers": [...]}`.
List<McpServerDefinition> decodeMcpServers(String source) {
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
    throw const FormatException('mcp.json must use schemaVersion 1.');
  }
  final Object? servers = decoded['servers'];
  if (servers is! List<Object?>) {
    throw const FormatException('mcp.json must contain a servers list.');
  }
  final List<McpServerDefinition> definitions = <McpServerDefinition>[
    for (final Object? server in servers)
      if (server is Map<String, Object?>) McpServerDefinition.fromJson(server) else throw const FormatException('Each MCP server must be an object.'),
  ];
  if (definitions.map((McpServerDefinition server) => server.id).toSet().length != definitions.length) {
    throw const FormatException('mcp.json contains duplicate server IDs.');
  }
  return definitions;
}

/// Serializes [servers] as an `mcp.json` document.
String encodeMcpServers(Iterable<McpServerDefinition> servers) =>
    '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'schemaVersion': 1,
      'servers': <Map<String, Object?>>[for (final McpServerDefinition server in servers) server.toJson()],
    })}\n';

String _requireText(String value, String name) {
  final String normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return normalized;
}

String _requireUrl(String value) {
  final String url = _requireText(value, 'url');
  // `${NAME}` placeholders are allowed until the server is resolved.
  final Uri? uri = Uri.tryParse(url.replaceAll(RegExp(r'\$\{[A-Za-z_][A-Za-z0-9_]*\}'), 'x'));
  if (uri == null || !<String>{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
    throw ArgumentError.value(value, 'url', 'must be an http or https URL');
  }
  return url;
}
