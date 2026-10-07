import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';
import 'package:weave_agents/testing.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../../../helpers/app_test_harness.dart';

AgentPlanUsage _usage(int session, int week) => AgentPlanUsage(
  windows: <AgentPlanUsageWindow>[
    AgentPlanUsageWindow(label: 'Current session', percentUsed: session, resetsAt: 'Oct 7 at 8:10pm (Asia/Saigon)'),
    AgentPlanUsageWindow(label: 'Current week (all models)', percentUsed: week, resetsAt: 'Oct 10 at 6pm (Asia/Saigon)'),
  ],
  checkedAt: DateTime.now(),
);

String _plan(AgentRunRequest request, ScriptedAgentSession session) => 'done';

/// Reports plan usage but cannot read it.
final class _FailingUsageAdapter implements AgentAdapter {
  final ScriptedAgentAdapter _delegate = ScriptedAgentAdapter(id: 'flaky', displayName: 'Flaky Agent', handler: _plan);

  @override
  String get id => _delegate.id;

  @override
  String get displayName => _delegate.displayName;

  @override
  AgentAccount? get account => _delegate.account;

  @override
  bool get supportsAccounts => _delegate.supportsAccounts;

  @override
  Future<AgentAccountInfo?> readAccount() => _delegate.readAccount();

  @override
  bool get supportsMcp => _delegate.supportsMcp;

  @override
  bool get reportsPlanUsage => true;

  @override
  Future<AgentPlanUsage> readPlanUsage() async => throw const AgentPlanUsageException('Flaky Agent took too long to report its usage.');

  @override
  Future<AgentAvailability> checkAvailability() => _delegate.checkAvailability();

  @override
  Future<AgentExecution> start(AgentRunRequest request) => _delegate.start(request);
}

void main() {
  late AppTestHarness harness;

  setUp(() async {
    harness = AppTestHarness();
    await harness.initialize();
  });
  tearDown(() => harness.dispose());

  testWidgets('shows each ready agent plan usage and refreshes it on demand', (WidgetTester tester) async {
    final ScriptedAgentAdapter claudeLike = ScriptedAgentAdapter(id: 'solo', displayName: 'Solo Agent', handler: _plan, planUsage: _usage(28, 74));
    final ScriptedAgentAdapter plain = ScriptedAgentAdapter(id: 'plain', displayName: 'Plain Agent', handler: _plan);
    final DateTime reset = DateTime(2026, 10, 7, 19, 15);
    final ScriptedAgentAdapter exact = ScriptedAgentAdapter(
      id: 'exact',
      displayName: 'Exact Agent',
      handler: _plan,
      planUsage: AgentPlanUsage(
        windows: <AgentPlanUsageWindow>[AgentPlanUsageWindow(label: '5-hour limit', percentUsed: 100, resetTime: reset)],
        checkedAt: DateTime.now(),
      ),
    );
    final ScriptedAgentAdapter offline = ScriptedAgentAdapter(id: 'offline', displayName: 'Offline Agent', handler: _plan, isAvailable: false, planUsage: _usage(1, 1));
    harness.services = harness.servicesWith(<AgentAdapter>[claudeLike, plain, exact, offline, _FailingUsageAdapter()]);
    await harness.launch(tester);

    await tapReal(tester, find.byKey(const Key('sidebar-agents')));
    await pumpUntil(tester, () => find.byType(WeaveUsageMeter).evaluate().length == 3);
    expect(claudeLike.planUsageReads, 1, reason: 'read the first time the screen opens');
    final Finder solo = find.byKey(const Key('plan-usage-solo'));
    expect(find.descendant(of: solo, matching: find.text('Current session')), findsOneWidget);
    expect(find.descendant(of: solo, matching: find.text('28%')), findsOneWidget);
    expect(find.descendant(of: solo, matching: find.text('Resets Oct 10 at 6pm (Asia/Saigon)')), findsOneWidget);
    expect(find.textContaining('Checked at'), findsNothing, reason: 'no check time is shown');
    expect(find.descendant(of: find.byKey(const Key('plan-usage-plain')), matching: find.text('This agent does not report plan usage to Weave.')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('plan-usage-flaky')), matching: find.textContaining('took too long')), findsOneWidget);
    expect(find.byKey(const Key('plan-usage-offline')), findsNothing, reason: 'agents that are not ready show no usage');
    final Finder exactUsage = find.byKey(const Key('plan-usage-exact'));
    expect(
      find.descendant(of: exactUsage, matching: find.text('Resets Oct 7 at 7:15pm')),
      findsOneWidget,
      reason: 'an exact reset time is shown in local time',
    );
    expect(find.descendant(of: exactUsage, matching: find.text('100%')), findsOneWidget);
    expect(offline.planUsageReads, 0, reason: 'only ready agents are asked');

    // 1400 px window: three columns, cards in a row share their height.
    Rect card(String id) => tester.getRect(find.byKey(ValueKey<String>('agent-card-$id')));
    expect(<double>[card('plain').top, card('exact').top], everyElement(card('solo').top), reason: 'side by side');
    expect(card('plain').left, greaterThan(card('solo').right));
    expect(<double>[card('plain').height, card('exact').height], everyElement(card('solo').height));
    expect(card('offline').top, greaterThan(card('solo').bottom), reason: 'the fourth card starts the next row');

    tester.view.physicalSize = WeaveLayout.minimumWindow;
    await tester.pump();
    expect(card('plain').top, card('solo').top);
    expect(card('exact').top, greaterThan(card('solo').bottom), reason: 'a narrow window shows fewer columns');
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pump();

    claudeLike.planUsage = _usage(35, 80);
    await tapReal(tester, find.byKey(const Key('refresh-usage')));
    await pumpUntil(tester, () => find.descendant(of: solo, matching: find.text('35%')).evaluate().isNotEmpty);
    expect(claudeLike.planUsageReads, 2);
    expect(find.descendant(of: solo, matching: find.text('80%')), findsOneWidget);

    // Leaving and reopening the screen keeps the last values; only Refresh
    // usage reads them again.
    claudeLike.planUsage = _usage(40, 82);
    await tapReal(tester, find.byKey(const Key('sidebar-home')));
    await tester.pump(const Duration(milliseconds: 300));
    await tapReal(tester, find.byKey(const Key('sidebar-agents')));
    await pumpUntil(tester, () => find.byKey(const Key('plan-usage-solo')).evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    expect(claudeLike.planUsageReads, 2, reason: 'no automatic read on a later visit');
    expect(find.descendant(of: find.byKey(const Key('plan-usage-solo')), matching: find.text('35%')), findsOneWidget);
  });

  testWidgets('adds a custom agent to agents.json and removes it again', (WidgetTester tester) async {
    await harness.launch(tester);
    await tapReal(tester, find.byKey(const Key('sidebar-agents')));
    await pumpUntil(tester, () => find.byKey(const Key('add-agent')).evaluate().isNotEmpty);

    await tapReal(tester, find.byKey(const Key('add-agent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('agent-name')), 'Gemini CLI');
    expect(
      tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('agent-id')), matching: find.byType(EditableText))).controller.text,
      'gemini-cli',
      reason: 'the ID follows the name',
    );
    await tester.enterText(find.byKey(const Key('agent-executable')), 'gemini-weave-test');
    await tapReal(tester, find.byKey(const Key('save-agent')));
    await pumpUntil(tester, () => find.byKey(const ValueKey<String>('agent-card-gemini-cli')).evaluate().isNotEmpty);

    final String file = File(agentsFilePath(harness.paths)).readAsStringSync();
    expect(file, allOf(contains('"id": "gemini-cli"'), contains('"executable": "gemini-weave-test"')));
    await pumpUntil(tester, () => find.descendant(of: find.byKey(const ValueKey<String>('agent-card-gemini-cli')), matching: find.text('Not installed')).evaluate().isNotEmpty);

    await tester.ensureVisible(find.byKey(const Key('remove-agent-gemini-cli')));
    await tapReal(tester, find.byKey(const Key('remove-agent-gemini-cli')));
    await pumpUntil(tester, () => find.byKey(const Key('confirm-remove-agent')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('confirm-remove-agent')));
    await pumpUntil(tester, () => find.byKey(const ValueKey<String>('agent-card-gemini-cli')).evaluate().isEmpty);
    expect(File(agentsFilePath(harness.paths)).readAsStringSync(), isNot(contains('gemini-cli')));
  });

  testWidgets('rejects an agent without a command, keeping the dialog open', (WidgetTester tester) async {
    await harness.launch(tester);
    await tapReal(tester, find.byKey(const Key('sidebar-agents')));
    await pumpUntil(tester, () => find.byKey(const Key('add-agent')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('add-agent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('agent-name')), 'Broken');
    await tester.tap(find.byKey(const Key('save-agent')));
    await tester.pump();

    expect(find.byKey(const Key('agent-error')), findsOneWidget);
    expect(find.byKey(const Key('agent-name')), findsOneWidget, reason: 'the form stays open');
  });

  testWidgets('re-checks sign-in on every visit and when the user comes back to Weave, without re-reading plan usage', (WidgetTester tester) async {
    final ScriptedAgentAdapter agent = ScriptedAgentAdapter(id: 'solo', displayName: 'Solo Agent', handler: _plan, planUsage: _usage(10, 20));
    harness.services = harness.servicesWith(<AgentAdapter>[agent]);
    await harness.launch(tester);
    final int atLaunch = agent.availabilityChecks;
    await tapReal(tester, find.byKey(const Key('sidebar-agents')));
    await pumpUntil(tester, () => find.byType(WeaveUsageMeter).evaluate().isNotEmpty && agent.availabilityChecks > atLaunch);
    expect(find.byKey(const Key('check-all-connections')), findsNothing, reason: 'no manual check button');
    expect(find.text('Checked on this Mac each time you open this screen or come back to Weave.'), findsOneWidget);
    final int checks = agent.availabilityChecks;
    final int reads = agent.planUsageReads;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpUntil(tester, () => agent.availabilityChecks > checks);
    expect(agent.planUsageReads, reads, reason: 'usage only refreshes through Refresh usage');
  });

  testWidgets('Add agent lists well-known agents; Add saves one to agents.json, and it shows as Added next time', (WidgetTester tester) async {
    await harness.launch(tester);
    await tapReal(tester, find.byKey(const Key('sidebar-agents')));
    await pumpUntil(tester, () => find.byKey(const Key('add-agent')).evaluate().isNotEmpty);

    await tapReal(tester, find.byKey(const Key('add-agent')));
    await pumpUntil(tester, () => find.byKey(const ValueKey<String>('gallery-gemini')).evaluate().isNotEmpty && tester.widget<WeaveStatusPill>(find.byKey(const Key('gallery-status-gemini'))).label != 'Checking…');
    for (final AgentCatalogEntry entry in agentCatalog) {
      expect(find.byKey(ValueKey<String>('gallery-${entry.definition.id}')), findsOneWidget);
      expect(find.text(entry.definition.displayName), findsOneWidget);
    }
    expect(<String>['Installed', 'Not installed'], contains(tester.widget<WeaveStatusPill>(find.byKey(const Key('gallery-status-gemini'))).label), reason: 'checked on this Mac');
    expect(find.descendant(of: find.byKey(const ValueKey<String>('gallery-copilot')), matching: find.byType(BrandIcon)), findsOneWidget);

    await tapReal(tester, find.byKey(const Key('gallery-add-gemini')));
    await pumpUntil(tester, () => find.byKey(const ValueKey<String>('agent-card-gemini')).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey<String>('gallery-gemini')), findsNothing, reason: 'the gallery closed');
    expect(File(agentsFilePath(harness.paths)).readAsStringSync(), allOf(contains('"id": "gemini"'), contains('"plan"')));

    await tapReal(tester, find.byKey(const Key('add-agent')));
    await pumpUntil(tester, () => find.byKey(const Key('gallery-added-gemini')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('gallery-add-gemini')), findsNothing);
    expect(find.byKey(const Key('gallery-add-copilot')), findsOneWidget);
  });
}
