import 'sandbox_mode.dart';
import 'workspace_scope.dart';

/// An operation Weave or an agent may attempt.
enum GuardedOperation {
  readFile,
  writeFile,
  deleteFile,
  runCommand,
  network,

  /// Inspects a repository without changing it.
  gitRead,

  /// Changes local repository state without discarding work.
  gitWrite,
  gitCommit,
  gitPush,

  /// Discards work or rewrites history.
  gitDestructive,
}

/// The outcome of evaluating an operation against a [SecurityPolicy].
enum PolicyDecision { allow, requireApproval, deny }

/// One operation to evaluate, with the path it targets when relevant.
final class OperationRequest {
  const OperationRequest(this.operation, {this.targetPath});

  final GuardedOperation operation;
  final String? targetPath;
}

/// Decides which operations need the user's approval.
///
/// Read-only executions can never change the workspace. Commits, pushes,
/// destructive operations, network access, and anything outside the
/// workspace require approval even when writes are allowed.
final class SecurityPolicy {
  const SecurityPolicy({required this.scope, required this.mode});

  final WorkspaceScope scope;
  final SandboxMode mode;

  PolicyDecision evaluate(OperationRequest request) {
    final PolicyDecision decision = _decisionFor(request.operation);
    if (decision == PolicyDecision.deny) {
      return decision;
    }

    final String? targetPath = request.targetPath;
    if (targetPath != null && !scope.containsPath(targetPath)) {
      return PolicyDecision.requireApproval;
    }
    return decision;
  }

  PolicyDecision _decisionFor(GuardedOperation operation) => switch ((mode, operation)) {
    (_, GuardedOperation.readFile || GuardedOperation.gitRead) => PolicyDecision.allow,
    (_, GuardedOperation.network) => PolicyDecision.requireApproval,
    (SandboxMode.readOnly, GuardedOperation.runCommand) => PolicyDecision.requireApproval,
    (SandboxMode.readOnly, _) => PolicyDecision.deny,
    (SandboxMode.workspaceWrite, GuardedOperation.writeFile || GuardedOperation.gitWrite || GuardedOperation.runCommand) => PolicyDecision.allow,
    (SandboxMode.workspaceWrite, _) => PolicyDecision.requireApproval,
  };
}
