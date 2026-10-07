import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

const Key _content = Key('content');
final Finder _gutter = find.byKey(const Key('weave-scrollbar-gutter'));

Widget _verticalList() => const SizedBox(
  width: 300,
  height: 200,
  child: SingleChildScrollView(
    child: SizedBox(key: _content, height: 600, width: double.infinity),
  ),
);

void main() {
  test('the scrollbar thumb and its margins fit exactly in the gutter', () {
    final ScrollbarThemeData theme = WeaveTheme.dark().scrollbarTheme;
    expect(theme.thickness!.resolve(<WidgetState>{}), WeaveLayout.scrollbarThickness);
    expect(theme.thickness!.resolve(<WidgetState>{WidgetState.hovered}), WeaveLayout.scrollbarThickness);
    expect(theme.crossAxisMargin, WeaveLayout.scrollbarMargin);
    expect(WeaveLayout.scrollbarGutter, WeaveLayout.scrollbarThickness + 2 * WeaveLayout.scrollbarMargin);
  });

  testWidgets('desktop vertical scroll views keep content out of the scrollbar gutter', (WidgetTester tester) async {
    await pumpComponent(tester, _verticalList());

    final Rect scrollbar = tester.getRect(find.byType(Scrollbar));
    final Rect content = tester.getRect(find.byKey(_content));
    expect(scrollbar.width, 300);
    expect(content.width, 300 - WeaveLayout.scrollbarGutter);
    expect(content.right, scrollbar.right - WeaveLayout.scrollbarGutter);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('a switch at the right edge of a dialog body is not covered by the scrollbar', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      WeaveDialog(
        title: 'Advanced workflow settings',
        body: Column(
          children: <Widget>[
            for (int index = 0; index < 20; index++)
              Row(
                children: <Widget>[
                  Expanded(child: Text('Setting $index')),
                  WeaveSwitch(key: ValueKey<int>(index), value: index.isEven, onChanged: (bool value) {}, semanticLabel: 'Setting $index'),
                ],
              ),
          ],
        ),
      ),
    );

    final Rect scrollbar = tester.getRect(find.descendant(of: find.byType(WeaveDialog), matching: find.byType(Scrollbar)));
    final Rect firstSwitch = tester.getRect(find.byKey(const ValueKey<int>(0)));
    expect(firstSwitch.right, lessThanOrEqualTo(scrollbar.right - WeaveLayout.scrollbarGutter));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('horizontal scroll views and multiline text fields get no gutter', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const SizedBox(
        width: 300,
        height: 200,
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 40,
              child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: 900, height: 40)),
            ),
            TextField(minLines: 3, maxLines: 3),
          ],
        ),
      ),
    );

    expect(_gutter, findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('touch platforms keep the default overlay-free behaviour', (WidgetTester tester) async {
    await pumpComponent(tester, _verticalList());

    expect(_gutter, findsNothing);
    expect(tester.getRect(find.byKey(_content)).width, 300);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
