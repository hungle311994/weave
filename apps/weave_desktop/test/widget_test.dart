import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:weave/src/weave_app.dart';
import 'package:weave/src/weave_controller.dart';
import 'package:weave_agents/testing.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

/// Lets real file and process I/O finish, then rebuilds, until [condition].
Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {Duration timeout = const Duration(seconds: 15)}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      final List<String> texts = <String>[for (final Element element in find.byType(Text).evaluate()) (element.widget as Text).data ?? ''];
      fail('Timed out waiting for the UI to update. Visible text: $texts');
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    // Advance fake time too, so animations such as tab changes progress.
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Taps [finder] in the real zone, so the process and file I/O it starts can
/// finish; FakeAsync would otherwise hold their callbacks.
Future<void> tapReal(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() => tester.tap(finder));
  await tester.pump();
}

void main() {
  late Directory temporaryDirectory;
  late Directory repository;
  late WeaveStoragePaths paths;
  late WeaveServices services;

  String writeNotes(AgentRunRequest request, ScriptedAgentSession session) {
    File(path.join(request.workingDirectory, 'notes.txt')).writeAsStringSync('notes\n');
    session.write('wrote notes.txt\n');
    return 'Added notes.txt';
  }

  ScriptedAgentAdapter solo({ScriptedAgentHandler? implement}) => ScriptedAgentAdapter(
    id: 'solo',
    displayName: 'Solo Agent',
    handler: (AgentRunRequest request, ScriptedAgentSession session) async => switch (request.role) {
      AgentRole.planner => 'Plan: add notes.txt',
      AgentRole.implementer => await (implement ?? writeNotes)(request, session),
      AgentRole.reviewer => 'VERDICT: APPROVED',
    },
  );

  WeaveServices servicesWith(List<AgentAdapter> agents) => WeaveServices(paths: paths, agents: AgentRegistry(agents), environment: Platform.environment);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-desktop-test-');
    repository = await Directory(path.join(temporaryDirectory.path, 'repo')).create();
    await Process.run('git', <String>['init', '--quiet', '--initial-branch=main'], workingDirectory: repository.path);
    paths = WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: <String, String>{'WEAVE_HOME': path.join(temporaryDirectory.path, 'home')});
    services = servicesWith(<AgentAdapter>[
      solo(),
      ScriptedAgentAdapter(id: 'offline', displayName: 'Offline Agent', isAvailable: false, handler: (AgentRunRequest request, ScriptedAgentSession session) => ''),
    ]);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(WeaveApp(createController: () async => WeaveController(services)));
    await pumpUntil(tester, () => find.text('New workflow').evaluate().length >= 2);
  }

  testWidgets('shows the form, the agents, and an empty workflow list', (WidgetTester tester) async {
    await launch(tester);

    expect(find.text('No workflows yet.'), findsOneWidget);
    expect(find.text('Start workflow'), findsOneWidget);

    await tapReal(tester, find.text('Agents'));
    await pumpUntil(tester, () => find.text('Solo Agent  (solo)').evaluate().isNotEmpty);

    expect(find.text('Offline Agent  (offline)'), findsOneWidget);
    expect(find.textContaining('offline is not available.'), findsOneWidget);
    expect(find.textContaining('agents.json'), findsOneWidget);
  });

  testWidgets('starts a workflow from the form and follows it to completion', (WidgetTester tester) async {
    await launch(tester);

    await tester.enterText(find.byKey(const Key('repository')), repository.path);
    await tapReal(tester, find.text('Load'));
    await pumpUntil(tester, () => find.text('Git repository loaded').evaluate().isNotEmpty);
    expect(find.text('Solo Agent'), findsNWidgets(3));

    await tester.enterText(find.byKey(const Key('request')), 'Add notes');
    await tapReal(tester, find.byKey(const Key('start')));
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);

    expect(find.text('Add notes'), findsWidgets);
    expect(File(path.join(repository.path, 'notes.txt')).existsSync(), isTrue);
    expect(find.text('No workflows yet.'), findsNothing);
  });

  testWidgets('reports a directory that is not a repository', (WidgetTester tester) async {
    await launch(tester);

    await tester.enterText(find.byKey(const Key('repository')), temporaryDirectory.path);
    await tapReal(tester, find.text('Load'));
    await pumpUntil(tester, () => find.textContaining('not inside a Git repository').evaluate().isNotEmpty);

    await tapReal(tester, find.byKey(const Key('start')));
    await pumpUntil(tester, () => find.textContaining('not inside a Git repository').evaluate().isNotEmpty);
    expect(find.text('No workflows yet.'), findsOneWidget);
  });

  /// Loads the test repository and starts [request] from the form.
  Future<void> startFromForm(WidgetTester tester, String request) async {
    await tester.enterText(find.byKey(const Key('repository')), repository.path);
    await tapReal(tester, find.text('Load'));
    await pumpUntil(tester, () => find.text('Git repository loaded').evaluate().isNotEmpty);
    await tester.enterText(find.byKey(const Key('request')), request);
    await tapReal(tester, find.byKey(const Key('start')));
  }

  testWidgets('shows live activity, answers approvals, and displays artifacts and changes', (WidgetTester tester) async {
    services = servicesWith(<AgentAdapter>[
      solo(
        implement: (AgentRunRequest request, ScriptedAgentSession session) async {
          if (request.resumeSessionId == null) {
            final ApprovalDecision decision = await session.requestApproval(action: 'network', details: 'Download a package');
            session.write('decision: ${decision.name}\n');
          }
          return writeNotes(request, session);
        },
      ),
    ]);
    await launch(tester);

    await startFromForm(tester, 'Add notes');
    await pumpUntil(tester, () => find.byKey(const Key('approve')).evaluate().isNotEmpty);
    expect(find.textContaining('implementer asks to: network'), findsOneWidget);

    await tapReal(tester, find.byKey(const Key('approve')));
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);
    expect(find.byKey(const Key('approve')), findsNothing);
    expect(find.textContaining('decision: approve'), findsOneWidget);
    expect(find.textContaining('wrote notes.txt'), findsWidgets);
    expect(find.text('implementer: Solo Agent'), findsOneWidget);

    await tester.tap(find.text('Plan').last);
    await pumpUntil(tester, () => find.text('Plan: add notes.txt').evaluate().isNotEmpty);

    await tester.tap(find.text('Review').last);
    await pumpUntil(tester, () => find.text('VERDICT: APPROVED').evaluate().isNotEmpty);

    await tester.tap(find.text('Changes'));
    await tester.pumpAndSettle();
    await tapReal(tester, find.byKey(const Key('show-changes')));
    await pumpUntil(tester, () => find.text('+notes').evaluate().isNotEmpty);
    expect(find.textContaining('notes.txt'), findsWidgets);
  });

  testWidgets('cancels a running workflow', (WidgetTester tester) async {
    services = servicesWith(<AgentAdapter>[
      solo(
        implement: (AgentRunRequest request, ScriptedAgentSession session) async {
          await Completer<void>().future;
          return 'never';
        },
      ),
    ]);
    await launch(tester);

    await startFromForm(tester, 'Add notes');
    await pumpUntil(tester, () => find.byKey(const Key('cancel')).evaluate().isNotEmpty && find.text('Implementing').evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('cancel')));

    await pumpUntil(tester, () => find.text('Cancelled').evaluate().isNotEmpty);
    expect(find.byKey(const Key('cancel')), findsNothing);
    expect(find.textContaining('Cancelled by user.'), findsWidgets);
  });

  testWidgets('offers an MCP server when the request links to Figma', (WidgetTester tester) async {
    final ScriptedAgentAdapter agent = solo();
    services = servicesWith(<AgentAdapter>[agent]);
    await launch(tester);

    await startFromForm(tester, 'Build https://www.figma.com/design/AbC123/Login');
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

  testWidgets('adds and removes a custom MCP server', (WidgetTester tester) async {
    await launch(tester);

    await tester.tap(find.widgetWithText(ListTile, 'MCP servers'));
    await tester.pumpAndSettle();
    expect(find.text('Figma  (figma)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-mcp')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('mcp-id')), 'tracker');
    await tester.enterText(find.byKey(const Key('mcp-endpoint')), 'ftp://wrong');
    await tester.tap(find.byKey(const Key('save-mcp')));
    await tester.pump();
    expect(find.textContaining('http or https'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('mcp-endpoint')), 'https://tracker.example.com/mcp');
    await tapReal(tester, find.byKey(const Key('save-mcp')));
    await pumpUntil(tester, () => find.text('tracker  (tracker)').evaluate().isNotEmpty && find.byTooltip('Remove').evaluate().isNotEmpty);
    expect(File(mcpFilePath(paths)).readAsStringSync(), contains('https://tracker.example.com/mcp'));

    await tapReal(tester, find.byTooltip('Remove'));
    await pumpUntil(tester, () => find.text('tracker  (tracker)').evaluate().isEmpty);
    expect(services.mcp['tracker'], isNull);
  });

  testWidgets('commits a completed workflow after approval', (WidgetTester tester) async {
    for (final List<String> setting in <List<String>>[
      <String>['user.name', 'Weave Test'],
      <String>['user.email', 'weave@example.com'],
      <String>['commit.gpgsign', 'false'],
      <String>['core.hooksPath', '/dev/null'],
    ]) {
      // Real processes only complete outside the widget test's fake zone.
      await tester.runAsync(() => Process.run('git', <String>['config', ...setting], workingDirectory: repository.path));
    }
    await launch(tester);
    await startFromForm(tester, 'Add notes');
    await pumpUntil(tester, () => find.byKey(const Key('commit')).evaluate().isNotEmpty);

    await tester.tap(find.byKey(const Key('commit')));
    await pumpUntil(tester, () => find.byKey(const Key('commit-message')).evaluate().isNotEmpty);
    expect(find.textContaining('Created by Weave workflow'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('commit-message')), 'Add team notes');
    await tapReal(tester, find.byKey(const Key('commit-next')));
    await pumpUntil(tester, () => find.text('Commit 1 file to main').evaluate().isNotEmpty);
    expect(find.text('notes.txt'), findsOneWidget);

    await tapReal(tester, find.byKey(const Key('commit-approve')));
    await pumpUntil(tester, () => find.textContaining('Committed ').evaluate().isNotEmpty);

    final ProcessResult log = await tester.runAsync(() => Process.run('git', <String>['log', '-1', '--format=%s'], workingDirectory: repository.path)) as ProcessResult;
    expect((log.stdout as String).trim(), 'Add team notes');
  });

  testWidgets('guides first-time setup when no agent is ready', (WidgetTester tester) async {
    services = servicesWith(<AgentAdapter>[ScriptedAgentAdapter(id: 'claude-like', displayName: 'Signed-out Agent', isAvailable: false, signInCommand: 'agent auth login', handler: (AgentRunRequest request, ScriptedAgentSession session) => '')]);
    await launch(tester);
    await pumpUntil(tester, () => find.byKey(const Key('setup-banner')).evaluate().isNotEmpty);

    await tester.tap(find.text('Open Agents'));
    await pumpUntil(tester, () => find.byKey(const Key('copy-sign-in-claude-like')).evaluate().isNotEmpty);
    expect(find.textContaining('Run `agent auth login` in Terminal'), findsOneWidget);
  });

  testWidgets('pauses at the plan checkpoint, revises, and shows the checklist and usage', (WidgetTester tester) async {
    final List<String> plannerPrompts = <String>[];
    services = servicesWith(<AgentAdapter>[
      ScriptedAgentAdapter(
        id: 'solo',
        displayName: 'Solo Agent',
        usage: const AgentUsage(inputTokens: 100, outputTokens: 20),
        handler: (AgentRunRequest request, ScriptedAgentSession session) => switch (request.role) {
          AgentRole.planner => () {
            plannerPrompts.add(request.instructions);
            return '## Tasks\n- [ ] T1: Add notes.txt\n## Test cases\n- [ ] TC1: notes.txt exists';
          }(),
          AgentRole.implementer => '${writeNotes(request, session)}\nT1: done\nTC1: done',
          AgentRole.reviewer => 'T1: ok\nTC1: covered\nVERDICT: APPROVED',
        },
      ),
    ]);
    await launch(tester);
    await tester.enterText(find.byKey(const Key('repository')), repository.path);
    await tapReal(tester, find.text('Load'));
    await pumpUntil(tester, () => find.text('Git repository loaded').evaluate().isNotEmpty);
    await tester.ensureVisible(find.byKey(const Key('advanced')));
    await tester.tap(find.byKey(const Key('advanced')));
    // The first frame only starts the expansion ticker; the second runs it to
    // the end, so the switch is no longer clipped.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.byKey(const Key('approve-plan')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('approve-plan')));
    await tester.pump();
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('approve-plan'))).value, isTrue);
    await tester.enterText(find.byKey(const Key('request')), 'Add notes');
    await tapReal(tester, find.byKey(const Key('start')));

    await pumpUntil(tester, () => find.byKey(const Key('checkpoint-revise')).evaluate().isNotEmpty);
    expect(find.text('Approve the plan'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('checkpoint-feedback')), 'Mention the README');
    await tapReal(tester, find.byKey(const Key('checkpoint-revise')));
    await pumpUntil(tester, () => plannerPrompts.length == 2 && find.byKey(const Key('checkpoint-approve')).evaluate().isNotEmpty);
    expect(plannerPrompts.last, contains('Mention the README'));
    await tapReal(tester, find.byKey(const Key('checkpoint-approve')));
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);

    expect(find.byKey(const Key('checkpoint-approve')), findsNothing);
    expect(find.text('600 tokens (500 in, 100 out)'), findsOneWidget);
    await tester.tap(find.text('Checklist'));
    await pumpUntil(tester, () => find.text('Add notes.txt').evaluate().isNotEmpty);
    expect(find.text('Verified'), findsNWidgets(2));
    expect(find.textContaining('Implemented by Solo Agent · reviewed by Solo Agent'), findsNWidgets(2));
  });

  testWidgets('resumes an interrupted workflow from its page', (WidgetTester tester) async {
    final String root = (await tester.runAsync(repository.resolveSymbolicLinks))!;
    final WorkflowTask task = WorkflowTask.create(id: 'wf-interrupted', request: 'Add notes', repositoryPath: root, createdAt: DateTime.now()).transitionTo(WorkflowStatus.planning, at: DateTime.now());
    await tester.runAsync(() async {
      await services.tasks.save(task);
      await services.settings.saveForTask(
        task.id,
        WorkflowSettings(
          assignments: AgentAssignments(plannerAgentId: 'solo', implementerAgentId: 'solo', reviewerAgentId: 'solo'),
        ),
      );
    });
    await launch(tester);
    await pumpUntil(tester, () => find.byIcon(Icons.pause_circle_outline).evaluate().isNotEmpty);

    await tester.tap(find.text('Add notes'));
    await pumpUntil(tester, () => find.byKey(const Key('resume')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('resume')));
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);

    expect(find.byKey(const Key('resume')), findsNothing);
    expect(find.byIcon(Icons.pause_circle_outline), findsNothing);
    expect(File(path.join(repository.path, 'notes.txt')).existsSync(), isTrue);
  });
}
