import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  testWidgets('reserves one uninterrupted strip for the macOS window controls', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const SizedBox(
        width: WeaveLayout.galleryTileWidth,
        child: WeaveWindowTitleBar(),
      ),
    );

    final Finder titleBar = find.byType(WeaveWindowTitleBar);
    expect(tester.getSize(titleBar), const Size(WeaveLayout.galleryTileWidth, WeaveLayout.windowTitleBarHeight));

    final BoxDecoration decoration = tester.widget<DecoratedBox>(find.byKey(const Key('window-title-bar-surface'))).decoration as BoxDecoration;
    expect(decoration.color, WeaveColors.sidebar);
    expect(
      decoration.border,
      const Border(
        bottom: BorderSide(color: WeaveColors.borderSubtle, width: WeaveLayout.divider),
      ),
    );
  });

  testWidgets('places leading controls right of the traffic lights, on their centre line', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const SizedBox(
        width: WeaveLayout.galleryTileWidth,
        child: WeaveWindowTitleBar(
          leading: SizedBox(key: Key('controls'), width: 80, height: WeaveLayout.windowControlSize),
        ),
      ),
    );

    final Rect bar = tester.getRect(find.byType(WeaveWindowTitleBar));
    final Rect controls = tester.getRect(find.byKey(const Key('controls')));
    expect(controls.left - bar.left, WeaveLayout.windowControlsInset);
    expect(controls.center.dy - bar.top, bar.height / 2, reason: 'vertically centred');
  });

  testWidgets('is twice as tall as the traffic lights are from the top, so they sit in its middle', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const SizedBox(
        width: WeaveLayout.galleryTileWidth,
        child: WeaveWindowTitleBar(
          trafficLightCenter: 17,
          leading: SizedBox(key: Key('controls'), width: 80, height: WeaveLayout.windowControlSize),
        ),
      ),
    );

    expect(tester.getSize(find.byType(WeaveWindowTitleBar)).height, 34);
    expect(tester.getCenter(find.byKey(const Key('controls'))).dy - tester.getTopLeft(find.byType(WeaveWindowTitleBar)).dy, 17, reason: 'on the traffic lights\' centre line');
    expect(WeaveWindowTitleBar.heightFor(4), WeaveLayout.windowTitleBarMinHeight, reason: 'never too short for the controls');
    expect(WeaveWindowTitleBar.heightFor(null), WeaveLayout.windowTitleBarHeight);
  });
}
