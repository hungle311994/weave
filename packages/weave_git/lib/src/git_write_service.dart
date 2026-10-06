import 'package:weave_security/weave_security.dart';

import 'git_command_runner.dart';
import 'git_exceptions.dart';
import 'git_repository_service.dart';
import 'git_repository_snapshot.dart';

/// A repository write waiting for the user's decision.
final class GitWriteRequest {
  GitWriteRequest({required this.operation, required this.repositoryRoot, required this.summary, required List<String> paths}) : paths = List<String>.unmodifiable(paths);

  final GuardedOperation operation;
  final String repositoryRoot;

  /// One line describing the write, e.g. `Commit 3 files to main`.
  final String summary;

  /// Every path the write affects, relative to [repositoryRoot].
  final List<String> paths;
}

/// Decides whether a write may run; return `true` only after the user
/// approved it.
typedef GitApprovalGate = Future<bool> Function(GitWriteRequest request);

/// The commit created by [GitWriteService.commitAll].
final class GitCommitResult {
  const GitCommitResult({required this.commitSha, required this.branch});

  final String commitSha;

  /// `null` when the commit was made on a detached `HEAD`.
  final String? branch;
}

/// Raised when the user does not approve a repository write.
final class GitApprovalDeniedException implements Exception {
  const GitApprovalDeniedException(this.summary);

  final String summary;

  @override
  String toString() => 'GitApprovalDeniedException: not approved: $summary';
}

/// Raised when there are no changes to commit.
final class GitNothingToCommitException implements Exception {
  const GitNothingToCommitException();

  @override
  String toString() => 'GitNothingToCommitException: the working tree has no changes.';
}

/// Repository writes, each gated by [SecurityPolicy] and user approval.
///
/// Kept apart from [GitRepositoryService] so read-only callers can never
/// reach a write by accident.
final class GitWriteService {
  GitWriteService({GitCommandRunner? runner, GitRepositoryService? reader}) : _runner = runner ?? ProcessGitCommandRunner(), _reader = reader ?? GitRepositoryService(runner: runner);

  final GitCommandRunner _runner;
  final GitRepositoryService _reader;

  static const List<String> _options = <String>['-c', 'core.fsmonitor=false'];

  /// Stages every change in [directory] and commits it with [message] once
  /// [approve] allows it.
  Future<GitCommitResult> commitAll(String directory, {required String message, required GitApprovalGate approve}) async {
    final String trimmed = message.trim();
    if (trimmed.isEmpty || message.contains('\x00')) {
      throw ArgumentError.value(message, 'message', 'must be non-empty text');
    }

    final GitRepositorySnapshot snapshot = await _reader.readSnapshot(directory);
    if (snapshot.isClean) {
      throw const GitNothingToCommitException();
    }
    if (snapshot.conflictedFiles.isNotEmpty) {
      throw StateError('Resolve merge conflicts before committing.');
    }

    final List<String> stage = <String>[..._options, 'add', '--all', '--', '.'];
    final List<String> commit = <String>[..._options, 'commit', '--quiet', '-m', trimmed];
    final WorkspaceScope scope = await WorkspaceScope.resolve(snapshot.rootPath);
    final SecurityPolicy policy = SecurityPolicy(scope: scope, mode: SandboxMode.workspaceWrite);
    final PolicyDecision decision = policy.evaluate(OperationRequest(classifyGitArguments(commit)));
    if (decision == PolicyDecision.deny) {
      throw GitApprovalDeniedException('commit is not allowed');
    }

    final List<String> paths = <String>[for (final GitStatusEntry entry in snapshot.entries) entry.path]..sort();
    final GitWriteRequest request = GitWriteRequest(
      operation: GuardedOperation.gitCommit,
      repositoryRoot: snapshot.rootPath,
      summary: 'Commit ${paths.length} file${paths.length == 1 ? '' : 's'} to ${snapshot.head.branch ?? 'detached HEAD'}',
      paths: paths,
    );
    // Commits always need approval, whatever the policy would otherwise say.
    if (!await approve(request)) {
      throw GitApprovalDeniedException(request.summary);
    }

    await _run(stage, snapshot.rootPath);
    await _run(commit, snapshot.rootPath);
    final GitHead head = (await _reader.readSnapshot(snapshot.rootPath)).head;
    return GitCommitResult(commitSha: head.commitSha!, branch: head.branch);
  }

  Future<void> _run(List<String> arguments, String workingDirectory) async {
    final GitCommandResult result = await _runner.run(arguments, workingDirectory: workingDirectory);
    if (result.exitCode != 0) {
      throw GitCommandException(arguments, result.exitCode);
    }
  }
}
