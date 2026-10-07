import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  testWidgets('matches the selected expanded navigation item', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    int presses = 0;
    await pumpComponent(
      tester,
      SizedBox(
        width: 256,
        child: WeaveNavigationItem(label: 'Agents', icon: WeaveIcons.bot, onPressed: () => presses += 1, expanded: true, selected: true),
      ),
    );

    expect(tester.getSize(find.byType(WeaveNavigationItem)).height, WeaveLayout.sidebarItemHeight);
    expect(decorationAround(tester, find.text('Agents')).gradient, WeaveGradients.navSelected);
    expect(tester.getSemantics(find.text('Agents')).label, 'Agents');

    await tester.tap(find.text('Agents'));
    expect(presses, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(presses, 2);
    semantics.dispose();
  });

  testWidgets('uses a 48 px icon hit area and tooltip when collapsed', (WidgetTester tester) async {
    await pumpComponent(tester, WeaveNavigationItem(label: 'Agents', icon: WeaveIcons.bot, onPressed: () {}, expanded: false));

    expect(tester.getSize(find.byType(WeaveNavigationItem)), const Size.square(WeaveLayout.sidebarItemHeight));
    expect(find.byTooltip('Agents'), findsOneWidget);
  });

  testWidgets('a collapsed item can leave out its tooltip', (WidgetTester tester) async {
    await pumpComponent(tester, WeaveNavigationItem(label: 'Home', icon: WeaveIcons.home, onPressed: () {}, expanded: false, tooltip: false));

    expect(find.byType(WeaveTooltip), findsNothing);
    expect(find.bySemanticsLabel('Home'), findsOneWidget, reason: 'still named for assistive technology');
  });
}
