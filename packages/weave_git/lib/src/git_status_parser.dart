import 'git_exceptions.dart';
import 'git_repository_snapshot.dart';

/// Parses `git status --porcelain=v2 --branch -z`.
///
/// Records are NUL-terminated and paths are never quoted, so a path is always
/// the remainder of its record and may contain any number of spaces.
({GitHead head, List<GitStatusEntry> entries}) parseGitStatusPorcelainV2(String output) {
  final List<String> records = output.split('\x00');
  if (records.last.isEmpty) {
    records.removeLast();
  }

  String? branchOid;
  String? branchHead;
  final List<GitStatusEntry> entries = <GitStatusEntry>[];

  for (int index = 0; index < records.length; index++) {
    final String record = records[index];
    if (record.isEmpty) {
      throw const GitOutputFormatException('Git status contains an empty record.');
    }

    switch (record[0]) {
      case '#':
        if (record.startsWith(_branchOidPrefix)) {
          branchOid = record.substring(_branchOidPrefix.length);
        } else if (record.startsWith(_branchHeadPrefix)) {
          branchHead = record.substring(_branchHeadPrefix.length);
        }
      case '1':
        final List<String> fields = _splitFields(record, 9);
        final (GitChangeType? staged, GitChangeType? unstaged) = _parseChangePair(fields[1]);
        entries.add(GitTrackedChange(path: fields[8], stagedChange: staged, unstagedChange: unstaged));
      case '2':
        final List<String> fields = _splitFields(record, 10);
        final (GitChangeType? staged, GitChangeType? unstaged) = _parseChangePair(fields[1]);
        index++;
        if (index >= records.length || records[index].isEmpty) {
          throw const GitOutputFormatException('Git status rename record is missing its original path.');
        }
        entries.add(GitTrackedChange(path: fields[9], originalPath: records[index], stagedChange: staged, unstagedChange: unstaged));
      case 'u':
        final List<String> fields = _splitFields(record, 11);
        entries.add(GitConflictedFile(path: fields[10], conflict: _parseConflict(fields[1])));
      case '?':
        entries.add(GitUntrackedFile(_splitFields(record, 2)[1]));
      case '!':
        continue;
      default:
        throw GitOutputFormatException('Git status contains an unknown record type "${record[0]}".');
    }
  }

  return (head: _parseHead(branchOid, branchHead), entries: entries);
}

const String _branchOidPrefix = '# branch.oid ';
const String _branchHeadPrefix = '# branch.head ';
final RegExp _commitShaPattern = RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$');

GitHead _parseHead(String? branchOid, String? branchHead) {
  if (branchOid == null || branchHead == null) {
    throw const GitOutputFormatException('Git status is missing branch headers.');
  }

  final String? commitSha = branchOid == '(initial)' ? null : branchOid;
  if (commitSha != null && !_commitShaPattern.hasMatch(commitSha)) {
    throw const GitOutputFormatException('Git status contains an invalid commit SHA.');
  }

  final String? branch = branchHead == '(detached)' ? null : branchHead;
  if (branch != null && branch.isEmpty) {
    throw const GitOutputFormatException('Git status contains an empty branch name.');
  }
  if (branch == null && commitSha == null) {
    throw const GitOutputFormatException('Git status reports a detached HEAD without a commit.');
  }

  return GitHead(branch: branch, commitSha: commitSha);
}

/// Splits on the first `count - 1` spaces so the final path keeps its spaces.
List<String> _splitFields(String record, int count) {
  final List<String> fields = <String>[];
  int start = 0;
  for (int field = 0; field < count - 1; field++) {
    final int end = record.indexOf(' ', start);
    if (end < 0) {
      throw GitOutputFormatException('Git status record "${record[0]}" has too few fields.');
    }
    fields.add(record.substring(start, end));
    start = end + 1;
  }

  final String path = record.substring(start);
  if (path.isEmpty) {
    throw GitOutputFormatException('Git status record "${record[0]}" has an empty path.');
  }
  fields.add(path);
  return fields;
}

(GitChangeType?, GitChangeType?) _parseChangePair(String code) {
  if (code.length != 2) {
    throw const GitOutputFormatException('Git status contains an invalid change code.');
  }
  return (_parseChange(code[0]), _parseChange(code[1]));
}

GitChangeType? _parseChange(String code) => switch (code) {
  '.' => null,
  'M' => GitChangeType.modified,
  'T' => GitChangeType.typeChanged,
  'A' => GitChangeType.added,
  'D' => GitChangeType.deleted,
  'R' => GitChangeType.renamed,
  'C' => GitChangeType.copied,
  _ => throw GitOutputFormatException('Git status contains an unknown change code "$code".'),
};

GitConflictType _parseConflict(String code) => switch (code) {
  'DD' => GitConflictType.bothDeleted,
  'AU' => GitConflictType.addedByUs,
  'UD' => GitConflictType.deletedByThem,
  'UA' => GitConflictType.addedByThem,
  'DU' => GitConflictType.deletedByUs,
  'AA' => GitConflictType.bothAdded,
  'UU' => GitConflictType.bothModified,
  _ => throw GitOutputFormatException('Git status contains an unknown conflict code "$code".'),
};
