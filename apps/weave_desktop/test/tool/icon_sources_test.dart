import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../tool/icons/icon_sources.dart';

void main() {
  test('every UI icon asset matches its source definition', () {
    for (final MapEntry<String, String>(:String key, :String value) in uiIcons.entries) {
      expect(File('assets/icons/$key.svg').readAsStringSync(), value, reason: '$key.svg is stale — run fvm dart run tool/generate_icons.dart');
    }
  });

  test('icon sources, assets and enums list the same icons', () {
    final Set<String> assets = <String>{
      for (final FileSystemEntity entity in Directory('assets/icons').listSync())
        if (entity is File && entity.path.endsWith('.svg')) entity.uri.pathSegments.last.replaceAll('.svg', ''),
    };
    expect(assets, uiIcons.keys.toSet());
    expect(<String>{for (final WeaveIcons icon in WeaveIcons.values) icon.fileName}, uiIcons.keys.toSet());

    final Set<String> brandAssets = <String>{
      for (final FileSystemEntity entity in Directory('assets/icons/brand').listSync())
        if (entity is File) entity.uri.pathSegments.last.replaceAll('.svg', ''),
    };
    expect(brandAssets, brandSources.keys.toSet());
    expect(<String>{for (final BrandMark mark in BrandMark.values) mark.fileName}, brandSources.keys.toSet());
  });

  test('a brand mark keeps the single path of its source and the chosen viewBox', () {
    const BrandSource source = BrandSource('example.svg', viewBox: '1 2 3 4');
    expect(brandSvg('<svg viewBox="0 0 24 24"><title>X</title><path d="M0 0h1z"/></svg>', source), '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="1 2 3 4" fill="#000000"><path d="M0 0h1z"/></svg>\n');
    expect(() => brandSvg('<svg><path d="M0 0"/><path d="M1 1"/></svg>', source), throwsFormatException);
  });
}
