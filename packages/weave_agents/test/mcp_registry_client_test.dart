import 'dart:convert';

import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';

/// Entries shaped like real `GET /v0/servers` answers.
Map<String, Object?> _response() => jsonDecode('''
{
  "servers": [
    {
      "server": {
        "name": "ai.smithery/smithery-notion",
        "description": "A Notion workspace",
        "version": "1.0.0",
        "remotes": [{"type": "streamable-http", "url": "https://server.smithery.ai/@smithery/notion/mcp", "headers": [{"name": "Authorization", "value": "Bearer {smithery_api_key}", "isRequired": true, "isSecret": true}]}]
      },
      "_meta": {"io.modelcontextprotocol.registry/official": {"status": "active", "isLatest": true}}
    },
    {
      "server": {
        "name": "com.mcparmory/notion",
        "description": "Create, update, and manage pages",
        "version": "1.0.2",
        "packages": [
          {"registryType": "pypi", "identifier": "mcparmory-notion", "version": "1.0.2", "runtimeHint": "uvx", "transport": {"type": "stdio"}},
          {"registryType": "oci", "identifier": "ghcr.io/mcparmory/notion:1.0.2", "transport": {"type": "stdio"}}
        ]
      },
      "_meta": {"io.modelcontextprotocol.registry/official": {"status": "active", "isLatest": true}}
    },
    {
      "server": {
        "name": "com.notion/mcp",
        "title": "Notion",
        "description": "Official Notion MCP server",
        "version": "1.0.1",
        "remotes": [{"type": "streamable-http", "url": "https://mcp.notion.com/mcp"}, {"type": "sse", "url": "https://mcp.notion.com/sse"}]
      },
      "_meta": {"io.modelcontextprotocol.registry/official": {"status": "active", "isLatest": true}}
    },
    {
      "server": {
        "name": "io.github.getsentry/sentry-mcp",
        "description": "Sentry",
        "version": "0.42.0",
        "packages": [{"registryType": "npm", "identifier": "@sentry/mcp-server", "version": "0.42.0", "transport": {"type": "stdio"}, "environmentVariables": [{"name": "SENTRY_ACCESS_TOKEN", "isRequired": true, "isSecret": true}, {"name": "SENTRY_HOST", "isRequired": false, "isSecret": false}]}],
        "remotes": [{"type": "streamable-http", "url": "https://mcp.sentry.dev/mcp"}]
      },
      "_meta": {"io.modelcontextprotocol.registry/official": {"status": "active", "isLatest": true}}
    },
    {
      "server": {"name": "example/docker-only", "description": "Docker", "version": "1", "packages": [{"registryType": "oci", "identifier": "ghcr.io/x/y", "transport": {"type": "stdio"}}]},
      "_meta": {"io.modelcontextprotocol.registry/official": {"status": "active", "isLatest": true}}
    },
    {
      "server": {"name": "example/needs-input", "description": "Needs a path", "version": "1", "packages": [{"registryType": "npm", "identifier": "needs-input", "transport": {"type": "stdio"}, "packageArguments": [{"type": "positional", "isRequired": true, "valueHint": "path"}]}]},
      "_meta": {"io.modelcontextprotocol.registry/official": {"status": "active", "isLatest": true}}
    },
    {
      "server": {"name": "example/old", "description": "Old", "version": "0.1", "remotes": [{"type": "streamable-http", "url": "https://old.example.com/mcp"}]},
      "_meta": {"io.modelcontextprotocol.registry/official": {"status": "deprecated", "isLatest": true}}
    }
  ],
  "metadata": {"count": 7}
}
''') as Map<String, Object?>;

McpRegistryEntry _named(List<McpRegistryEntry> entries, String name) => entries.firstWhere((McpRegistryEntry entry) => entry.name == name);

void main() {
  group('parseMcpRegistryServers', () {
    final List<McpRegistryEntry> entries = parseMcpRegistryServers(_response());

    test('skips deprecated servers', () {
      expect(entries.map((McpRegistryEntry entry) => entry.name), isNot(contains('example/old')));
    });

    test('a header placeholder becomes an environment reference', () {
      final McpServerDefinition server = _named(entries, 'ai.smithery/smithery-notion').server!;
      expect(server.id, 'smithery-notion');
      expect((server.transport as McpHttpTransport).headers, <String, String>{'Authorization': r'Bearer ${SMITHERY_API_KEY}'});
      expect(server.setupHint, contains(r'Set $SMITHERY_API_KEY.'));
      expect(server.setupHint, contains('community'));
    });

    test('a PyPI package runs with uvx; Docker is skipped', () {
      final McpStdioTransport transport = _named(entries, 'com.mcparmory/notion').server!.transport as McpStdioTransport;
      expect(transport.command, 'uvx');
      expect(transport.arguments, <String>['mcparmory-notion==1.0.2']);
    });

    test('a package with a token is preferred over a remote that needs an interactive sign-in', () {
      final McpServerDefinition server = _named(entries, 'io.github.getsentry/sentry-mcp').server!;
      final McpStdioTransport transport = server.transport as McpStdioTransport;
      expect(transport.command, 'npx');
      expect(transport.arguments, <String>['-y', '@sentry/mcp-server@0.42.0']);
      expect(transport.environment, <String, String>{'SENTRY_ACCESS_TOKEN': r'${SENTRY_ACCESS_TOKEN}'}, reason: 'optional settings are left out');
      expect(server.setupHint, contains('Needs Node.js'));
    });

    test('a remote without a token signs in through the agent', () {
      final McpServerDefinition server = _named(entries, 'com.notion/mcp').server!;
      expect(server.displayName, 'Notion', reason: 'the title is preferred');
      expect(server.id, 'notion-mcp', reason: 'a generic name takes the publisher in front');
      expect((server.transport as McpHttpTransport).url, 'https://mcp.notion.com/mcp');
      expect(server.setupHint, contains('sign in'));
    });

    test('servers Weave cannot run are listed as unsupported', () {
      expect(_named(entries, 'example/docker-only').server, isNull);
      expect(_named(entries, 'example/docker-only').unsupportedReason, contains('Docker'));
      expect(_named(entries, 'example/needs-input').server, isNull, reason: 'a required argument Weave cannot fill');
    });

    test('nothing converted holds a credential', () {
      for (final McpRegistryEntry entry in entries) {
        final McpServerDefinition? server = entry.server;
        if (server == null) {
          continue;
        }
        final Iterable<String> values = switch (server.transport) {
          McpHttpTransport(:final Map<String, String> headers) => headers.values,
          McpStdioTransport(:final Map<String, String> environment) => environment.values,
        };
        expect(values.every((String value) => value.contains(r'${')), isTrue, reason: entry.name);
      }
    });
  });

  group('McpRegistryClient', () {
    test('sends only the search text and asks for the latest versions', () async {
      Uri? requested;
      final McpRegistryClient client = McpRegistryClient(
        fetch: (Uri uri) async {
          requested = uri;
          return jsonEncode(_response());
        },
      );

      final List<McpRegistryEntry> results = await client.search('  notion ');
      expect(results, isNotEmpty);
      expect(requested?.host, 'registry.modelcontextprotocol.io');
      expect(requested?.queryParameters, <String, String>{'search': 'notion', 'limit': '30', 'version': 'latest'});
    });

    test('network failures and unreadable answers become readable errors', () async {
      await expectLater(McpRegistryClient(fetch: (Uri uri) async => throw StateError('offline')).search('x'), throwsA(isA<McpRegistryException>().having((McpRegistryException error) => error.message, 'message', contains('could not be reached'))));
      await expectLater(McpRegistryClient(fetch: (Uri uri) async => '<html>').search('x'), throwsA(isA<McpRegistryException>().having((McpRegistryException error) => error.message, 'message', contains('cannot read'))));
    });
  });
}
