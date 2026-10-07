import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../../helpers/app_test_harness.dart';

void main() {
  late AppTestHarness harness;

  setUp(() async {
    harness = AppTestHarness();
    await harness.initialize();
  });
  tearDown(() => harness.dispose());

  testWidgets('shows the fixed safety policy without editable controls', (WidgetTester tester) async {
    await harness.launch(tester, size: WeaveLayout.defaultWindow);
    await tester.tap(find.byKey(const Key('sidebar-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Permissions & safety'), findsOneWidget);
    expect(find.text('These guards are enforced by Weave and cannot be weakened by an agent.'), findsOneWidget);
    expect(find.text('Read only'), findsWidgets);
    expect(find.text('Push is not supported.', findRichText: true), findsNothing);
    expect(find.textContaining('Push is not supported.'), findsOneWidget);
    expect(find.byType(WeaveSwitch), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reflows policy cards at the minimum window size', (WidgetTester tester) async {
    await harness.launch(tester, size: WeaveLayout.minimumWindow);
    await tester.tap(find.byKey(const Key('sidebar-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final Rect navigation = tester.getRect(find.byKey(const Key('settings-navigation')));
    final Rect permissions = tester.getRect(find.byKey(const Key('permissions-card')));
    final Rect currentPolicy = tester.getRect(find.byKey(const Key('current-policy-card')));
    expect(permissions.top, greaterThan(navigation.bottom));
    expect(currentPolicy.top, greaterThan(permissions.bottom));
    expect(tester.takeException(), isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('sidebar-shell'))).width, WeaveLayout.sidebarCollapsed);
    expect(tester.takeException(), isNull, reason: 'Settings also reflows with the sidebar collapsed');
  });
}
