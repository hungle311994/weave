import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  testWidgets('cards use the surface of their kind', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WeaveCard(child: Text('Execution timeline')),
          WeaveCard(surface: WeaveSurface.field, child: Text('mama-morsel')),
          WeaveCard(surface: WeaveSurface.selected, child: Text('Claude Code')),
        ],
      ),
    );
    final BoxDecoration card = decorationAround(tester, find.text('Execution timeline'));
    expect(card.gradient, WeaveGradients.card);
    expect(card.boxShadow, WeaveShadows.card);
    expect(card.borderRadius, BorderRadius.circular(WeaveRadii.panel));
    final BoxDecoration field = decorationAround(tester, find.text('mama-morsel'));
    expect(field.color, WeaveColors.surface);
    expect(field.boxShadow, isNull);
    expect((decorationAround(tester, find.text('Claude Code')).border! as Border).top.color, WeaveColors.purple);
  });

  testWidgets('a tappable card behaves like a selectable row', (WidgetTester tester) async {
    int taps = 0;
    await pumpComponent(tester, WeaveCard(surface: WeaveSurface.elevated, onTap: () => taps++, child: const Text('Codex')));
    expect(decorationAround(tester, find.text('Codex')).color, WeaveColors.surfaceElevated);
    await tester.tap(find.text('Codex'));
    expect(taps, 1);
  });

  testWidgets('status pills tint background and border from the tone', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WeaveStatusPill(label: 'Ready', tone: WeaveTone.success),
          WeaveStatusPill(label: 'Offline', tone: WeaveTone.danger),
        ],
      ),
    );
    final BoxDecoration ready = decorationAround(tester, find.text('Ready'));
    expect(ready.color, WeaveColors.tint(WeaveColors.green));
    expect((ready.border! as Border).top.color, WeaveColors.tintBorder(WeaveColors.green));
    expect(tester.widget<Text>(find.text('Ready')).style?.fontWeight, FontWeight.w600);
    expect(tester.widget<Text>(find.text('Offline')).style?.color, WeaveColors.redStrong);
    expect(tester.getSize(find.byType(WeaveStatusPill).first).height, WeaveLayout.statusPillHeight);
  });

  testWidgets('badges use the soft purple for the accent tone or a custom colour', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WeaveBadge(label: '3 folders'),
          WeaveBadge(label: 'Implementer', color: WeaveColors.coral),
          WeaveCountBubble(count: 3),
          WeaveCountBubble(count: 120),
        ],
      ),
    );
    expect(tester.widget<Text>(find.text('3 folders')).style?.color, WeaveColors.purpleSoft);
    expect(decorationAround(tester, find.text('Implementer')).color, WeaveColors.tint(WeaveColors.coral, 0.16));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });
}
