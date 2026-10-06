import 'dart:io';

import 'package:weave_git/weave_git.dart';

Future<void> main() async {
  final GitRepositoryService service = GitRepositoryService();
  final String directory = Directory.current.absolute.path;

  if (!await service.isRepository(directory)) {
    print('Not a Git repository.');
    return;
  }

  final GitRepositorySnapshot snapshot = await service.readSnapshot(directory);
  print('Branch: ${snapshot.head.branch ?? '(detached)'}');
  print('HEAD: ${snapshot.head.commitSha ?? '(no commits)'}');
  print('Staged: ${snapshot.stagedChanges.length}');
  print('Unstaged: ${snapshot.unstagedChanges.length}');
  print('Untracked: ${snapshot.untrackedFiles.length}');
}
