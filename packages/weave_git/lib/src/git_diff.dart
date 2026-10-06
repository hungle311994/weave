import 'git_repository_snapshot.dart';

/// Read-only patch of every uncommitted change in a working tree.
final class GitDiff {
  const GitDiff({required this.snapshot, required this.staged, required this.unstaged, required this.untracked, required this.isTruncated});

  /// The status the patch was read against.
  final GitRepositorySnapshot snapshot;

  /// `HEAD` against the index.
  final String staged;

  /// The index against the working tree.
  final String unstaged;

  /// New regular files that Git does not track yet.
  final String untracked;

  /// Whether the size limit cut the patch short.
  final bool isTruncated;

  bool get isEmpty => staged.isEmpty && unstaged.isEmpty && untracked.isEmpty;

  /// All sections as one patch, staged changes first.
  String get patch => <String>[staged, unstaged, untracked].where((String section) => section.isNotEmpty).join('\n');
}
