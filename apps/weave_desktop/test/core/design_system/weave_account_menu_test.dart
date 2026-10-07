import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  test('builds initials from at most the first two name parts', () {
    expect(WeaveAvatar.initialsFor('Hùng'), 'H');
    expect(WeaveAvatar.initialsFor('Hùng Lê'), 'HL');
    expect(WeaveAvatar.initialsFor('Hùng Lê Quang'), 'HL');
    expect(WeaveAvatar.initialsFor('  '), '?');
  });

  testWidgets('account button keeps a 40 px avatar in both sidebar layouts', (WidgetTester tester) async {
    int presses = 0;
    await pumpComponent(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 240,
            child: WeaveAccountButton(name: 'Hùng Lê Quang', expanded: true, onPressed: () => presses++),
          ),
          WeaveAccountButton(name: 'Hùng Lê Quang', expanded: false, onPressed: () => presses++),
        ],
      ),
    );

    expect(find.text('HL'), findsNWidgets(2));
    expect(tester.getSize(find.byType(WeaveAvatar).first), const Size.square(WeaveLayout.accountAvatarSize));
    expect(find.text('Hùng Lê Quang'), findsOneWidget);

    await tester.tap(find.byType(WeaveAccountButton).first);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(presses, 2);
  });

  testWidgets('account menu exposes the real Settings action', (WidgetTester tester) async {
    WeaveAccountAction? selected;
    await pumpComponent(tester, WeaveAccountMenu(name: 'Hùng Lê Quang', onSelected: (WeaveAccountAction action) => selected = action));

    expect(find.text('Local profile'), findsOneWidget);
    expect(find.text('⌘,'), findsOneWidget);
    expect(find.text('Log out'), findsNothing, reason: 'Weave has no account session to log out from yet');
    await tester.tap(find.text('Settings'));
    expect(selected, WeaveAccountAction.settings);
  });
}
