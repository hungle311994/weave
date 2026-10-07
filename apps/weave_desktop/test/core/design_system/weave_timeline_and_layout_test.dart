import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

import '../../helpers/design_system_harness.dart';

void main() {
  testWidgets('timeline renders exact markers, connectors, type and every status', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      SizedBox(
        width: 500,
        child: WeaveStepTimeline(
          steps: <WeaveStep>[
            const WeaveStep(title: 'Plan', subtitle: 'Completed', status: WeaveStepStatus.done),
            WeaveStep(
              title: 'Implement',
              subtitle: 'Running',
              status: WeaveStepStatus.active,
              child: WeaveCard(
                surface: WeaveSurface.sunken,
                child: Text('Live output', style: WeaveTypography.code),
              ),
            ),
            const WeaveStep(title: 'Verify', subtitle: 'Queued', status: WeaveStepStatus.pending),
            const WeaveStep(title: 'Review', subtitle: 'Stopped', status: WeaveStepStatus.failed),
          ],
        ),
      ),
    );
    final List<DecoratedBox> markers = tester
        .widgetList<DecoratedBox>(find.descendant(of: find.byType(WeaveStepTimeline), matching: find.byType(DecoratedBox)))
        .where((DecoratedBox box) {
          final BoxDecoration? decoration = box.decoration is BoxDecoration ? box.decoration as BoxDecoration : null;
          return decoration?.shape == BoxShape.circle && decoration?.border != null;
        })
        .toList(growable: false);
    expect(markers, hasLength(4));
    final BoxDecoration active = markers[1].decoration as BoxDecoration;
    expect(active.color, WeaveColors.stepActive);
    expect((active.border! as Border).top.color, WeaveColors.green);
    expect((active.border! as Border).top.width, WeaveLayout.timelineStrokeWidth);
    expect(tester.getSize(find.byType(WeaveIcon).first), const Size.square(WeaveIconSize.compact));
    expect(tester.widget<Text>(find.text('Implement')).style, WeaveTypography.titleSmall);
    expect(tester.widget<Text>(find.text('Running')).style?.fontSize, WeaveTypography.caption.fontSize);
    expect(find.bySemanticsLabel('Step 2: Implement, active'), findsOneWidget);
    final Iterable<Container> connectors = tester.widgetList<Container>(find.descendant(of: find.byType(WeaveStepTimeline), matching: find.byType(Container))).where((Container container) => container.color == WeaveColors.border && container.constraints?.minWidth == WeaveLayout.timelineStrokeWidth);
    expect(connectors, hasLength(3));
  });

  testWidgets('breadcrumb uses medium 12 tertiary text and page header maps title and subtitle type', (WidgetTester tester) async {
    await pumpComponent(
      tester,
      const SizedBox(
        width: 800,
        child: WeavePageHeader(
          breadcrumb: <String>['Workspace', 'New task'],
          title: 'What should Weave build?',
          subtitle: 'Describe your task.',
          trailing: WeaveStatusPill(label: 'Ready', tone: WeaveTone.success),
        ),
      ),
    );
    final Text breadcrumb = tester.widget<Text>(find.text('Workspace'));
    expect(breadcrumb.style?.fontSize, 12);
    expect(breadcrumb.style?.fontWeight, FontWeight.w500);
    expect(breadcrumb.style?.color, WeaveColors.textTertiary);
    expect(tester.widget<Text>(find.text('What should Weave build?')).style, WeaveTypography.display);
    expect(tester.widget<Text>(find.text('Describe your task.')).style, WeaveTypography.bodyLarge);
    expect(find.bySemanticsLabel('Breadcrumb: Workspace, New task'), findsOneWidget);
  });
}
