import 'package:weave_core/weave_core.dart';
import 'package:weave_security/weave_security.dart';

import 'agent_role.dart';
import 'mcp_server.dart';

/// Input required to start one agent execution.
final class AgentRunRequest {
  AgentRunRequest({
    required this.task,
    required this.role,
    required String instructions,
    required String workingDirectory,
    String? resumeSessionId,
    List<McpServerDefinition> mcpServers = const <McpServerDefinition>[],
    String? model,
  }) : model = _optionalText(model, 'model'),
       mcpServers = List<McpServerDefinition>.unmodifiable(mcpServers),
       instructions = _requireText(instructions, 'instructions'),
       workingDirectory = _requireText(workingDirectory, 'workingDirectory'),
       resumeSessionId = _optionalText(resumeSessionId, 'resumeSessionId');

  final WorkflowTask task;
  final AgentRole role;
  final String instructions;
  final String workingDirectory;
  final String? resumeSessionId;

  /// MCP servers the agent may use, with `${NAME}` values already resolved.
  final List<McpServerDefinition> mcpServers;

  /// Overrides the agent's default model for this run, e.g. per role.
  final String? model;

  /// Derived from [role] so a request can never widen its own access.
  SandboxMode get sandboxMode => role.sandboxMode;

  static String _requireText(String value, String name) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }

  static String? _optionalText(String? value, String name) => value == null ? null : _requireText(value, name);
}
