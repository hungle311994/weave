import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every UI icon and brand mark is a bundled single-colour SVG', () async {
    final List<String> assets = <String>[for (final WeaveIcons icon in WeaveIcons.values) icon.assetPath, for (final BrandMark mark in BrandMark.values) mark.assetPath];
    expect(assets.toSet(), hasLength(assets.length));
    for (final String asset in assets) {
      final String svg = await rootBundle.loadString(asset);
      expect(svg, startsWith('<svg'), reason: asset);
      expect(RegExp('#[0-9A-Fa-f]{6}').allMatches(svg).map((Match match) => match.group(0)!.toUpperCase()).toSet(), <String>{'#000000'}, reason: '$asset must be drawn in black so it can be tinted');
    }
  });

  test('brand marks resolve by the name used in agent and MCP data', () {
    expect(BrandMark.byName('anthropic'), BrandMark.anthropic);
    expect(BrandMark.byName('openai')?.color, WeaveColors.purple);
    expect(BrandMark.byName('unknown'), isNull);
    expect(BrandMark.byName(null), isNull);
  });

  testWidgets('WeaveIcon is tinted with its colour or the ambient icon colour', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WeaveIcon(WeaveIcons.play, size: 18, color: WeaveColors.green),
          IconTheme(
            data: IconThemeData(color: WeaveColors.blue),
            child: WeaveIcon(WeaveIcons.lock, semanticLabel: 'Locked'),
          ),
        ],
      ),
    );
    final List<SvgPicture> pictures = tester.widgetList<SvgPicture>(find.byType(SvgPicture)).toList();
    expect(pictures.first.width, 18);
    expect(pictures.first.colorFilter, const ColorFilter.mode(WeaveColors.green, BlendMode.srcIn));
    expect(pictures.last.colorFilter, const ColorFilter.mode(WeaveColors.blue, BlendMode.srcIn));
    expect(find.bySemanticsLabel('Locked'), findsOneWidget);
  });

  testWidgets('BrandIcon uses the brand colour unless overridden', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          BrandIcon(BrandMark.anthropic),
          BrandIcon(BrandMark.github, color: WeaveColors.textSecondary),
        ],
      ),
    );
    final List<SvgPicture> pictures = tester.widgetList<SvgPicture>(find.byType(SvgPicture)).toList();
    expect(pictures.first.colorFilter, const ColorFilter.mode(WeaveColors.coral, BlendMode.srcIn));
    expect(pictures.last.colorFilter, const ColorFilter.mode(WeaveColors.textSecondary, BlendMode.srcIn));
  });
}
