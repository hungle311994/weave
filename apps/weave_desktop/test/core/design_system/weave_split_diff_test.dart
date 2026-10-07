import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

Color? _background(WidgetTester tester, String text) => tester.widget<ColoredBox>(find.ancestor(of: find.text(text), matching: find.byType(ColoredBox)).first).color;

void main() {
  Future<void> pumpDiff(WidgetTester tester, {String? placeholder}) => pumpComponent(
    tester,
    SizedBox(
      width: 648,
      height: 400,
      child: WeaveSplitDiff(
        path: 'lib/screen/auth/login_screen.dart',
        additions: 2,
        deletions: 1,
        statusLabel: 'Modified',
        statusTone: WeaveTone.info,
        originalLineCount: 2,
        updatedLineCount: 3,
        placeholder: placeholder,
        rows: const <WeaveDiffRow>[
          WeaveDiffHunkRow('@@ -82,2 +82,3 @@ _LoginScreenState'),
          WeaveDiffLineRow(
            original: WeaveDiffCell(number: 82, text: 'Future<void> _submit() async {', kind: WeaveDiffLineKind.context),
            updated: WeaveDiffCell(number: 82, text: 'Future<void> _submit() async {', kind: WeaveDiffLineKind.context),
          ),
          WeaveDiffLineRow(
            original: WeaveDiffCell(number: 83, text: 'await login();', kind: WeaveDiffLineKind.removed),
            updated: WeaveDiffCell(number: 83, text: 'if (_busy) return;', kind: WeaveDiffLineKind.added),
          ),
          WeaveDiffLineRow(
            updated: WeaveDiffCell(number: 84, text: 'await login(retry: true);', kind: WeaveDiffLineKind.added),
          ),
        ],
      ),
    ),
  );

  testWidgets('shows the file header, column headers and counts from the design', (WidgetTester tester) async {
    await pumpDiff(tester);

    expect(find.text('lib/screen/auth/login_screen.dart'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('−1'), findsOneWidget);
    expect(find.widgetWithText(WeaveStatusPill, 'Modified'), findsOneWidget);
    expect(find.text('Before · 2 lines'), findsOneWidget);
    expect(find.text('After · 3 lines'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Original')).style?.color, WeaveColors.red);
    expect(tester.widget<Text>(find.text('Updated')).style?.color, WeaveColors.greenBright);
    expect(find.byWidgetPredicate((Widget widget) => widget is WeaveIcon && widget.icon == WeaveIcons.fileCode), findsOneWidget);
  });

  testWidgets('colours added, removed and missing lines and keeps both sides aligned', (WidgetTester tester) async {
    await pumpDiff(tester);

    expect(_background(tester, 'await login();'), WeaveColors.diffRemoved);
    expect(_background(tester, 'if (_busy) return;'), WeaveColors.diffAdded);
    expect(tester.getRect(find.text('await login();')).center.dy, tester.getRect(find.text('if (_busy) return;')).center.dy, reason: 'a removed line faces its replacement');
    expect(find.text('Future<void> _submit() async {'), findsNWidgets(2));

    final Rect added = tester.getRect(find.text('await login(retry: true);'));
    final Finder empty = find.byWidgetPredicate((Widget widget) => widget is ColoredBox && widget.color == WeaveColors.diffEmpty);
    expect(empty, findsOneWidget, reason: 'the original side has no line opposite an extra addition');
    expect(tester.getRect(empty).center.dy, added.center.dy);
    expect(tester.getSize(empty).height, WeaveLayout.diffLineHeight);
    expect(tester.widget<Text>(find.text('84')).style?.color, WeaveColors.greenDeep);
    expect(tester.widget<Text>(find.text('83').first).style?.color, WeaveColors.diffRemovedNumber);
    expect(tester.getRect(find.text('83').first).right, lessThanOrEqualTo(tester.getRect(find.byType(WeaveSplitDiff)).left + WeaveLayout.diffGutterWidth));
    expect(find.text('@@ -82,2 +82,3 @@ _LoginScreenState'), findsOneWidget);
  });

  testWidgets('shows a placeholder instead of rows, e.g. for a binary file', (WidgetTester tester) async {
    await pumpDiff(tester, placeholder: 'Binary file — no text changes to show.');

    expect(find.text('Binary file — no text changes to show.'), findsOneWidget);
    expect(find.text('await login();'), findsNothing);
  });
}
