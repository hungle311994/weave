import 'package:weave_agents/weave_agents.dart';

import 'mcp_server_readiness.dart';

/// MCP server persistence and discovery needed by the desktop app.
abstract interface class IntegrationsRepository {
  List<McpServerDefinition> get servers;

  String get configurationPath;

  McpServerDefinition? serverById(String id);

  List<McpServerDefinition> suggestionsFor(String request, Iterable<String> enabledIds);

  Future<Set<String>> customServerIds();

  Future<void> saveServer(McpServerDefinition server);

  Future<void> removeServer(String id);

  /// Checks [server] locally; nothing connects to it.
  Future<McpServerReadiness> checkReadiness(McpServerDefinition server);

  /// Searches the public MCP Registry; only [query] is sent. Throws
  /// [McpRegistryException] when it cannot be reached or read.
  Future<List<McpRegistryEntry>> searchRegistry(String query);
}
