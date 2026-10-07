import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  testWidgets('primary button draws the gradient and reports taps', (WidgetTester tester) async {
    int taps = 0;
    await pumpComponent(tester, WeaveButton.primary(label: 'Start workflow', icon: WeaveIcons.play, onPressed: () => taps++));
    final BoxDecoration decoration = decorationAround(tester, find.text('Start workflow'));
    expect(decoration.gradient, WeaveGradients.primary);
    expect((decoration.border! as Border).top.color, WeaveColors.purple);
    expect(tester.getSize(find.byType(WeaveButton)).height, WeaveLayout.controlHeight);
    expect(find.byType(WeaveIcon), findsOneWidget);
    expect(tester.widget<InkWell>(find.byType(InkWell)).mouseCursor, SystemMouseCursors.click);
    await tester.tap(find.text('Start workflow'));
    expect(taps, 1);
  });

  testWidgets('regular buttons keep the dialog minimum width; small buttons hug their label', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WeaveButton.primary(key: const Key('save'), label: 'Save', onPressed: () {}),
          WeaveButton(key: const Key('ok'), label: 'OK', size: WeaveButtonSize.small, onPressed: () {}),
        ],
      ),
    );
    expect(tester.getSize(find.byKey(const Key('save'))).width, WeaveLayout.buttonMinWidth);
    expect(tester.getSize(find.byKey(const Key('ok'))).width, lessThan(WeaveLayout.buttonMinWidth));
    expect(tester.getCenter(find.text('Save')).dx, tester.getCenter(find.byKey(const Key('save'))).dx, reason: 'the label stays centred in the wider button');
  });

  testWidgets('each variant uses its design colours', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WeaveButton(label: 'Pause', onPressed: () {}),
          WeaveButton.danger(label: 'Cancel', onPressed: () {}),
          WeaveButton(label: 'View diff', variant: WeaveButtonVariant.ghost, size: WeaveButtonSize.small, onPressed: () {}),
        ],
      ),
    );
    expect(decorationAround(tester, find.text('Pause')).color, WeaveColors.surfaceRaised);
    final BoxDecoration danger = decorationAround(tester, find.text('Cancel'));
    expect(danger.color, WeaveColors.redSurface);
    expect((danger.border! as Border).top.color, WeaveColors.redStrong);
    expect(tester.widget<Text>(find.text('Cancel')).style?.color, WeaveColors.red);
    expect(decorationAround(tester, find.text('View diff')).border, isNull);
    expect(tester.getSize(find.ancestor(of: find.text('View diff'), matching: find.byType(WeaveButton))).height, 32);
  });

  testWidgets('a disabled button is dimmed and ignores taps', (WidgetTester tester) async {
    await pumpComponent(tester, const WeaveButton.primary(label: 'Approve', onPressed: null));
    expect(tester.widget<Opacity>(find.ancestor(of: find.text('Approve'), matching: find.byType(Opacity))).opacity, 0.45);
    expect(tester.widget<InkWell>(find.byType(InkWell)).mouseCursor, SystemMouseCursors.forbidden);
    await tester.tap(find.text('Approve'));
    expect(tester.getSemantics(find.byType(WeaveButton)), isSemantics(isButton: true, hasEnabledState: true, isEnabled: false));
  });

  testWidgets('a button can be focused and activated from the keyboard', (WidgetTester tester) async {
    int taps = 0;
    await pumpComponent(tester, WeaveButton(label: 'Change…', onPressed: () => taps++));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('icon button shows its tooltip, border and selection', (WidgetTester tester) async {
    int taps = 0;
    await pumpComponent(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WeaveIconButton(icon: WeaveIcons.panelClose, tooltip: 'Collapse sidebar', bordered: true, onPressed: () => taps++),
          WeaveIconButton(icon: WeaveIcons.plus, tooltip: 'New task', size: 48, selected: true, onPressed: () {}),
        ],
      ),
    );
    expect(find.byTooltip('Collapse sidebar'), findsOneWidget);
    expect(find.bySemanticsLabel('Collapse sidebar'), findsOneWidget);
    expect(tester.getSize(find.byType(WeaveIconButton).last), const Size(48, 48));
    final BoxDecoration bordered = decorationAround(tester, find.byType(WeaveIcon).first);
    expect((bordered.border! as Border).top.color, WeaveColors.borderSubtle);
    final BoxDecoration selected = decorationAround(tester, find.byType(WeaveIcon).last);
    expect(selected.color, WeaveColors.surfaceSelected);
    expect(tester.widgetList<InkWell>(find.byType(InkWell)).every((InkWell inkWell) => inkWell.mouseCursor == SystemMouseCursors.click), isTrue);
    await tester.tap(find.byType(WeaveIconButton).first);
    expect(taps, 1);
  });
}
