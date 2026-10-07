import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  testWidgets('segmented control uses the 35 px purple selected design and supports keyboard activation', (WidgetTester tester) async {
    String value = 'write';
    await pumpComponent(
      tester,
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => WeaveSegmentedControl<String>(
          value: value,
          onChanged: (String next) => setState(() => value = next),
          semanticLabel: 'Repository access',
          segments: const <WeaveSegment<String>>[
            WeaveSegment<String>(value: 'write', label: 'Write', icon: WeaveIcons.pencil),
            WeaveSegment<String>(value: 'read', label: 'Read only', icon: WeaveIcons.eye),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    Rect segment(String label) => tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(InkWell)));
    final Finder indicator = find.byKey(const Key('weave-segment-indicator'));
    final Rect control = tester.getRect(find.byType(WeaveSegmentedControl<String>));

    expect(control.height, WeaveLayout.segmentedControlHeight);
    expect((tester.widget<DecoratedBox>(find.descendant(of: indicator, matching: find.byType(DecoratedBox))).decoration as BoxDecoration).color, WeaveColors.purple.withValues(alpha: 0.2));
    expect(tester.getRect(indicator), segment('Write'));
    expect(segment('Write').left - control.left, WeaveLayout.segmentedControlInset, reason: 'the selection does not touch the border');
    expect(segment('Write').top - control.top, WeaveLayout.segmentedControlInset);
    expect(control.right - segment('Read only').right, WeaveLayout.segmentedControlInset);
    expect(segment('Read only').left - segment('Write').right, WeaveLayout.segmentedControlGap, reason: 'segments do not touch each other');
    expect(tester.getSemantics(find.text('Write')), isSemantics(isButton: true, hasSelectedState: true, isSelected: true, hasEnabledState: true, isEnabled: true, label: 'Write'));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(value, 'read');
    await tester.pump(WeaveMotion.standard ~/ 2);
    final Rect sliding = tester.getRect(indicator);
    expect(sliding.left, greaterThan(segment('Write').left), reason: 'the selection slides instead of jumping');
    expect(sliding.left, lessThan(segment('Read only').left));
    await tester.pumpAndSettle();
    expect(tester.getRect(indicator), segment('Read only'));
  });

  testWidgets('checkbox is 16 px, toggles from the keyboard and dims when disabled', (WidgetTester tester) async {
    bool value = false;
    await pumpComponent(
      tester,
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => WeaveCheckbox(value: value, semanticLabel: 'Include file', onChanged: (bool next) => setState(() => value = next)),
      ),
    );
    expect(tester.getSize(find.byType(WeaveCheckbox)), const Size.square(WeaveLayout.checkboxSize));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(value, isTrue);
    final DecoratedBox checkbox = tester.widget<DecoratedBox>(find.descendant(of: find.byType(WeaveCheckbox), matching: find.byType(DecoratedBox)).first);
    expect((checkbox.decoration as BoxDecoration).color, WeaveColors.purple);
    expect(tester.getSemantics(find.byType(WeaveCheckbox)), isSemantics(hasCheckedState: true, isChecked: true, hasEnabledState: true, isEnabled: true, label: 'Include file'));

    await pumpComponent(tester, const WeaveCheckbox(value: false, semanticLabel: 'Disabled file', onChanged: null));
    expect(tester.widget<Opacity>(find.descendant(of: find.byType(WeaveCheckbox), matching: find.byType(Opacity))).opacity, 0.45);
  });

  testWidgets('switch uses token dimensions, toggled semantics and disabled opacity', (WidgetTester tester) async {
    bool value = true;
    await pumpComponent(
      tester,
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => WeaveSwitch(value: value, semanticLabel: 'Plan checkpoint', onChanged: (bool next) => setState(() => value = next)),
      ),
    );
    expect(tester.getSize(find.byType(WeaveSwitch)), const Size(WeaveLayout.switchWidth, WeaveLayout.switchHeight));
    final DecoratedBox switchTrack = tester.widget<DecoratedBox>(find.descendant(of: find.byType(WeaveSwitch), matching: find.byType(DecoratedBox)).first);
    expect((switchTrack.decoration as BoxDecoration).color, WeaveColors.settingEnabled);
    expect(((switchTrack.decoration as BoxDecoration).border! as Border).top.color, WeaveColors.green);
    expect(tester.getSemantics(find.byType(WeaveSwitch)), isSemantics(hasToggledState: true, isToggled: true, hasEnabledState: true, isEnabled: true, label: 'Plan checkpoint'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(WeaveMotion.fast);
    expect(value, isFalse);

    await pumpComponent(tester, const WeaveSwitch(value: false, semanticLabel: 'Disabled checkpoint', onChanged: null));
    expect(tester.widget<Opacity>(find.descendant(of: find.byType(WeaveSwitch), matching: find.byType(Opacity))).opacity, 0.45);
  });

  testWidgets('select is 52 px and opens a keyboard-selectable popover', (WidgetTester tester) async {
    String value = 'codex';
    await pumpComponent(
      tester,
      SizedBox(
        width: 400,
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => WeaveSelect<String>(
            value: value,
            semanticLabel: 'Planner default',
            onChanged: (String next) => setState(() => value = next),
            options: const <WeavePopoverItem<String>>[
              WeavePopoverItem<String>(value: 'codex', title: 'Codex', brand: BrandMark.openai, selected: true),
              WeavePopoverItem<String>(value: 'claude', title: 'Claude Code', brand: BrandMark.anthropic),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(WeaveSelect<String>)).height, WeaveLayout.selectHeight);
    expect((decorationAround(tester, find.text('Codex')).border! as Border).top.color, WeaveColors.border);
    await tester.tap(find.byType(WeaveSelect<String>));
    await tester.pumpAndSettle();
    expect(find.byType(WeavePopoverMenu<String>), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(value, 'claude');
  });
}
