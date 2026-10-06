import 'dart:convert';

import 'agent_adapter.dart';
import 'agent_definition.dart';
import 'agent_executable_locator.dart';
import 'command_agent_adapter.dart';

/// The agents Weave can assign to workflow roles, keyed by ID.
final class AgentRegistry {
  AgentRegistry(Iterable<AgentAdapter> adapters)
    : _adapters = Map<String, AgentAdapter>.unmodifiable(
        <String, AgentAdapter>{
          for (final AgentAdapter adapter in adapters) adapter.id: adapter,
        },
      );

  /// Built-in presets plus [customDefinitions]; a custom definition with a
  /// built-in ID replaces that preset.
  factory AgentRegistry.fromDefinitions({
    Iterable<AgentDefinition> customDefinitions = const <AgentDefinition>[],
    Map<String, String>? environment,
    Duration executionTimeout = const Duration(hours: 1),
  }) {
    final AgentExecutableLocator locator = AgentExecutableLocator(environment: environment);
    final Map<String, AgentDefinition> definitions = <String, AgentDefinition>{
      for (final AgentDefinition definition in <AgentDefinition>[...builtInDefinitions, ...customDefinitions]) definition.id: definition,
    };
    return AgentRegistry(
      <AgentAdapter>[
        for (final AgentDefinition definition in definitions.values)
          CommandAgentAdapter(
            definition,
            locator: locator,
            environment: environment,
            executionTimeout: executionTimeout,
          ),
      ],
    );
  }

  static List<AgentDefinition> get builtInDefinitions => <AgentDefinition>[AgentDefinition.codex(), AgentDefinition.claudeCode()];

  final Map<String, AgentAdapter> _adapters;

  Iterable<AgentAdapter> get adapters => _adapters.values;

  Iterable<String> get ids => _adapters.keys;

  AgentAdapter? operator [](String id) => _adapters[id];

  /// The adapter for [id], or a [StateError] naming the known agents.
  AgentAdapter require(String id) => _adapters[id] ?? (throw StateError('Unknown agent "$id". Available agents: ${ids.join(', ')}.'));
}

/// Parses an `agents.json` document:
/// `{"schemaVersion": 1, "agents": [<AgentDefinition>...]}`.
List<AgentDefinition> decodeAgentDefinitions(String source) {
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
    throw const FormatException('agents.json must use schemaVersion 1.');
  }
  final Object? agents = decoded['agents'];
  if (agents is! List<Object?>) {
    throw const FormatException('agents.json must contain an agents list.');
  }

  final List<AgentDefinition> definitions = <AgentDefinition>[
    for (final Object? agent in agents)
      if (agent is Map<String, Object?>) AgentDefinition.fromJson(agent) else throw const FormatException('Each agent must be an object.'),
  ];
  final List<String> ids = definitions.map((AgentDefinition definition) => definition.id).toList();
  if (ids.toSet().length != ids.length) {
    throw const FormatException('agents.json contains duplicate agent IDs.');
  }
  return definitions;
}

/// Serializes [definitions] as an `agents.json` document.
String encodeAgentDefinitions(Iterable<AgentDefinition> definitions) =>
    '${const JsonEncoder.withIndent('  ').convert(<String, Object>{
      'schemaVersion': 1,
      'agents': <Map<String, Object?>>[for (final AgentDefinition definition in definitions) definition.toJson()],
    })}\n';
