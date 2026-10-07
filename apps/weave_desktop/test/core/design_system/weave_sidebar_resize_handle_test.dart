import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

const Key _surface = Key('sidebar-resize-handle-surface');

Color? _surfaceColor(WidgetTester tester) => (tester.widget<AnimatedContainer>(find.byKey(_surface)).decoration! as BoxDecoration).color;

Future<void> _pumpHandle(WidgetTester tester, {VoidCallback? onToggle, GestureDragEndCallback? onDragEnd}) => pumpComponent(
  tester,
  WeaveSidebarResizeHandle(
    expanded: true,
    onToggle: onToggle ?? () {},
    onDragStart: (DragStartDetails details) {},
    onDragUpdate: (DragUpdateDetails details) {},
    onDragEnd: onDragEnd ?? (DragEndDetails details) {},
  ),
);

void main() {
  testWidgets('keeps a wide hit target without a permanent grip and supports pointer and keyboard toggles', (WidgetTester tester) async {
    int toggles = 0;
    await _pumpHandle(tester, onToggle: () => toggles++);

    expect(tester.getSize(find.byKey(_surface)).width, WeaveLayout.sidebarResizeHandleWidth);
    expect(find.byKey(const Key('sidebar-resize-grip')), findsNothing);
    expect(find.bySemanticsLabel('Resize sidebar'), findsOneWidget);

    await tester.tap(find.byKey(_surface));
    expect(toggles, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(toggles, 2);
  });

  testWidgets('forwards horizontal drag gestures', (WidgetTester tester) async {
    double distance = 0;
    bool started = false;
    bool ended = false;
    await pumpComponent(
      tester,
      WeaveSidebarResizeHandle(
        expanded: false,
        onToggle: () {},
        onDragStart: (DragStartDetails details) => started = true,
        onDragUpdate: (DragUpdateDetails details) => distance += details.delta.dx,
        onDragEnd: (DragEndDetails details) => ended = true,
      ),
    );

    await tester.drag(find.byKey(_surface), const Offset(80, 0));

    expect(started, isTrue);
    expect(distance, greaterThan(0));
    expect(ended, isTrue);
  });

  group('highlight', () {
    testWidgets('is neutral at rest and purple only while the pointer hovers', (WidgetTester tester) async {
      await _pumpHandle(tester);
      expect(_surfaceColor(tester), WeaveColors.sidebar);

      final TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(_surface)));
      await tester.pumpAndSettle();
      expect(_surfaceColor(tester), WeaveColors.tint(WeaveColors.purple));

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(_surfaceColor(tester), WeaveColors.sidebar);
    });

    testWidgets('stays purple while dragging and turns neutral once released away from the handle', (WidgetTester tester) async {
      bool ended = false;
      await _pumpHandle(tester, onDragEnd: (DragEndDetails details) => ended = true);

      final TestGesture drag = await tester.startGesture(tester.getCenter(find.byKey(_surface)), kind: PointerDeviceKind.mouse);
      await drag.moveBy(const Offset(40, 0));
      await drag.moveBy(const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(_surfaceColor(tester), WeaveColors.tint(WeaveColors.purple), reason: 'the pointer left the handle but the drag is still in progress');

      await drag.up();
      await tester.pumpAndSettle();
      expect(ended, isTrue);
      expect(_surfaceColor(tester), WeaveColors.sidebar);
      expect(Focus.of(tester.element(find.byKey(_surface))).hasFocus, isFalse, reason: 'pointer use must not leave keyboard focus on the handle');
    });

    testWidgets('keyboard focus does not look like pointer hover', (WidgetTester tester) async {
      await _pumpHandle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(Focus.of(tester.element(find.byKey(_surface))).hasFocus, isTrue);
      expect(_surfaceColor(tester), WeaveColors.sidebar);
    });
  });
}
