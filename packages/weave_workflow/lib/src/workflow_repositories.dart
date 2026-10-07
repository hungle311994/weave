import 'package:path/path.dart' as path;

/// A repository offered at the [WorkflowCheckpointKind.repositories] checkpoint.
final class WorkflowRepositoryChoice {
  const WorkflowRepositoryChoice({required this.path, required this.name, required this.proposed, this.reason});

  final String path;

  /// Short name used in prompts and the UI, e.g. the folder name.
  final String name;

  /// Whether the plan intends to change it.
  final bool proposed;

  /// What the plan wants to change there, in the planner's words.
  final String? reason;
}

/// `HEAD` of one repository when a workflow started.
final class WorkflowRepositoryHead {
  const WorkflowRepositoryHead({this.branch, this.commit});

  factory WorkflowRepositoryHead.fromJson(Map<String, Object?> json) => WorkflowRepositoryHead(branch: json['branch'] as String?, commit: json['commit'] as String?);

  final String? branch;
  final String? commit;

  Map<String, Object?> toJson() => <String, Object?>{'branch': branch, 'commit': commit};
}

/// A short, unique name per repository: the folder name, or the parent and
/// folder names when two repositories share a folder name.
Map<String, String> repositoryNames(List<String> repositoryPaths) {
  final Map<String, int> counts = <String, int>{};
  for (final String repository in repositoryPaths) {
    counts[path.basename(repository)] = (counts[path.basename(repository)] ?? 0) + 1;
  }
  return <String, String>{
    for (final String repository in repositoryPaths) repository: counts[path.basename(repository)]! > 1 ? path.join(path.basename(path.dirname(repository)), path.basename(repository)) : path.basename(repository),
  };
}

final RegExp _sectionHeading = RegExp(r'^\s*#{1,6}\s*Repositories to change\s*:?\s*$', caseSensitive: false);
final RegExp _anyHeading = RegExp(r'^\s*#{1,6}\s');
final RegExp _bullet = RegExp(r'^\s*[-*]\s*(?:\[[ xX]\]\s*)?`?([^`:—]+?)`?\s*(?:[:—–-]\s+(.*))?$');

/// The repositories a plan intends to change, from its
/// `## Repositories to change` section of `- <name>: <reason>` lines, keyed by
/// path with the reason as value. Names match a repository's folder name,
/// its unique name, or its full path; other lines are ignored.
Map<String, String?> plannedRepositories(String plan, List<String> repositoryPaths) {
  final Map<String, String> names = repositoryNames(repositoryPaths);
  final Map<String, String?> planned = <String, String?>{};
  bool inSection = false;
  for (final String line in plan.split('\n')) {
    if (_sectionHeading.hasMatch(line)) {
      inSection = true;
      continue;
    }
    if (inSection && _anyHeading.hasMatch(line)) {
      break;
    }
    if (!inSection) {
      continue;
    }
    final RegExpMatch? match = _bullet.firstMatch(line);
    if (match == null) {
      continue;
    }
    final String name = match.group(1)!.trim().toLowerCase();
    for (final String repository in repositoryPaths) {
      if (name == repository.toLowerCase() || name == names[repository]!.toLowerCase() || name == path.basename(repository).toLowerCase()) {
        final String? reason = match.group(2)?.trim();
        planned[repository] = reason == null || reason.isEmpty ? null : reason;
      }
    }
  }
  return planned;
}

/// Repositories the user names in [text], by folder name, unique name or full
/// path, as whole words (case-insensitive).
Set<String> mentionedRepositories(String text, List<String> repositoryPaths) {
  final Map<String, String> names = repositoryNames(repositoryPaths);
  final String lower = text.toLowerCase();
  bool mentions(String name) => RegExp('(^|[^a-z0-9_.-])${RegExp.escape(name.toLowerCase())}(\$|[^a-z0-9_-])').hasMatch(lower);
  return <String>{
    for (final String repository in repositoryPaths)
      if (mentions(repository) || mentions(names[repository]!) || mentions(path.basename(repository))) repository,
  };
}
