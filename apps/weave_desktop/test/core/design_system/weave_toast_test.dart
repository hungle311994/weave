import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  testWidgets('toast uses the Weave surface and sits at the top centre, clear of page actions', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      Builder(
        builder: (BuildContext context) => WeaveButton(
          label: 'Notify',
          onPressed: () => showWeaveToast(context, message: 'Install command copied.', tone: WeaveToastTone.success),
        ),
      ),
    );

    await tester.tap(find.text('Notify'));
    await tester.pump(WeaveMotion.standard);
    await tester.pump(WeaveMotion.standard);

    final Finder toast = find.byType(WeaveToast);
    final Rect frame = tester.getRect(toast);
    final Rect overlay = tester.getRect(find.byType(Overlay));
    expect(frame.width, WeaveLayout.toastWidth);
    expect(frame.top, overlay.top + WeaveLayout.toastTop);
    expect(frame.center.dx, overlay.center.dx);
    expect(find.bySemanticsLabel(RegExp(r'Install command copied\.')), findsOneWidget);
    final BoxDecoration decoration = decorationAround(tester, find.text('Install command copied.'));
    expect(decoration.color, WeaveColors.surfaceElevated);
    expect((decoration.border! as Border).top.color, WeaveColors.green);

    await tester.tap(find.bySemanticsLabel('Dismiss notification'));
    await tester.pump();
    expect(toast, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset.dx, 0);
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset.dy, lessThan(0), reason: 'dismiss reverses toward the top edge used by the entrance');
    await tester.pump(WeaveMotion.standard);
    await tester.pump();
    expect(toast, findsNothing);
  });

  testWidgets('a new toast replaces the current toast and expires', (WidgetTester tester) async {
    late BuildContext overlayContext;
    await pumpComponent(
      tester,
      Builder(
        builder: (BuildContext context) {
          overlayContext = context;
          return const SizedBox.shrink();
        },
      ),
    );

    showWeaveToast(overlayContext, message: 'First', duration: const Duration(seconds: 10));
    showWeaveToast(overlayContext, message: 'Second', tone: WeaveToastTone.danger);
    await tester.pump(WeaveMotion.standard);

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    final BoxDecoration decoration = decorationAround(tester, find.text('Second'));
    expect((decoration.border! as Border).top.color, WeaveColors.red);

    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(WeaveToast), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(WeaveToast), findsNothing);
  });
}
