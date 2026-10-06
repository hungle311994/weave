/// The branch and commit referenced by `HEAD`.
final class GitHead {
  const GitHead({required this.branch, required this.commitSha}) : assert(branch != null || commitSha != null, 'A detached HEAD must reference a commit.');

  /// Short branch name, or `null` when `HEAD` is detached.
  final String? branch;

  /// Full commit SHA, or `null` before the first commit on [branch].
  final String? commitSha;

  bool get isDetached => branch == null;

  bool get isUnborn => commitSha == null;
}

/// How a tracked path differs on one side of the index.
enum GitChangeType { modified, typeChanged, added, deleted, renamed, copied }

/// The unmerged state of a conflicted path.
enum GitConflictType { bothDeleted, addedByUs, deletedByThem, addedByThem, deletedByUs, bothAdded, bothModified }

/// One path reported by `git status`, relative to the repository root.
sealed class GitStatusEntry {
  const GitStatusEntry(this.path);

  final String path;
}

/// A tracked path with staged changes, unstaged changes, or both.
final class GitTrackedChange extends GitStatusEntry {
  const GitTrackedChange({required String path, required this.stagedChange, required this.unstagedChange, this.originalPath}) : super(path);

  /// Difference between `HEAD` and the index.
  final GitChangeType? stagedChange;

  /// Difference between the index and the working tree.
  final GitChangeType? unstagedChange;

  /// Source path of a rename or copy.
  final String? originalPath;

  bool get isStaged => stagedChange != null;

  bool get hasUnstagedChanges => unstagedChange != null;
}

/// A path that Git does not track and does not ignore.
final class GitUntrackedFile extends GitStatusEntry {
  const GitUntrackedFile(super.path);
}

/// A path with an unresolved merge conflict.
final class GitConflictedFile extends GitStatusEntry {
  const GitConflictedFile({required String path, required this.conflict}) : super(path);

  final GitConflictType conflict;
}

/// Read-only view of a working tree at one point in time.
final class GitRepositorySnapshot {
  GitRepositorySnapshot({required this.rootPath, required this.head, required List<GitStatusEntry> entries}) : entries = List<GitStatusEntry>.unmodifiable(entries);

  final String rootPath;
  final GitHead head;
  final List<GitStatusEntry> entries;

  bool get isClean => entries.isEmpty;

  List<GitTrackedChange> get stagedChanges => List<GitTrackedChange>.unmodifiable(entries.whereType<GitTrackedChange>().where((GitTrackedChange entry) => entry.isStaged));

  List<GitTrackedChange> get unstagedChanges => List<GitTrackedChange>.unmodifiable(entries.whereType<GitTrackedChange>().where((GitTrackedChange entry) => entry.hasUnstagedChanges));

  List<GitUntrackedFile> get untrackedFiles => List<GitUntrackedFile>.unmodifiable(entries.whereType<GitUntrackedFile>());

  List<GitConflictedFile> get conflictedFiles => List<GitConflictedFile>.unmodifiable(entries.whereType<GitConflictedFile>());
}
