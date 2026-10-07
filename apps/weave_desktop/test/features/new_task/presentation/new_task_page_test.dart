import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:weave/core/design_system/design_system.dart';
import 'package:weave_agents/testing.dart';
import 'package:weave_agents/weave_agents.dart';

import '../../../helpers/app_test_harness.dart';

void main() {
  late AppTestHarness harness;

  setUp(() async {
    harness = AppTestHarness();
    await harness.initialize();
  });
  tearDown(() => harness.dispose());

  testWidgets('starts a workflow from the form and follows it to completion', (WidgetTester tester) async {
    await harness.launch(tester);

    await harness.chooseRepository(tester, harness.repository.path);
    await harness.chooseAgents(tester);
    expect(find.text('Solo Agent'), findsNWidgets(3));

    await tester.enterText(find.byKey(const Key('request')), 'Add notes');
    await tapReal(tester, find.byKey(const Key('start')));
    await pumpUntil(tester, () => find.byKey(const Key('advanced-save')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('advanced-save')));
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);

    expect(find.text('Add notes'), findsWidgets);
    expect(File(path.join(harness.repository.path, 'notes.txt')).existsSync(), isTrue);
    expect(find.text('No workflows yet.'), findsNothing);
  });

  testWidgets('reports a directory that is not a repository', (WidgetTester tester) async {
    await harness.launch(tester);

    await tapReal(tester, find.byKey(const Key('repository-add')));
    await tester.pumpAndSettle();
    harness.picker.nextDirectory = harness.temporaryDirectory.path;
    await tapReal(tester, find.byKey(const Key('repository-browse')));
    await pumpUntil(tester, () => find.textContaining('not inside a Git repository').evaluate().isNotEmpty);

    expect(find.byType(WeaveDialog), findsOneWidget, reason: 'an invalid folder stays in the picker');
    await tester.tap(find.byTooltip('Close dialog'));
    await tester.pumpAndSettle();
    await tapReal(tester, find.byKey(const Key('start')));
    await pumpUntil(tester, () => find.text('Add the repository this task works on.').evaluate().isNotEmpty);
  });

  testWidgets('offers an MCP server when the request links to Figma', (WidgetTester tester) async {
    final ScriptedAgentAdapter agent = harness.solo();
    harness.services = harness.servicesWith(<AgentAdapter>[agent]);
    await harness.launch(tester);

    await harness.startFromForm(tester, 'Build https://www.figma.com/design/AbC123/Login');
    await pumpUntil(tester, () => find.text('Use an MCP server?').evaluate().isNotEmpty);
    expect(find.byKey(const Key('suggest-figma')), findsOneWidget);
    expect(find.byKey(const Key('suggest-figma-desktop')), findsOneWidget);

    await tester.tap(find.byKey(const Key('suggest-figma-desktop')));
    await tester.pump();
    await tapReal(tester, find.byKey(const Key('mcp-enable')));
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);

    expect(agent.requests.map((AgentRunRequest request) => request.mcpServers.single.id).toSet(), <String>{'figma-desktop'});
    expect(find.text('MCP: Figma (desktop app)'), findsOneWidget);
  });

  testWidgets('offers an MCP server when the request explicitly names it', (WidgetTester tester) async {
    await harness.launch(tester);

    await harness.startFromForm(tester, 'Add the Figma MCP to this workflow');
    await pumpUntil(tester, () => find.text('Use an MCP server?').evaluate().isNotEmpty);

    expect(find.byKey(const Key('suggest-figma')), findsOneWidget);
    expect(find.byKey(const Key('suggest-figma-desktop')), findsOneWidget);
    expect(find.byKey(const Key('mcp-enable')), findsOneWidget);
    expect(find.byKey(const Key('mcp-skip')), findsOneWidget);
  });

  testWidgets('centres the top-aligned form while keeping its breadcrumb at the top left', (WidgetTester tester) async {
    await harness.launch(tester, size: WeaveLayout.defaultWindow);
    Rect rectOf(String key) => tester.getRect(find.byKey(Key(key)));

    expect(find.text('What should Weave build?'), findsOneWidget);
    expect(find.text('Workflow preview'), findsNothing);
    expect(find.textContaining('10,000'), findsNothing, reason: 'the task description has no length limit');
    expect(rectOf('agent-implementer').top, rectOf('agent-planner').top, reason: 'pipeline cards in one row');
    expect(tester.takeException(), isNull);

    for (final Size size in <Size>[const Size(2560, 1440), const Size(1512, 982)]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'no overflow at $size');
      final Rect page = tester.getRect(find.byKey(const Key('new-task-main')));
      final Rect content = tester.getRect(find.byKey(const Key('new-task-content')));
      final Rect breadcrumb = tester.getRect(find.byKey(const Key('new-task-breadcrumb')));
      final double availableLeft = page.left + WeaveLayout.pageGutter;
      final double availableRight = page.right - WeaveSpacing.s28;
      expect((content.left - availableLeft - (availableRight - content.right)).abs(), lessThan(1), reason: 'the form is horizontally centred at $size');
      expect((breadcrumb.left - availableLeft).abs(), lessThan(1), reason: 'the breadcrumb stays at the page gutter at $size');
      expect(content.top, lessThan(rectOf('request').top), reason: 'the centred content remains top-aligned');
      expect(tester.getSize(find.byKey(const Key('request'))).width, lessThanOrEqualTo(WeaveLayout.newTaskFormWidth));
    }

    tester.view.physicalSize = WeaveLayout.minimumWindow;
    await tester.pump();
    expect(rectOf('agent-implementer').top, rectOf('agent-planner').top, reason: 'the narrower icon rail leaves room for one pipeline row');
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens repository and agent dialogs, then settings when starting', (WidgetTester tester) async {
    await harness.launch(tester, size: WeaveLayout.defaultWindow);

    await tester.tap(find.byKey(const Key('repository-add')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(WeaveDialog)), const Size(WeaveLayout.dialogWidth, WeaveLayout.dialogHeight));
    expect(find.text('Use a Git repository already cloned on this Mac.'), findsOneWidget);
    expect(find.byKey(const Key('repository-browse')), findsOneWidget, reason: 'one target to click or drop on');
    expect(
      find.descendant(of: find.byType(WeaveDialog), matching: find.byType(TextField)),
      findsNothing,
      reason: 'no path to type in local mode',
    );
    await tester.tap(find.byTooltip('Close dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('agent-planner')));
    await tester.pumpAndSettle();
    expect(find.text('Solo Agent'), findsOneWidget);
    expect(find.text('Offline Agent'), findsOneWidget);
    await tester.tap(find.byTooltip('Close dialog'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('advanced')), findsNothing, reason: 'advanced settings are not shown before start');
    await harness.chooseRepository(tester, harness.repository.path);
    await harness.chooseAgents(tester);
    await tester.enterText(find.byKey(const Key('request')), 'Add notes');
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tapReal(tester, find.byKey(const Key('start')));
    await pumpUntil(tester, () => find.text('Advanced workflow settings').evaluate().isNotEmpty);
    expect(find.text('Advanced workflow settings'), findsOneWidget);
    expect(find.byKey(const Key('approve-plan')), findsOneWidget);
    expect(tester.widget<WeaveButton>(find.byKey(const Key('advanced-save'))).label, 'Start workflow');
  });

  testWidgets('keeps the New Task draft when navigating away and back', (WidgetTester tester) async {
    await harness.launch(tester);
    await harness.chooseRepository(tester, harness.repository.path);
    await harness.chooseAgents(tester);
    await tester.enterText(find.byKey(const Key('request')), 'Keep this draft');

    await tapReal(tester, find.byKey(const Key('sidebar-agents')));
    await pumpUntil(tester, () => find.byKey(const ValueKey<String>('agent-card-solo')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('sidebar-home')));
    await pumpUntil(tester, () => find.byKey(const Key('request')).evaluate().isNotEmpty);

    final TextField request = tester.widget<TextField>(find.descendant(of: find.byKey(const Key('request')), matching: find.byType(TextField)));
    expect(request.controller?.text, 'Keep this draft');
    expect(find.text('Solo Agent'), findsNWidgets(3));
    expect(find.byKey(ValueKey<String>('repository-${harness.repository.resolveSymbolicLinksSync()}')), findsOneWidget);
  });

  testWidgets('removes a selected agent and highlights its role on validation', (WidgetTester tester) async {
    await harness.launch(tester);
    await harness.chooseRepository(tester, harness.repository.path);
    await harness.chooseAgents(tester);
    await tester.enterText(find.byKey(const Key('request')), 'Validate agents');

    final Finder plannerCard = find.byKey(const Key('agent-planner'));
    final Finder removeButton = find.byKey(const Key('clear-agent-plan'));
    final Finder readyPill = find.descendant(of: plannerCard, matching: find.text('Ready'));
    expect(tester.getRect(removeButton).center.dx, greaterThan(tester.getRect(readyPill).center.dx), reason: 'the remove action is the right-most control');
    expect(tester.getSize(removeButton).height, WeaveLayout.statusPillHeight, reason: 'remove and status controls use the same height');
    expect(tester.getSize(find.ancestor(of: readyPill, matching: find.byType(WeaveStatusPill))).height, WeaveLayout.compactStatusPillHeight);
    expect(tester.getRect(readyPill).center.dy, greaterThan(tester.getRect(removeButton).center.dy), reason: 'compact status moves to the agent metadata row so the title keeps the first row');
    expect(find.descendant(of: find.byKey(const Key('agent-implementer')), matching: find.text('Implement')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('agent-reviewer')), matching: find.text('Review & test')), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Plan agent'));
    await tester.pump();
    expect(find.text('Select agent'), findsOneWidget);

    await tapReal(tester, find.byKey(const Key('start')));
    await tester.pump();
    expect(find.text('Choose an agent for Plan.'), findsOneWidget, reason: 'errors are toasts');
    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('adding a repository never chooses agents; starting without them explains it in a toast', (WidgetTester tester) async {
    await harness.launch(tester);
    await harness.chooseRepository(tester, harness.repository.path);

    expect(find.byKey(const Key('repository-change')), findsNothing, reason: 'no repository is singled out');
    expect(find.text('Select agent'), findsNWidgets(3));
    await tester.enterText(find.byKey(const Key('request')), 'Add notes');
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tapReal(tester, find.byKey(const Key('start')));
    await tester.pump();

    expect(find.text('Choose an agent for Plan, Implement, Review & test.'), findsOneWidget);
    expect(find.text('Required'), findsNWidgets(3));
  });

  testWidgets('repositories are peers: add several, reject a duplicate, remove any', (WidgetTester tester) async {
    final Directory second = Directory(path.join(harness.temporaryDirectory.path, 'second'))..createSync();
    await tester.runAsync(() => Process.run('git', <String>['init', '--quiet', '--initial-branch=main'], workingDirectory: second.path));
    await harness.launch(tester);
    await harness.chooseRepository(tester, harness.repository.path);
    await harness.chooseRepository(tester, second.path);
    final Finder first = find.byKey(ValueKey<String>('repository-${harness.repository.resolveSymbolicLinksSync()}'));
    final Finder other = find.byKey(ValueKey<String>('repository-${second.resolveSymbolicLinksSync()}'));
    expect(first, findsOneWidget);
    expect(other, findsOneWidget);

    await harness.chooseRepository(tester, second.path);
    expect(find.text('second is already part of this task.'), findsOneWidget, reason: 'a toast, not text above Start');

    await tester.tap(find.byKey(ValueKey<String>('remove-repository-${harness.repository.resolveSymbolicLinksSync()}')));
    await tester.pump();
    expect(first, findsNothing, reason: 'the first repository can be removed like any other');
    expect(other, findsOneWidget);
  });
}
