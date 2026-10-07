import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  testWidgets('fills the bar to the used share and shows label, percent and reset', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const SizedBox(
        width: 400,
        child: WeaveUsageMeter(label: 'Current session', percentUsed: 28, detail: 'Resets Oct 7 at 8:10pm'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Current session'), findsOneWidget);
    expect(find.text('28%'), findsOneWidget);
    expect(find.text('Resets Oct 7 at 8:10pm'), findsOneWidget);
    final double track = tester.getSize(find.descendant(of: find.byType(WeaveUsageMeter), matching: find.byType(ClipRRect))).width;
    expect(tester.getSize(find.byKey(const Key('weave-usage-meter-fill'))).width, closeTo(track * 0.28, 0.5));
    expect(tester.getSize(find.descendant(of: find.byType(WeaveUsageMeter), matching: find.byType(ClipRRect))).height, WeaveLayout.usageMeterHeight);
  });

  test('turns amber from 70 % and red from 90 %', () {
    expect(WeaveUsageMeter.toneFor(69), WeaveTone.success);
    expect(WeaveUsageMeter.toneFor(70), WeaveTone.warning);
    expect(WeaveUsageMeter.toneFor(89), WeaveTone.warning);
    expect(WeaveUsageMeter.toneFor(90), WeaveTone.danger);
  });

  testWidgets('a value over 100 % keeps the bar inside its track', (WidgetTester tester) async {
    await pumpComponent(tester, const SizedBox(width: 400, child: WeaveUsageMeter(label: 'Week', percentUsed: 130)));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('weave-usage-meter-fill'))).width, tester.getSize(find.descendant(of: find.byType(WeaveUsageMeter), matching: find.byType(ClipRRect))).width);
  });

  testWidgets('the fill grows from zero and then glides to a new value', (WidgetTester tester) async {
    double fill() => tester.getSize(find.byKey(const Key('weave-usage-meter-fill'))).width;
    Widget meter(int percent) => SizedBox(
      width: 400,
      child: WeaveUsageMeter(label: 'Week', percentUsed: percent),
    );

    await pumpComponent(tester, meter(50));
    expect(fill(), 0, reason: 'starts empty');
    await tester.pumpAndSettle();
    expect(fill(), closeTo(200, 0.5));

    await pumpComponent(tester, meter(100));
    await tester.pump(WeaveMotion.slow ~/ 2);
    expect(fill(), allOf(greaterThan(200), lessThan(400)), reason: 'moves between the old and new value');
    await tester.pumpAndSettle();
    expect(fill(), closeTo(400, 0.5));
  });

  testWidgets('a highlight sweeps the bar while refreshing, unless animations are reduced', (WidgetTester tester) async {
    final Finder sweep = find.byKey(const Key('weave-usage-meter-sweep'));
    await pumpComponent(tester, const SizedBox(width: 400, child: WeaveUsageMeter(label: 'Week', percentUsed: 40, refreshing: true)));
    expect(sweep, findsOneWidget);
    final Finder band = find.descendant(of: sweep, matching: find.byType(DecoratedBox));
    final double start = tester.getTopLeft(band).dx;
    await tester.pump(WeaveMotion.sweep ~/ 2);
    expect(tester.getTopLeft(band).dx, isNot(start), reason: 'the highlight moves');

    await pumpComponent(tester, const SizedBox(width: 400, child: WeaveUsageMeter(label: 'Week', percentUsed: 40)));
    expect(sweep, findsNothing);

    await pumpComponent(
      tester,
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: SizedBox(width: 400, child: WeaveUsageMeter(label: 'Week', percentUsed: 40, refreshing: true)),
      ),
    );
    expect(sweep, findsNothing);
  });
}
