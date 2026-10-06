import 'package:weave_security/weave_security.dart';

/// A responsibility an AI agent can perform in a Weave workflow.
enum AgentRole {
  planner,
  implementer,
  reviewer;

  /// Planners and reviewers only inspect; implementers edit the workspace.
  SandboxMode get sandboxMode => switch (this) {
    implementer => SandboxMode.workspaceWrite,
    planner || reviewer => SandboxMode.readOnly,
  };
}
