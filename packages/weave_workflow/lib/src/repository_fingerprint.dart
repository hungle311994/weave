import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:weave_git/weave_git.dart';

/// A cheap description of a working tree that changes whenever a tracked or
/// untracked file is added, removed, or rewritten, or `HEAD` moves.
///
/// Status alone misses a second edit to an already modified file, so the
/// size and modification time of every reported path are included.
Future<String> fingerprintRepository(GitRepositorySnapshot snapshot) async {
  final List<String> lines = <String>['head ${snapshot.head.branch ?? '(detached)'} ${snapshot.head.commitSha ?? '(unborn)'}'];
  final List<GitStatusEntry> entries = snapshot.entries.toList()..sort((GitStatusEntry left, GitStatusEntry right) => left.path.compareTo(right.path));
  for (final GitStatusEntry entry in entries) {
    final String state = switch (entry) {
      GitTrackedChange(:final GitChangeType? stagedChange, :final GitChangeType? unstagedChange, :final String? originalPath) => 'tracked ${stagedChange?.name} ${unstagedChange?.name} ${originalPath ?? ''}',
      GitUntrackedFile() => 'untracked',
      GitConflictedFile(:final GitConflictType conflict) => 'conflict ${conflict.name}',
    };
    final FileStat stat = await FileStat.stat(path.join(snapshot.rootPath, entry.path));
    lines.add('${entry.path}\t$state\t${stat.type}\t${stat.size}\t${stat.modified.microsecondsSinceEpoch}');
  }
  return lines.join('\n');
}
