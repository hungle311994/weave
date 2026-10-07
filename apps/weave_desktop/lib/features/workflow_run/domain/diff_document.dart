/// How a file changed in a patch.
enum DiffFileStatus {
  modified('M'),
  added('A'),
  deleted('D'),
  renamed('R');

  const DiffFileStatus(this.letter);

  /// The one-letter code Git uses in `git status --short`.
  final String letter;
}

enum DiffLineKind { context, added, removed }

/// One line of a hunk with its line numbers in the original and updated file.
final class DiffLine {
  const DiffLine({required this.kind, required this.text, this.originalNumber, this.updatedNumber});

  final DiffLineKind kind;
  final String text;

  /// Null for an added line.
  final int? originalNumber;

  /// Null for a removed line.
  final int? updatedNumber;
}

/// One row of a side-by-side diff; a side is null where it has no line.
final class SplitDiffRow {
  const SplitDiffRow({this.original, this.updated});

  final DiffLine? original;
  final DiffLine? updated;
}

/// A `@@ -a,b +c,d @@` section of a file diff.
final class DiffHunk {
  DiffHunk({required this.header, required List<DiffLine> lines}) : lines = List<DiffLine>.unmodifiable(lines);

  final String header;
  final List<DiffLine> lines;

  /// Lines paired for a side-by-side view: context lines face each other, and
  /// a run of removed lines faces the run of added lines that replaces it.
  List<SplitDiffRow> get splitRows {
    final List<SplitDiffRow> rows = <SplitDiffRow>[];
    final List<DiffLine> removed = <DiffLine>[];
    final List<DiffLine> added = <DiffLine>[];

    void flush() {
      final int count = removed.length > added.length ? removed.length : added.length;
      for (int index = 0; index < count; index++) {
        rows.add(SplitDiffRow(original: index < removed.length ? removed[index] : null, updated: index < added.length ? added[index] : null));
      }
      removed.clear();
      added.clear();
    }

    for (final DiffLine line in lines) {
      switch (line.kind) {
        case DiffLineKind.removed:
          if (added.isNotEmpty) {
            flush();
          }
          removed.add(line);
        case DiffLineKind.added:
          added.add(line);
        case DiffLineKind.context:
          flush();
          rows.add(SplitDiffRow(original: line, updated: line));
      }
    }
    flush();
    return rows;
  }
}

/// The changes to one file.
final class DiffFile {
  DiffFile({required this.path, required this.status, required List<DiffHunk> hunks, this.originalPath, this.isBinary = false, this.repository}) : hunks = List<DiffHunk>.unmodifiable(hunks);

  /// The repository's short name in a multi-repository workflow, else null.
  final String? repository;

  /// This file, labelled with [name] and its path prefixed by it.
  DiffFile inRepository(String name) => DiffFile(path: '$name/$path', status: status, hunks: hunks, originalPath: originalPath == null ? null : '$name/$originalPath', isBinary: isBinary, repository: name);

  /// Path in the updated tree (the original path for a deleted file).
  final String path;

  /// The path before a rename.
  final String? originalPath;
  final DiffFileStatus status;
  final List<DiffHunk> hunks;
  final bool isBinary;

  int get additions => _count(DiffLineKind.added);
  int get deletions => _count(DiffLineKind.removed);

  /// Lines shown on the original and updated side.
  int get originalLineCount => hunks.fold(0, (int total, DiffHunk hunk) => total + hunk.lines.where((DiffLine line) => line.kind != DiffLineKind.added).length);
  int get updatedLineCount => hunks.fold(0, (int total, DiffHunk hunk) => total + hunk.lines.where((DiffLine line) => line.kind != DiffLineKind.removed).length);

  int _count(DiffLineKind kind) => hunks.fold(0, (int total, DiffHunk hunk) => total + hunk.lines.where((DiffLine line) => line.kind == kind).length);
}

/// The files of a unified Git patch, as read for the Code Review screen.
final class DiffDocument {
  DiffDocument(List<DiffFile> files) : files = List<DiffFile>.unmodifiable(files);

  /// Parses `git diff` output. Staged, unstaged and untracked sections may
  /// mention one file twice; their hunks are merged into a single entry. A
  /// patch cut short by a size limit keeps everything read so far.
  factory DiffDocument.parse(String patch) {
    final Map<String, _FileBuilder> files = <String, _FileBuilder>{};
    _FileBuilder? file;
    _HunkBuilder? hunk;

    void finishFile() {
      final _FileBuilder? current = file;
      if (current == null) {
        return;
      }
      current.finishHunk(hunk);
      hunk = null;
      final String key = current.path;
      final _FileBuilder? existing = files[key];
      if (existing == null) {
        files[key] = current;
      } else {
        existing.mergeFrom(current);
      }
      file = null;
    }

    for (final String line in patch.split('\n')) {
      if (line.startsWith('diff --git ')) {
        finishFile();
        file = _FileBuilder.fromGitHeader(line.substring('diff --git '.length));
        continue;
      }
      final _FileBuilder? current = file;
      if (current == null) {
        continue;
      }
      final _HunkBuilder? currentHunk = hunk;
      if (line.startsWith('@@')) {
        current.finishHunk(currentHunk);
        hunk = _HunkBuilder.parse(line);
        continue;
      }
      if (currentHunk != null) {
        if (line.startsWith('+')) {
          currentHunk.add(DiffLineKind.added, line.substring(1));
        } else if (line.startsWith('-')) {
          currentHunk.add(DiffLineKind.removed, line.substring(1));
        } else if (line.startsWith(' ')) {
          currentHunk.add(DiffLineKind.context, line.substring(1));
        } else if (line.isEmpty && currentHunk.expectsMore) {
          // An empty context line whose leading space was trimmed.
          currentHunk.add(DiffLineKind.context, '');
        }
        // "\ No newline at end of file" and other markers carry no content.
        continue;
      }
      current.readHeader(line);
    }
    finishFile();
    return DiffDocument(<DiffFile>[for (final _FileBuilder builder in files.values) builder.build()]);
  }

  final List<DiffFile> files;

  /// One document for several repositories, each file labelled with its
  /// repository; a single repository keeps its paths as they are.
  factory DiffDocument.combine(Map<String, DiffDocument> byRepository) => byRepository.length == 1
      ? byRepository.values.single
      : DiffDocument(<DiffFile>[
          for (final MapEntry<String, DiffDocument>(:String key, :DiffDocument value) in byRepository.entries)
            for (final DiffFile file in value.files) file.inRepository(key),
        ]);

  bool get isEmpty => files.isEmpty;
  int get additions => files.fold(0, (int total, DiffFile file) => total + file.additions);
  int get deletions => files.fold(0, (int total, DiffFile file) => total + file.deletions);
}

final class _FileBuilder {
  _FileBuilder(this.path);

  /// Reads the paths from `a/<path> b/<path>`; the `---`/`+++` lines refine them.
  factory _FileBuilder.fromGitHeader(String paths) {
    final int split = paths.lastIndexOf(' b/');
    final String updated = split >= 0 ? paths.substring(split + 3) : paths;
    return _FileBuilder(_unquote(updated));
  }

  String path;
  String? originalPath;
  DiffFileStatus status = DiffFileStatus.modified;
  bool isBinary = false;
  final List<DiffHunk> hunks = <DiffHunk>[];

  void readHeader(String line) {
    if (line.startsWith('new file mode')) {
      status = DiffFileStatus.added;
    } else if (line.startsWith('deleted file mode')) {
      status = DiffFileStatus.deleted;
    } else if (line.startsWith('rename from ')) {
      status = DiffFileStatus.renamed;
      originalPath = _unquote(line.substring('rename from '.length));
    } else if (line.startsWith('rename to ')) {
      status = DiffFileStatus.renamed;
      path = _unquote(line.substring('rename to '.length));
    } else if (line.startsWith('Binary files ') || line == 'GIT binary patch') {
      isBinary = true;
    } else if (line.startsWith('--- ')) {
      final String original = _stripPrefix(line.substring(4), 'a/');
      if (original == '/dev/null') {
        status = DiffFileStatus.added;
      }
    } else if (line.startsWith('+++ ')) {
      final String updated = _stripPrefix(line.substring(4), 'b/');
      if (updated == '/dev/null') {
        status = DiffFileStatus.deleted;
      } else {
        path = updated;
      }
    }
  }

  void finishHunk(_HunkBuilder? hunk) {
    if (hunk != null) {
      hunks.add(hunk.build());
    }
  }

  void mergeFrom(_FileBuilder other) {
    hunks.addAll(other.hunks);
    isBinary = isBinary || other.isBinary;
    if (other.status != DiffFileStatus.modified) {
      status = other.status;
      originalPath = other.originalPath ?? originalPath;
    }
  }

  DiffFile build() => DiffFile(path: path, originalPath: originalPath, status: status, hunks: hunks, isBinary: isBinary);

  static String _stripPrefix(String value, String prefix) {
    final String path = _unquote(value.split('\t').first);
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  static String _unquote(String value) => value.length >= 2 && value.startsWith('"') && value.endsWith('"') ? value.substring(1, value.length - 1) : value;
}

final class _HunkBuilder {
  _HunkBuilder({required this.header, required this.originalLine, required this.updatedLine, required this.originalRemaining, required this.updatedRemaining});

  static final RegExp _range = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

  factory _HunkBuilder.parse(String line) {
    final RegExpMatch? match = _range.firstMatch(line);
    int number(int group, int fallback) => int.tryParse(match?.group(group) ?? '') ?? fallback;
    return _HunkBuilder(header: line, originalLine: number(1, 1), originalRemaining: number(2, 1), updatedLine: number(3, 1), updatedRemaining: number(4, 1));
  }

  final String header;
  int originalLine;
  int updatedLine;
  int originalRemaining;
  int updatedRemaining;
  final List<DiffLine> _lines = <DiffLine>[];

  bool get expectsMore => originalRemaining > 0 || updatedRemaining > 0;

  void add(DiffLineKind kind, String text) {
    switch (kind) {
      case DiffLineKind.context:
        _lines.add(DiffLine(kind: kind, text: text, originalNumber: originalLine++, updatedNumber: updatedLine++));
        originalRemaining--;
        updatedRemaining--;
      case DiffLineKind.removed:
        _lines.add(DiffLine(kind: kind, text: text, originalNumber: originalLine++));
        originalRemaining--;
      case DiffLineKind.added:
        _lines.add(DiffLine(kind: kind, text: text, updatedNumber: updatedLine++));
        updatedRemaining--;
    }
  }

  DiffHunk build() => DiffHunk(header: header, lines: _lines);
}

/// The uncommitted changes of one repository of a workflow.
final class RepositoryDiff {
  const RepositoryDiff({required this.name, required this.path, required this.patch, required this.isTruncated});

  /// Short name, e.g. the folder name.
  final String name;
  final String path;
  final String patch;
  final bool isTruncated;
}
