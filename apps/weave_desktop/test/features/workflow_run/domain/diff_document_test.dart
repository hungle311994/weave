import 'package:flutter_test/flutter_test.dart';
import 'package:weave/features/workflow_run/domain/diff_document.dart';

const String _modified = '''
diff --git a/lib/login_screen.dart b/lib/login_screen.dart
index 1111111..2222222 100644
--- a/lib/login_screen.dart
+++ b/lib/login_screen.dart
@@ -82,4 +82,5 @@ class _LoginScreenState
 Future<void> _submit() async {
-  await login(
-    email,
+  if (_busy) return;
+  await login(
+    email,
   );
''';

const String _untracked = '''
diff --git a/test/login_test.dart b/test/login_test.dart
new file mode 100644
index 0000000..3333333
--- /dev/null
+++ b/test/login_test.dart
@@ -0,0 +1,2 @@
+void main() {}
+
''';

void main() {
  group('DiffDocument.parse', () {
    test('reads files, statuses, counts and line numbers', () {
      final DiffDocument document = DiffDocument.parse('$_modified$_untracked');

      expect(document.files.map((DiffFile file) => file.path), <String>['lib/login_screen.dart', 'test/login_test.dart']);
      expect(document.additions, 5);
      expect(document.deletions, 2);

      final DiffFile modified = document.files.first;
      expect(modified.status, DiffFileStatus.modified);
      expect(modified.hunks.single.header, startsWith('@@ -82,4 +82,5 @@'));
      final List<DiffLine> lines = modified.hunks.single.lines;
      expect(lines.first.kind, DiffLineKind.context);
      expect((lines.first.originalNumber, lines.first.updatedNumber), (82, 82));
      expect(lines[1].kind, DiffLineKind.removed);
      expect((lines[1].originalNumber, lines[1].updatedNumber), (83, null));
      expect(lines[3].kind, DiffLineKind.added);
      expect((lines[3].originalNumber, lines[3].updatedNumber), (null, 83));
      expect((lines.last.originalNumber, lines.last.updatedNumber), (85, 86));
      expect((modified.originalLineCount, modified.updatedLineCount), (4, 5));

      final DiffFile added = document.files.last;
      expect(added.status, DiffFileStatus.added);
      expect(added.hunks.single.lines.map((DiffLine line) => line.text), <String>['void main() {}', '']);
    });

    test('pairs a removed run with the added run that replaces it', () {
      final List<SplitDiffRow> rows = DiffDocument.parse(_modified).files.single.hunks.single.splitRows;

      expect(rows, hasLength(5));
      expect(rows.first.original?.text, rows.first.updated?.text);
      expect(rows[1].original?.text, '  await login(');
      expect(rows[1].updated?.text, '  if (_busy) return;');
      expect(rows[3].original, isNull, reason: 'three added lines face two removed ones');
      expect(rows[3].updated?.text, '    email,');
      expect(rows.last.original?.kind, DiffLineKind.context);
    });

    test('recognises deletions, renames and binary files', () {
      final DiffDocument document = DiffDocument.parse('''
diff --git a/old.txt b/old.txt
deleted file mode 100644
--- a/old.txt
+++ /dev/null
@@ -1 +0,0 @@
-gone
diff --git a/a.dart b/b.dart
similarity index 100%
rename from a.dart
rename to b.dart
diff --git a/logo.png b/logo.png
Binary files a/logo.png and b/logo.png differ
''');

      expect(document.files.map((DiffFile file) => (file.path, file.status)), <(String, DiffFileStatus)>[('old.txt', DiffFileStatus.deleted), ('b.dart', DiffFileStatus.renamed), ('logo.png', DiffFileStatus.modified)]);
      expect(document.files[1].originalPath, 'a.dart');
      expect(document.files[2].isBinary, isTrue);
      expect(document.files[2].hunks, isEmpty);
    });

    test('merges staged and unstaged sections of the same file', () {
      final DiffDocument document = DiffDocument.parse('$_modified\n$_modified');
      expect(document.files, hasLength(1));
      expect(document.files.single.hunks, hasLength(2));
    });

    test('keeps what was read from a truncated patch and ignores no-newline markers', () {
      final DiffDocument document = DiffDocument.parse('''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
-one
\\ No newline at end of file
+uno
 two
diff --git a/b.txt b/b.txt
--- a/b.txt
+++ b/b.txt
@@ -1,3 +1,3 @@
 first''');

      expect(document.files.map((DiffFile file) => file.path), <String>['a.txt', 'b.txt']);
      expect(document.files.first.hunks.single.lines.map((DiffLine line) => line.text), <String>['one', 'uno', 'two']);
      expect(document.files.last.hunks.single.lines.single.text, 'first');
    });

    test('an empty patch has no files', () {
      expect(DiffDocument.parse('').isEmpty, isTrue);
    });
  });

  test('combines several repositories, labelling each file, and leaves a single one as is', () {
    final DiffDocument single = DiffDocument.parse(_modified);
    expect(DiffDocument.combine(<String, DiffDocument>{'flutter': single}).files.single.path, 'lib/login_screen.dart');

    final DiffDocument combined = DiffDocument.combine(<String, DiffDocument>{'flutter': single, 'backend': DiffDocument.parse(_untracked)});
    expect(combined.files.map((DiffFile file) => (file.repository, file.path)), <(String?, String)>[('flutter', 'flutter/lib/login_screen.dart'), ('backend', 'backend/test/login_test.dart')]);
    expect(combined.additions, 5);
  });
}
