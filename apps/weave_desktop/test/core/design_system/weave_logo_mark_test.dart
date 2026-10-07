import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  testWidgets('renders the Weave mark at the requested size with semantics', (WidgetTester tester) async {
    await pumpComponent(tester, const WeaveLogoMark(size: WeaveSpacing.s48));

    final Finder mark = find.byType(WeaveLogoMark);
    expect(tester.getSize(mark), const Size.square(WeaveSpacing.s48));
    expect(find.descendant(of: mark, matching: find.byType(CustomPaint)), findsOneWidget);
    expect(find.bySemanticsLabel('Weave logo'), findsOneWidget);
  });
}
