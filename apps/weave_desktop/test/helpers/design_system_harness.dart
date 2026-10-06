import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

/// Pumps [child] centred in a dark Weave-themed app.
Future<void> pumpComponent(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: WeaveTheme.dark(),
    home: Scaffold(body: Center(child: child)),
  ),
);

/// The [BoxDecoration] of the nearest decorated box around [finder].
BoxDecoration decorationAround(WidgetTester tester, Finder finder) {
  final Finder decorated = find.ancestor(of: finder, matching: find.byWidgetPredicate((Widget widget) => (widget is DecoratedBox && widget.decoration is BoxDecoration) || (widget is Container && widget.decoration is BoxDecoration)));
  final Widget widget = tester.widget(decorated.first);
  return (widget is DecoratedBox ? widget.decoration : (widget as Container).decoration)! as BoxDecoration;
}
