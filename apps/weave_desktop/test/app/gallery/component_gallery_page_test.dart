import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/app/gallery/component_gallery_page.dart';
import 'package:weave/core/design_system/design_system.dart';

void main() {
  for (final Size size in <Size>[WeaveLayout.defaultWindow, WeaveLayout.minimumWindow]) {
    testWidgets('gallery renders without overflow at ${size.width.toInt()}×${size.height.toInt()}', (WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(theme: WeaveTheme.dark(), home: const ComponentGalleryPage()));
      await tester.pumpAndSettle();

      expect(find.text('Component gallery'), findsOneWidget);
      expect(find.byType(WeaveDialog), findsOneWidget);
      expect(find.byType(WeaveStepTimeline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
