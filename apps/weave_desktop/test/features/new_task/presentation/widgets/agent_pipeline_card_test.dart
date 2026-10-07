import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';
import 'package:weave/features/new_task/presentation/widgets/agent_pipeline_card.dart';
import 'package:weave_agents/testing.dart';

import '../../../../helpers/design_system_harness.dart';

void main() {
  testWidgets('number and role line up whether or not a card shows its remove button', (WidgetTester tester) async {
    final ScriptedAgentAdapter agent = ScriptedAgentAdapter(id: 'solo', displayName: 'Solo Agent', handler: (_, _) => '');
    await pumpComponent(
      tester,
      SizedBox(
        width: 800,
        child: Row(
          children: <Widget>[
            Expanded(
              child: AgentPipelineCard(number: 1, roleLabel: 'Plan', agent: null, model: null, available: false, onTap: () {}),
            ),
            const SizedBox(width: WeaveSpacing.s16),
            Expanded(
              child: AgentPipelineCard(number: 2, roleLabel: 'Implement', agent: agent, model: null, available: true, onTap: () {}, onClear: () {}),
            ),
          ],
        ),
      ),
    );

    expect(find.byTooltip('Remove Implement agent'), findsOneWidget);
    expect(tester.getCenter(find.text('2')).dy, tester.getCenter(find.text('1')).dy);
    expect(tester.getCenter(find.text('Implement')).dy, tester.getCenter(find.text('Plan')).dy);
    expect(tester.getTopLeft(find.text('Implement')).dx - tester.getTopLeft(find.byType(AgentPipelineCard).last).dx, tester.getTopLeft(find.text('Plan')).dx - tester.getTopLeft(find.byType(AgentPipelineCard).first).dx);
  });
}
