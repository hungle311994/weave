import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  testWidgets('dialog has the exact frame, typography, accent shadow and close semantics', (WidgetTester tester) async {
    int closes = 0;
    await pumpComponent(
      tester,
      WeaveDialog(
        title: 'Choose repository',
        subtitle: 'Select a local Git repository for this workflow.',
        accent: WeaveColors.green,
        onClose: () => closes++,
        body: const Text('Repository list'),
        actions: <Widget>[
          WeaveButton(label: 'Cancel', onPressed: () {}),
          WeaveButton.primary(label: 'Use repository', onPressed: () {}),
        ],
      ),
    );
    expect(tester.getSize(find.byType(WeaveDialog)), const Size(WeaveLayout.dialogWidth, WeaveLayout.dialogHeight));
    final BoxDecoration decoration = decorationAround(tester, find.text('Choose repository'));
    expect(decoration.color, WeaveColors.surface);
    expect(decoration.borderRadius, WeaveRadii.dialogAll);
    expect((decoration.border! as Border).top.color, WeaveColors.borderStrong);
    expect(decoration.boxShadow, WeaveShadows.dialog(WeaveColors.green));
    expect(tester.widget<Text>(find.text('Choose repository')).style, WeaveTypography.titleLarge);
    expect(tester.widget<Text>(find.text('Select a local Git repository for this workflow.')).style, WeaveTypography.bodySmall);
    expect(find.bySemanticsLabel('Close dialog'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close dialog'));
    await tester.pump();
    expect(closes, 1);
  });

  testWidgets('showWeaveDialog closes on Escape and traps traversal in the route', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      Builder(
        builder: (BuildContext context) => WeaveButton(
          label: 'Open dialog',
          onPressed: () => showWeaveDialog<void>(
            context: context,
            title: 'Dialog title',
            body: const WeaveTextField(label: 'Name'),
            actions: <Widget>[WeaveButton.primary(label: 'Save', onPressed: () {})],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(find.byType(WeaveDialog), findsOneWidget);
    for (int index = 0; index < 6; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
      expect(focused, isNotNull);
      expect(find.ancestor(of: find.byElementPredicate((Element element) => element == focused), matching: find.byType(WeaveDialog)), findsOneWidget);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(WeaveDialog), findsNothing);
  });

  testWidgets('popover uses menu dimensions, selected treatment and arrow-key selection', (WidgetTester tester) async {
    String? selected;
    await pumpComponent(
      tester,
      WeavePopoverMenu<String>(
        onSelected: (String value) => selected = value,
        groups: const <WeavePopoverGroup<String>>[
          WeavePopoverGroup<String>(
            label: 'Workspaces',
            items: <WeavePopoverItem<String>>[
              WeavePopoverItem<String>(value: 'weave', title: 'Weave', subtitle: '3 folders', icon: WeaveIcons.layers, selected: true),
              WeavePopoverItem<String>(value: 'app', title: 'App', subtitle: 'Single folder', brand: BrandMark.openai),
            ],
          ),
          WeavePopoverGroup<String>(
            items: <WeavePopoverItem<String>>[WeavePopoverItem<String>(value: 'new', title: 'New workspace…', icon: WeaveIcons.plus)],
          ),
        ],
      ),
    );
    expect(tester.getSize(find.byType(WeavePopoverMenu<String>)).width, WeaveLayout.popoverWidth);
    final BoxDecoration decoration = decorationAround(tester, find.text('WORKSPACES'));
    expect(decoration.color, WeaveColors.surfaceElevated);
    expect(decoration.borderRadius, WeaveRadii.panelAll);
    expect(decoration.boxShadow, WeaveShadows.popover);
    expect(tester.widget<Text>(find.text('WORKSPACES')).style, WeaveTypography.overline);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byType(BrandIcon), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, 'app');
  });

  group('showWeavePopoverMenu', () {
    List<WeavePopoverGroup<String>> groups(int count) => <WeavePopoverGroup<String>>[
      WeavePopoverGroup<String>(
        items: <WeavePopoverItem<String>>[for (int index = 0; index < count; index++) WeavePopoverItem<String>(value: '$index', title: 'Option $index', icon: WeaveIcons.terminal)],
      ),
    ];

    /// Opens a menu of [count] items from a field at [alignment] and returns
    /// the field's rect.
    Future<Rect> open(WidgetTester tester, Alignment alignment, int count) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WeaveTheme.dark(),
          home: Scaffold(
            body: Align(
              alignment: alignment,
              child: Builder(
                builder: (BuildContext context) => SizedBox(
                  key: const Key('field'),
                  width: 240,
                  height: 44,
                  child: GestureDetector(
                    onTap: () {
                      final RenderBox box = context.findRenderObject()! as RenderBox;
                      showWeavePopoverMenu<String>(context: context, anchor: box.localToGlobal(Offset.zero) & box.size, groups: groups(count), width: box.size.width);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('field')));
      await tester.pumpAndSettle();
      return tester.getRect(find.byKey(const Key('field')));
    }

    testWidgets('opens below a field with room under it', (WidgetTester tester) async {
      final Rect field = await open(tester, Alignment.topCenter, 3);
      final Rect menu = tester.getRect(find.byType(WeavePopoverMenu<String>));
      expect(menu.top, field.bottom + WeaveSpacing.s4);
      expect(menu.width, field.width);
    });

    testWidgets('opens above a field at the bottom edge so the menu stays visible', (WidgetTester tester) async {
      final Rect field = await open(tester, Alignment.bottomCenter, 3);
      final Rect menu = tester.getRect(find.byType(WeavePopoverMenu<String>));
      expect(menu.bottom, field.top - WeaveSpacing.s4);
      expect(find.text('Option 2').hitTestable(), findsOneWidget);
    });

    testWidgets('a menu taller than either side opens on the roomier side and scrolls', (WidgetTester tester) async {
      final Size viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
      final Rect field = await open(tester, const Alignment(0, 0.6), 40);
      final Rect menu = tester.getRect(find.byType(WeavePopoverMenu<String>));
      expect(menu.bottom, field.top - WeaveSpacing.s4, reason: 'more room above than below');
      expect(menu.top, WeaveSpacing.s8);
      expect(menu.bottom, lessThanOrEqualTo(viewport.height));
      expect(find.text('Option 39').hitTestable(), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Option 39'),
        200,
        scrollable: find.descendant(of: find.byType(WeavePopoverMenu<String>), matching: find.byType(Scrollable)),
      );
      expect(find.text('Option 39').hitTestable(), findsOneWidget);
    });
  });

  testWidgets('disabled popover is 45 percent opaque and ignores taps', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const WeavePopoverMenu<String>(
        onSelected: null,
        groups: <WeavePopoverGroup<String>>[
          WeavePopoverGroup<String>(
            items: <WeavePopoverItem<String>>[WeavePopoverItem<String>(value: 'one', title: 'One')],
          ),
        ],
      ),
    );
    expect(tester.widget<Opacity>(find.descendant(of: find.byType(WeavePopoverMenu<String>), matching: find.byType(Opacity))).opacity, 0.45);
    expect(tester.getSemantics(find.text('One')), isSemantics(isButton: true, hasEnabledState: true, isEnabled: false, label: 'One'));
  });

  group('tooltip placement', () {
    const Size overlay = Size(800, 600);
    const Size tooltip = Size(65, 32);

    test('below keeps the tooltip gap from the bottom edge of a 48 px item', () {
      const TooltipPositionContext position = TooltipPositionContext(target: Offset(400, 100), targetSize: Size(48, 48), tooltipSize: tooltip, verticalOffset: 24, overlaySize: overlay);
      expect(WeaveTooltip.positionFor(position, WeaveTooltipPlacement.below).dy, 100 + 24 + WeaveLayout.tooltipGap);
    });

    test('below flips above, still with the gap, when the window has no room below', () {
      const TooltipPositionContext position = TooltipPositionContext(target: Offset(400, 570), targetSize: Size(48, 48), tooltipSize: tooltip, verticalOffset: 24, overlaySize: overlay);
      expect(WeaveTooltip.positionFor(position, WeaveTooltipPlacement.below).dy, 570 - 24 - WeaveLayout.tooltipGap - tooltip.height);
    });

    test('right sits a compact gap beside a collapsed rail item, vertically centred', () {
      // Agents item at x 12, y 244 (48 × 48) in the fixed icon rail.
      const TooltipPositionContext position = TooltipPositionContext(target: Offset(36, 268), targetSize: Size(48, 48), tooltipSize: tooltip, verticalOffset: 24, overlaySize: overlay);
      final Offset topLeft = WeaveTooltip.positionFor(position, WeaveTooltipPlacement.right);
      expect(topLeft, const Offset(60 + WeaveLayout.railTooltipGap, 252), reason: 'just right of the item, not pushed past the rail');
    });

    testWidgets('hovering a 48 px item shows its tooltip clear of the item', (WidgetTester tester) async {
      await pumpComponent(
        tester,
        const WeaveTooltip(
          message: 'Agents',
          child: SizedBox.square(key: Key('target'), dimension: 48),
        ),
      );
      final TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(const Key('target'))));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final Rect target = tester.getRect(find.byKey(const Key('target')));
      final Rect label = tester.getRect(find.text('Agents'));
      expect(label.top - target.bottom, greaterThanOrEqualTo(WeaveLayout.tooltipGap + WeaveSpacing.s6), reason: 'gap plus the tooltip padding');
    });
  });

  testWidgets('tooltip uses elevated surface, subtle border, radius, type and shadow', (WidgetTester tester) async {
    await pumpComponent(tester, const WeaveTooltip(message: 'Helpful text', child: Text('Hover target')));
    final TooltipThemeData theme = Theme.of(tester.element(find.text('Hover target'))).tooltipTheme;
    final BoxDecoration decoration = theme.decoration! as BoxDecoration;
    expect(decoration.color, WeaveColors.surfaceElevated);
    expect((decoration.border! as Border).top.color, WeaveColors.borderSubtle);
    expect(decoration.borderRadius, WeaveRadii.mdAll);
    expect(decoration.boxShadow, WeaveShadows.tooltip);
    expect(theme.textStyle?.fontSize, 12);
    expect(theme.textStyle?.fontWeight, WeaveTypography.medium);
  });
}
