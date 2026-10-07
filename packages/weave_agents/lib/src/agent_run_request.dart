import 'package:weave_core/weave_core.dart';
import 'package:weave_security/weave_security.dart';

import 'agent_role.dart';
import 'mcp_server.dart';

/// A repository beyond the working directory that an agent may use.
final class AgentDirectoryAccess {
  AgentDirectoryAccess({required String path, required this.writable}) : path = _requirePath(path);

  final String path;

  /// Whether the agent may edit it; otherwise it is only read.
  final bool writable;

  static String _requirePath(String value) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'path', 'must not be empty');
    }
    return normalized;
  }
}

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
    List<AgentDirectoryAccess> additionalDirectories = const <AgentDirectoryAccess>[],
  }) : model = _optionalText(model, 'model'),
       additionalDirectories = List<AgentDirectoryAccess>.unmodifiable(_requireAccess(role, additionalDirectories)),
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

  /// Other repositories of a multi-repository workflow. A read-only role
  /// never receives a writable one.
  final List<AgentDirectoryAccess> additionalDirectories;

  /// Derived from [role] so a request can never widen its own access.
  SandboxMode get sandboxMode => role.sandboxMode;

  static String _requireText(String value, String name) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }

  static List<AgentDirectoryAccess> _requireAccess(AgentRole role, List<AgentDirectoryAccess> directories) {
    if (role.sandboxMode == SandboxMode.readOnly && directories.any((AgentDirectoryAccess directory) => directory.writable)) {
      throw ArgumentError.value(directories, 'additionalDirectories', 'must be read-only for the ${role.name}');
    }
    return directories;
  }

  static String? _optionalText(String? value, String name) => value == null ? null : _requireText(value, name);
}
