import 'dart:convert';

import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';

void main() {
  test('catalog IDs are unique and never replace a built-in server', () {
    final List<String> ids = <String>[for (final McpCatalogEntry entry in mcpCatalog) entry.server.id];

    expect(ids.toSet(), hasLength(ids.length));
    expect(ids.toSet().intersection(McpRegistry.withBuiltIns().ids.toSet()), isEmpty);
  });

  test('catalog servers hold no credentials, only environment references', () {
    final RegExp reference = RegExp(r'\$\{[A-Z0-9_]+\}');
    for (final McpCatalogEntry entry in mcpCatalog) {
      final Iterable<String> values = switch (entry.server.transport) {
        McpHttpTransport(:final Map<String, String> headers) => headers.values,
        McpStdioTransport(:final Map<String, String> environment) => environment.values,
      };
      for (final String value in values) {
        expect(reference.hasMatch(value), isTrue, reason: '${entry.server.id}: "$value" must read a token from the environment');
      }
      expect(entry.server.setupHint, isNotNull, reason: '${entry.server.id} tells the user how to set it up');
    }
    expect(mcpCatalog.firstWhere((McpCatalogEntry entry) => entry.server.id == 'github').server.environmentVariables, <String>['GITHUB_PERSONAL_ACCESS_TOKEN']);
  });

  test('every catalog server survives mcp.json and is offered for its links', () {
    final List<McpServerDefinition> servers = <McpServerDefinition>[for (final McpCatalogEntry entry in mcpCatalog) entry.server];
    final List<McpServerDefinition> restored = decodeMcpServers(encodeMcpServers(servers));

    expect(jsonEncode(<Object?>[for (final McpServerDefinition server in restored) server.toJson()]), jsonEncode(<Object?>[for (final McpServerDefinition server in servers) server.toJson()]));
    final McpRegistry registry = McpRegistry.withBuiltIns(customServers: servers);
    expect(registry.suggestionsFor('Fix https://github.com/acme/app/issues/12').map((McpServerDefinition server) => server.id), contains('github'));
  });
}
