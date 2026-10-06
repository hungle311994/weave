import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  testWidgets('chips show their icon and call onRemove', (WidgetTester tester) async {
    int removed = 0;
    await pumpComponent(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WeaveChip(label: 'settings_screen.dart', icon: WeaveIcons.fileCode, onRemove: () => removed++),
          const WeaveChip(label: 'main', icon: WeaveIcons.gitBranch, shape: WeaveChipShape.pill),
        ],
      ),
    );
    expect(decorationAround(tester, find.text('settings_screen.dart')).color, WeaveColors.surfaceSunken);
    expect(decorationAround(tester, find.text('main')).borderRadius, WeaveRadii.pillAll);
    expect(find.byTooltip('Remove main'), findsNothing);
    await tester.tap(find.byTooltip('Remove settings_screen.dart'));
    expect(removed, 1);
  });

  testWidgets('text field shows its label, hint and error and reports input', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    String? submitted;
    await pumpComponent(
      tester,
      SizedBox(
        width: 400,
        child: WeaveTextField(controller: controller, label: 'Workspace name', hintText: 'mama-morsel', prefixIcon: WeaveIcons.layers, errorText: 'Required', onSubmitted: (String value) => submitted = value),
      ),
    );
    expect(find.text('Workspace name'), findsOneWidget);
    expect(find.text('mama-morsel'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
    expect(find.byType(WeaveIcon), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'acme-shop');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(controller.text, 'acme-shop');
    expect(submitted, 'acme-shop');
  });

  testWidgets('multiline field starts at four lines and grows', (WidgetTester tester) async {
    await pumpComponent(tester, const SizedBox(width: 400, child: WeaveTextField.multiline(hintText: 'Describe your task')));
    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 4);
    expect(field.maxLines, isNull);
    expect(field.keyboardType, TextInputType.multiline);
  });
}
