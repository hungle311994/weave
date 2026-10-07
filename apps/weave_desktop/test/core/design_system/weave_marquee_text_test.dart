import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

const String _title = 'A workflow title that does not fit in its card at all';

void main() {
  double offset(WidgetTester tester) => tester.state<ScrollableState>(find.descendant(of: find.byType(WeaveMarqueeText), matching: find.byType(Scrollable))).position.pixels;

  testWidgets('waits, then scrolls slowly at a fixed speed, and resets on exit', (WidgetTester tester) async {
    await pumpComponent(tester, const SizedBox(width: 80, child: WeaveMarqueeText(_title)));
    final TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(WeaveMarqueeText)));
    await tester.pump();

    await tester.pump(WeaveMotion.marqueeDelay - const Duration(milliseconds: 100));
    expect(offset(tester), 0, reason: 'a passing pointer does not start it');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(offset(tester), closeTo(WeaveMotion.marqueeSpeed, 2), reason: 'one second moves marqueeSpeed pixels, whatever the length');
    expect(tester.getSemantics(find.byType(WeaveMarqueeText)), matchesSemantics(label: _title));

    await mouse.moveTo(const Offset(-10, -10));
    await tester.pump();
    await tester.pump(WeaveMotion.standard);
    expect(offset(tester), 0);
    await tester.pump(const Duration(seconds: 5));
    expect(offset(tester), 0, reason: 'the loop stops when the pointer leaves');
  });

  testWidgets('a parent can drive it, and it loops back to the start while active', (WidgetTester tester) async {
    Widget marquee(bool active) => SizedBox(width: 80, child: WeaveMarqueeText(_title, active: active));
    await pumpComponent(tester, marquee(true));
    await tester.pump();
    await tester.pump(WeaveMotion.marqueeDelay);
    await tester.pump(const Duration(seconds: 30));
    final double end = tester.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent;
    expect(offset(tester), end);
    await tester.pump(WeaveMotion.marqueePause);
    await tester.pump(WeaveMotion.slow);
    expect(offset(tester), 0, reason: 'returns to the start after resting at the end');

    await pumpComponent(tester, marquee(false));
    await tester.pump(const Duration(seconds: 10));
    expect(offset(tester), 0);
  });

  testWidgets('stays still when animations are reduced', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: SizedBox(width: 80, child: WeaveMarqueeText(_title, active: true)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(offset(tester), 0);
  });
}
