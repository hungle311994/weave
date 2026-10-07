import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Material and Cupertino icons are font glyphs; Weave draws its icons from SVG
/// assets (`WeaveIcon`, `BrandIcon`), so a font glyph renders as a `?` box when
/// the glyph is missing from the bundled (tree-shaken) icon font.
void main() {
  final Map<String, RegExp> forbidden = <String, RegExp>{
    'Material or Cupertino icon data': RegExp(r'\b(Icons|CupertinoIcons)\.'),
    'raw Icon widget': RegExp(r'(?<![A-Za-z_])(Icon|ImageIcon|IconButton)\('),
    'Material button with an icon slot': RegExp(r'\b(FilledButton|OutlinedButton|TextButton|ElevatedButton|FloatingActionButton)\.(icon|tonalIcon)\('),
    'Material widget that draws its own icon glyph': RegExp(r'\b(SegmentedButton|ButtonSegment|DropdownButton|DropdownButtonFormField|DropdownMenu|PopupMenuButton|ExpansionTile|BackButton|CloseButton|DrawerButton|EndDrawerButton|ExpandIcon|SearchAnchor|Stepper)\b'),
  };

  test('the desktop app draws every icon from the design system', () {
    final List<String> hits = <String>[];
    final Iterable<File> sources = Directory('lib').listSync(recursive: true).whereType<File>().where((File file) => file.path.endsWith('.dart'));
    for (final File file in sources) {
      final List<String> lines = file.readAsLinesSync();
      for (int index = 0; index < lines.length; index++) {
        for (final MapEntry<String, RegExp>(:String key, :RegExp value) in forbidden.entries) {
          if (value.hasMatch(lines[index])) {
            hits.add('${file.path}:${index + 1} $key: ${lines[index].trim()}');
          }
        }
      }
    }
    expect(hits, isEmpty, reason: 'Use WeaveIcon, WeaveIconButton, WeaveButton, WeaveSegmentedControl or BrandIcon instead.');
  });

  // Material buttons size and pad themselves differently from each other and
  // from WeaveButton, so mixed action rows end up with uneven hover surfaces.
  // Material's Tooltip measures its offset from the element's centre, so it
  // touches 48 px items; WeaveTooltip keeps a gap from the edge. Raw text
  // fields pick their own line count and density, so heights drift apart.
  // Only the design system itself may wrap these Material widgets.
  test('features use WeaveButton, WeaveTooltip and WeaveTextField instead of the Material widgets', () {
    final RegExp materialControl = RegExp(r'\b(TextButton|FilledButton|OutlinedButton|ElevatedButton)\(|(?<![A-Za-z_])(Tooltip|TextField|TextFormField|InputDecoration)\(');
    final List<String> hits = <String>[
      for (final File file in Directory('lib').listSync(recursive: true).whereType<File>().where((File file) => file.path.endsWith('.dart')))
        for (final (int index, String line) in file.readAsLinesSync().indexed)
          if (materialControl.hasMatch(line) && !file.path.contains('core/design_system/')) '${file.path}:${index + 1} ${line.trim()}',
    ];
    expect(hits, isEmpty);
  });
}
