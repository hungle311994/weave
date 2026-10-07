import 'package:weave_agents/weave_agents.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../domain/integrations_repository.dart';
import '../domain/mcp_server_readiness.dart';

/// Stores custom MCP servers through Weave's external application data.
final class WeaveIntegrationsRepository implements IntegrationsRepository {
  WeaveIntegrationsRepository(this._services, {McpRegistryClient? registry}) : _registry = registry ?? McpRegistryClient();

  final WeaveServices _services;
  final McpRegistryClient _registry;

  @override
  Future<List<McpRegistryEntry>> searchRegistry(String query) => _registry.search(query);

  @override
  List<McpServerDefinition> get servers => _services.mcp.servers.toList(growable: false);

  @override
  String get configurationPath => mcpFilePath(_services.paths);

  @override
  McpServerDefinition? serverById(String id) => _services.mcp[id];

  @override
  List<McpServerDefinition> suggestionsFor(String request, Iterable<String> enabledIds) => _services.mcp.suggestionsFor(request, enabledIds: enabledIds);

  @override
  Future<Set<String>> customServerIds() async => <String>{for (final McpServerDefinition server in await loadCustomMcpServers(_services.paths)) server.id};

  @override
  Future<void> saveServer(McpServerDefinition server) async {
    final List<McpServerDefinition> custom = await loadCustomMcpServers(_services.paths);
    await saveCustomMcpServers(
      _services.paths,
      <McpServerDefinition>[
        for (final McpServerDefinition existing in custom)
          if (existing.id != server.id) existing,
        server,
      ],
    );
    await _services.reloadMcp();
  }

  @override
  Future<McpServerReadiness> checkReadiness(McpServerDefinition server) async {
    final List<String> missing = <String>[
      for (final String name in server.environmentVariables)
        if (_services.environment[name]?.isNotEmpty != true) name,
    ]..sort();
    switch (server.transport) {
      case McpHttpTransport(:final String url):
        return missing.isEmpty ? McpServerReadiness.ready(detail: url) : McpServerReadiness.notReady(missingVariables: missing, detail: url);
      case McpStdioTransport(:final String command):
        // A command built from a variable can only be found once it is set.
        final String? found = command.contains(r'${') ? null : await AgentExecutableLocator(environment: _services.environment).locate(command);
        final bool commandMissing = !command.contains(r'${') && found == null;
        if (missing.isEmpty && !commandMissing) {
          return McpServerReadiness.ready(detail: found ?? command);
        }
        return McpServerReadiness.notReady(missingVariables: missing, missingCommand: commandMissing ? command : null, detail: command);
    }
  }

  @override
  Future<void> removeServer(String id) async {
    final List<McpServerDefinition> custom = await loadCustomMcpServers(_services.paths);
    await saveCustomMcpServers(
      _services.paths,
      <McpServerDefinition>[
        for (final McpServerDefinition existing in custom)
          if (existing.id != id) existing,
      ],
    );
    await _services.reloadMcp();
  }
}
