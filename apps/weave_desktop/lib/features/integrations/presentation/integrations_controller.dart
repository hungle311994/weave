import 'package:flutter/foundation.dart';
import 'package:weave_agents/weave_agents.dart';

import '../domain/integrations_repository.dart';
import '../domain/mcp_server_readiness.dart';

/// What the Plugins screen shows: the catalog, skills, or one installed plugin.
enum PluginSection { plugins, skills, installed }

/// Exposes MCP server state and mutations to integration screens.
final class IntegrationsController extends ChangeNotifier {
  IntegrationsController(this._repository);

  final IntegrationsRepository _repository;

  List<McpServerDefinition> get servers => _repository.servers;

  String get configurationPath => _repository.configurationPath;

  McpServerDefinition? serverById(String id) => _repository.serverById(id);

  List<McpServerDefinition> suggestionsFor(String request, Iterable<String> enabledIds) => _repository.suggestionsFor(request, enabledIds);

  Future<Set<String>> customServerIds() => _repository.customServerIds();

  final Map<String, McpServerReadiness> _readiness = <String, McpServerReadiness>{};
  Set<String> _customIds = const <String>{};
  bool _disposed = false;

  PluginSection _section = PluginSection.plugins;
  String? _selectedPluginGroup;

  /// The Plugins screen's view; kept here so the docked and the floating
  /// sidebar show and change the same selection.
  PluginSection get section => _section;

  /// The installed plugin shown when [section] is [PluginSection.installed].
  String? get selectedPluginGroup => _selectedPluginGroup;

  void showSection(PluginSection section) {
    _section = section;
    _selectedPluginGroup = null;
    _notify();
  }

  /// Shows the installed plugin [group] (its brand, or its server ID).
  void showPluginGroup(String group) {
    _section = PluginSection.installed;
    _selectedPluginGroup = group;
    _notify();
  }

  List<McpRegistryEntry> _registryResults = const <McpRegistryEntry>[];
  String? _registryError;
  String _registryQuery = '';
  bool _searchingRegistry = false;
  int _registryRequest = 0;

  /// MCP Registry results for [registryQuery]; empty until a search runs.
  List<McpRegistryEntry> get registryResults => _registryResults;

  /// Why the last registry search failed, if it did.
  String? get registryError => _registryError;

  String get registryQuery => _registryQuery;

  bool get searchingRegistry => _searchingRegistry;

  /// Searches the MCP Registry for [query] (two characters or more); an
  /// older search that answers late is ignored.
  Future<void> searchRegistry(String query) async {
    final String trimmed = query.trim();
    final int request = ++_registryRequest;
    _registryQuery = trimmed;
    _registryError = null;
    _registryResults = const <McpRegistryEntry>[];
    _searchingRegistry = trimmed.length >= 2;
    _notify();
    if (!_searchingRegistry) {
      return;
    }
    try {
      final List<McpRegistryEntry> results = await _repository.searchRegistry(trimmed);
      if (request == _registryRequest) {
        _registryResults = results;
      }
    } on McpRegistryException catch (error) {
      if (request == _registryRequest) {
        _registryError = error.message;
      }
    } finally {
      if (request == _registryRequest) {
        _searchingRegistry = false;
        _notify();
      }
    }
  }

  /// The last local check of [id], if any.
  McpServerReadiness? readinessOf(String id) => _readiness[id];

  /// Whether [id] comes from `mcp.json` and can be edited or removed.
  bool isCustom(String id) => _customIds.contains(id);

  /// Re-reads the custom servers and checks every server locally.
  Future<void> refresh() async {
    _customIds = await _repository.customServerIds();
    final List<McpServerDefinition> current = servers;
    final List<McpServerReadiness> results = await Future.wait(<Future<McpServerReadiness>>[for (final McpServerDefinition server in current) _repository.checkReadiness(server)]);
    _readiness
      ..clear()
      ..addEntries(<MapEntry<String, McpServerReadiness>>[for (int index = 0; index < current.length; index++) MapEntry<String, McpServerReadiness>(current[index].id, results[index])]);
    _notify();
  }

  Future<void> saveServer(McpServerDefinition server) async {
    await _repository.saveServer(server);
    await refresh();
  }

  Future<void> removeServer(String id) async {
    await _repository.removeServer(id);
    await refresh();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
