import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';
import 'package:weave_agents/weave_agents.dart';

import '../../../helpers/app_test_harness.dart';

void main() {
  late AppTestHarness harness;

  setUp(() async {
    harness = AppTestHarness();
    await harness.initialize();
  });
  tearDown(() => harness.dispose());

  testWidgets('continues locally after finding a ready agent', (WidgetTester tester) async {
    await harness.launch(tester, onboardingComplete: false);

    expect(find.text('Welcome to Weave'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-logo')), findsOneWidget);
    expect(find.text('W'), findsNothing);
    expect(find.textContaining('does not store agent passwords'), findsOneWidget);
    expect(find.textContaining('Cloud sign-in'), findsOneWidget);

    await tester.tap(find.byKey(const Key('continue-locally')));
    await tester.pump();

    expect(find.text('Set up an AI agent'), findsOneWidget);
    expect(find.text('Solo Agent'), findsOneWidget);
    expect(find.text('Offline Agent'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Needs setup'), findsOneWidget);

    await tapReal(tester, find.byKey(const Key('finish-onboarding')));
    await pumpUntil(tester, () => find.text('Start workflow').evaluate().isNotEmpty);

    expect(find.text('What should Weave build?'), findsOneWidget);
  });

  testWidgets('blocks setup completion when no agent is ready', (WidgetTester tester) async {
    harness.services = harness.servicesWith(<AgentAdapter>[]);
    await harness.launch(tester, onboardingComplete: false);

    await tester.tap(find.byKey(const Key('continue-locally')));
    await tester.pump();

    expect(find.text('No configured agents were found. Add an agent definition, then scan again.'), findsOneWidget);
    expect(find.text('Set up at least one agent before continuing.'), findsOneWidget);
    expect(tester.widget<WeaveButton>(find.byKey(const Key('finish-onboarding'))).onPressed, isNull);
  });

  testWidgets('shows and copies provider-neutral install guidance for a missing CLI', (WidgetTester tester) async {
    const String command = 'brew install missing-test-agent';
    final AgentDefinition definition = AgentDefinition.fromJson(<String, Object?>{
      'id': 'missing-test-agent',
      'displayName': 'Missing Test Agent',
      'executable': 'weave-missing-test-agent',
      'sandboxArguments': <String, Object?>{'readOnly': <String>[], 'workspaceWrite': <String>[]},
      'installCommand': <String>['brew', 'install', 'missing-test-agent'],
    });
    harness.services = harness.servicesWith(<AgentAdapter>[
      CommandAgentAdapter(definition, environment: const <String, String>{'PATH': '/nonexistent', 'HOME': '/nonexistent'}),
    ]);
    await harness.launch(tester, onboardingComplete: false);

    await tester.tap(find.byKey(const Key('continue-locally')));
    await pumpUntil(tester, () => find.byKey(const Key('copy-install-missing-test-agent')).evaluate().isNotEmpty);

    expect(find.text('Not installed'), findsOneWidget);
    expect(find.text('Install in Terminal: $command'), findsOneWidget);
    expect(find.text('Copy install'), findsNothing);
    expect(find.byTooltip('Copy install command'), findsOneWidget);
    final Finder card = find.byKey(const Key('onboarding-agent-missing-test-agent'));
    final Rect cardRect = tester.getRect(card);
    final Rect statusRect = tester.getRect(find.descendant(of: card, matching: find.byType(WeaveStatusPill)));
    final Rect leadingIconRect = tester.getRect(find.descendant(of: card, matching: find.byType(WeaveIcon)).first);
    expect(statusRect.top, cardRect.top + WeaveSpacing.s16);
    expect(leadingIconRect.top, cardRect.top + WeaveSpacing.s20);
    await tapReal(tester, find.byKey(const Key('copy-install-missing-test-agent')));
    await pumpUntil(tester, () => find.text('Install command copied. Run it in Terminal, then scan again.').evaluate().isNotEmpty);
  });
}
