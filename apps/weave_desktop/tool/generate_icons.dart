// Writes the icon assets from tool/icons/icon_sources.dart. Run from apps/weave_desktop:
//
//   fvm dart run tool/generate_icons.dart                    # UI icons
//   fvm dart run tool/generate_icons.dart --brands <folder>  # also rebuild the brand marks
//   fvm dart run tool/generate_icons.dart --check            # exit 1 if any asset is stale
import 'dart:io';

import 'icons/icon_sources.dart';

void main(List<String> arguments) {
  final bool check = arguments.contains('--check');
  final int brandsFlag = arguments.indexOf('--brands');
  final String? brandFolder = brandsFlag >= 0 && brandsFlag + 1 < arguments.length ? arguments[brandsFlag + 1] : null;
  if (brandsFlag >= 0 && brandFolder == null) {
    stderr.writeln('--brands needs the folder that holds the brand source SVGs');
    exit(64);
  }

  final Map<String, String> expected = <String, String>{for (final MapEntry<String, String>(:String key, :String value) in uiIcons.entries) 'assets/icons/$key.svg': value};
  if (brandFolder != null) {
    for (final MapEntry<String, BrandSource>(:String key, :BrandSource value) in brandSources.entries) {
      expected['assets/icons/brand/$key.svg'] = brandSvg(File('$brandFolder/${value.sourceFile}').readAsStringSync(), value);
    }
  }

  final List<String> stale = <String>[
    for (final MapEntry<String, String>(:String key, :String value) in expected.entries)
      if (!File(key).existsSync() || File(key).readAsStringSync() != value) key,
  ];
  if (check) {
    if (stale.isEmpty) {
      stdout.writeln('All ${expected.length} icons are up to date.');
      return;
    }
    stderr.writeln('Stale icons (run tool/generate_icons.dart):\n  ${stale.join('\n  ')}');
    exit(1);
  }
  for (final String asset in stale) {
    File(asset)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(expected[asset]!);
  }
  stdout.writeln('Wrote ${stale.length} of ${expected.length} icons.');
}
