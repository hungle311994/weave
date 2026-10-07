import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp_server.dart';

/// Reads [uri] and returns the response body; injectable for tests.
typedef McpRegistryFetch = Future<String> Function(Uri uri);

/// Thrown when the MCP Registry cannot be searched.
final class McpRegistryException implements Exception {
  const McpRegistryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One server listed in the public MCP Registry.
final class McpRegistryEntry {
  const McpRegistryEntry({required this.name, required this.displayName, required this.description, required this.version, this.server, this.unsupportedReason});

  /// The registry name, e.g. `io.github.getsentry/sentry-mcp`.
  final String name;
  final String displayName;
  final String description;
  final String version;

  /// What Weave would add to `mcp.json`, or `null` when no way of running
  /// the server is supported ([unsupportedReason] says why).
  final McpServerDefinition? server;
  final String? unsupportedReason;
}

/// Searches the public MCP Registry (registry.modelcontextprotocol.io).
///
/// Only the search text leaves this Mac; nothing is sent about the user,
/// their repositories or their agents.
final class McpRegistryClient {
  McpRegistryClient({McpRegistryFetch? fetch, Uri? baseUri}) : _fetch = fetch ?? _httpGet, _baseUri = baseUri ?? Uri.parse('https://registry.modelcontextprotocol.io/v0/servers');

  final McpRegistryFetch _fetch;
  final Uri _baseUri;

  /// The latest active servers matching [query], at most [limit].
  Future<List<McpRegistryEntry>> search(String query, {int limit = 30}) async {
    final Uri uri = _baseUri.replace(queryParameters: <String, String>{'search': query.trim(), 'limit': '$limit', 'version': 'latest'});
    final String body;
    try {
      body = await _fetch(uri).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const McpRegistryException('The MCP Registry did not answer in time. Check your connection and try again.');
    } on McpRegistryException {
      rethrow;
    } on Object {
      throw const McpRegistryException('The MCP Registry could not be reached. Check your connection and try again.');
    }
    try {
      final Object? decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? parseMcpRegistryServers(decoded) : const <McpRegistryEntry>[];
    } on FormatException {
      throw const McpRegistryException('The MCP Registry sent an answer Weave cannot read.');
    }
  }

  static Future<String> _httpGet(Uri uri) async {
    final HttpClient client = HttpClient()..userAgent = 'Weave';
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response = await request.close();
      final String body = await response.transform(const Utf8Decoder(allowMalformed: true)).join();
      if (response.statusCode != HttpStatus.ok) {
        throw McpRegistryException('The MCP Registry answered with HTTP ${response.statusCode}.');
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }
}

/// The latest, active servers of a `GET /v0/servers` response, each turned
/// into an [McpServerDefinition] when Weave can run it. Tokens become
/// `${NAME}` references, so no credential is ever written.
List<McpRegistryEntry> parseMcpRegistryServers(Map<String, Object?> response) {
  final List<McpRegistryEntry> entries = <McpRegistryEntry>[];
  final Set<String> seen = <String>{};
  for (final Object? item in response['servers'] is List<Object?> ? response['servers']! as List<Object?> : const <Object?>[]) {
    if (item case <String, Object?>{'server': final Map<String, Object?> server}) {
      final Object? meta = item['_meta'] is Map<String, Object?> ? (item['_meta']! as Map<String, Object?>)['io.modelcontextprotocol.registry/official'] : null;
      if (meta is Map<String, Object?> && (meta['isLatest'] == false || (meta['status'] != null && meta['status'] != 'active'))) {
        continue;
      }
      final String? name = server['name'] is String ? server['name']! as String : null;
      if (name == null || !seen.add(name)) {
        continue;
      }
      entries.add(_entry(name, server));
    }
  }
  return entries;
}

McpRegistryEntry _entry(String name, Map<String, Object?> server) {
  String text(String key) => server[key] is String ? (server[key]! as String).trim() : '';
  final String shortName = name.split('/').last;
  final String displayName = text('title').isNotEmpty ? text('title') : shortName;
  final String description = text('description');
  final String version = text('version');
  // `com.notion/mcp` would be just `mcp`; a generic last part takes the
  // publisher's name in front, e.g. `notion-mcp`.
  final String publisher = name.contains('/') ? name.substring(0, name.lastIndexOf('/')).split('.').last : '';
  final String id = _slug(<String>{'mcp', 'server', 'mcp-server'}.contains(shortName.toLowerCase()) && publisher.isNotEmpty ? '$publisher-$shortName' : shortName);
  final List<Map<String, Object?>> remotes = _objects(server['remotes']);
  final List<Map<String, Object?>> packages = _objects(server['packages']);

  McpServerDefinition definition(McpTransport transport, String hint) => McpServerDefinition(id: id, displayName: displayName, description: description.isEmpty ? null : description, transport: transport, setupHint: 'From the MCP Registry (community, not reviewed by Weave). $hint');

  try {
    final List<Map<String, Object?>> streamable = <Map<String, Object?>>[
      for (final Map<String, Object?> remote in remotes)
        if (remote['type'] == 'streamable-http' && remote['url'] is String && !(remote['url']! as String).contains('{')) remote,
    ];
    // 1. A remote server that takes a token in a header: nothing to install.
    for (final Map<String, Object?> remote in streamable) {
      final Map<String, String> headers = _headers(id, _objects(remote['headers']));
      if (headers.isNotEmpty) {
        return McpRegistryEntry(
          name: name,
          displayName: displayName,
          description: description,
          version: version,
          server: definition(McpHttpTransport(url: remote['url']! as String, headers: headers), _setHint(headers.values)),
        );
      }
    }
    // 2. A package Weave can start with npx or uvx.
    for (final Map<String, Object?> package in packages) {
      if (_stdio(package) case (final McpStdioTransport transport, final String needs)) {
        return McpRegistryEntry(name: name, displayName: displayName, description: description, version: version, server: definition(transport, '${_setHint(transport.environment.values)}$needs'.trim()));
      }
    }
    // 3. A remote server that signs in through the agent.
    if (streamable.isNotEmpty) {
      return McpRegistryEntry(
        name: name,
        displayName: displayName,
        description: description,
        version: version,
        server: definition(McpHttpTransport(url: streamable.first['url']! as String), 'Your agent may ask you to sign in the first time it connects.'),
      );
    }
  } on ArgumentError {
    // An entry Weave cannot express falls through to "not supported".
  } on FormatException {
    // Same.
  }
  return McpRegistryEntry(name: name, displayName: displayName, description: description, version: version, unsupportedReason: packages.isNotEmpty || remotes.isNotEmpty ? 'Runs only in a way Weave does not support yet (e.g. Docker or SSE).' : 'Lists no way to run it.');
}

List<Map<String, Object?>> _objects(Object? value) => <Map<String, Object?>>[
  if (value is List<Object?>)
    for (final Object? item in value)
      if (item is Map<String, Object?>) item,
];

/// Header values with `{placeholder}`s, and secret headers without a value,
/// as `${NAME}` references.
Map<String, String> _headers(String id, List<Map<String, Object?>> headers) => <String, String>{
  for (final Map<String, Object?> header in headers)
    if (header['name'] case final String name when name.isNotEmpty)
      if (header['value'] case final String value when value.isNotEmpty) name: value.replaceAllMapped(RegExp(r'\{([A-Za-z0-9_.-]+)\}'), (Match match) => '\${${_variable(match[1]!)}}') else if (header['isSecret'] == true || header['isRequired'] == true) name: name.toLowerCase() == 'authorization' ? 'Bearer \${${_variable('${id}_token')}}' : '\${${_variable('${id}_$name')}}',
};

/// npx or uvx for an npm or PyPI package over stdio, with what it needs.
(McpStdioTransport, String)? _stdio(Map<String, Object?> package) {
  final Object? transport = package['transport'];
  if (transport is! Map<String, Object?> || transport['type'] != 'stdio') {
    return null;
  }
  bool requiresInput(Object? arguments) => _objects(arguments).any((Map<String, Object?> argument) => argument['isRequired'] == true && argument['value'] == null && argument['default'] == null);
  if (requiresInput(package['packageArguments']) || requiresInput(package['runtimeArguments'])) {
    return null;
  }
  final String? identifier = package['identifier'] is String ? package['identifier']! as String : null;
  final String? version = package['version'] is String && (package['version']! as String).isNotEmpty ? package['version']! as String : null;
  if (identifier == null || identifier.isEmpty) {
    return null;
  }
  final Map<String, String> environment = <String, String>{
    for (final Map<String, Object?> variable in _objects(package['environmentVariables']))
      if (variable['name'] case final String name when RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name) && (variable['isRequired'] == true || variable['isSecret'] == true)) name: '\${$name}',
  };
  return switch (package['registryType']) {
    'npm' => (McpStdioTransport(command: 'npx', arguments: <String>['-y', version == null ? identifier : '$identifier@$version'], environment: environment), ' Needs Node.js (npx).'),
    'pypi' => (McpStdioTransport(command: 'uvx', arguments: <String>[version == null ? identifier : '$identifier==$version'], environment: environment), ' Needs uv (uvx).'),
    _ => null,
  };
}

String _setHint(Iterable<String> values) {
  final List<String> names = <String>{
    for (final String value in values)
      for (final Match match in RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}').allMatches(value)) match[1]!,
  }.toList();
  return names.isEmpty ? '' : 'Set ${names.map((String name) => '\$$name').join(', ')}.';
}

String _variable(String text) => text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');

String _slug(String text) {
  final String slug = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '-').replaceAll(RegExp(r'^[^a-z0-9]+|-+$'), '');
  return slug.isEmpty ? 'mcp-server' : (slug.length > 64 ? slug.substring(0, 64) : slug);
}
