import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:weave_agents/testing.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave/core/design_system/design_system.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../../../helpers/app_test_harness.dart';

/// Waits until a completed workflow has checked its repositories for changes.
Future<void> settleCommitCheck(WidgetTester tester) => pumpUntil(tester, () => find.byKey(const Key('commit')).evaluate().isNotEmpty || find.byKey(const Key('no-changes')).evaluate().isNotEmpty);

void main() {
  late AppTestHarness harness;

  setUp(() async {
    harness = AppTestHarness();
    await harness.initialize();
  });
  tearDown(() => harness.dispose());

  testWidgets('shows live activity, answers approvals, and displays artifacts and changes', (WidgetTester tester) async {
    harness.services = harness.servicesWith(<AgentAdapter>[
      harness.solo(
        implement: (AgentRunRequest request, ScriptedAgentSession session) async {
          if (request.resumeSessionId == null) {
            final ApprovalDecision decision = await session.requestApproval(action: 'network', details: 'Download a package');
            session.write('decision: ${decision.name}\n');
          }
          return harness.writeNotes(request, session);
        },
      ),
    ]);
    await harness.launch(tester);

    await harness.startFromForm(tester, 'Add notes');
    await pumpUntil(tester, () => find.byKey(const Key('approve')).evaluate().isNotEmpty);
    expect(find.textContaining('implementer asks to: network'), findsOneWidget);

    await tapReal(tester, find.byKey(const Key('approve')));
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);
    expect(find.byKey(const Key('approve')), findsNothing);
    expect(find.textContaining('decision: approve'), findsWidgets);
    expect(find.textContaining('wrote notes.txt'), findsWidgets);
    await pumpUntil(tester, () => find.text('implementer: Solo Agent').evaluate().isNotEmpty);
    expect(find.text('implementer: Solo Agent'), findsOneWidget);

    await tapReal(tester, find.byKey(const Key('plan-tab')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => find.text('Plan: add notes.txt').evaluate().isNotEmpty);

    await tester.ensureVisible(find.byKey(const Key('review-tab')));
    await tester.pumpAndSettle();
    await tapReal(tester, find.byKey(const Key('review-tab')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => find.text('VERDICT: APPROVED').evaluate().isNotEmpty);

    await tester.ensureVisible(find.byKey(const Key('changes-tab')));
    await tester.pumpAndSettle();
    await tapReal(tester, find.byKey(const Key('changes-tab')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tapReal(tester, find.byKey(const Key('show-changes')));
    await pumpUntil(tester, () => find.text('+notes').evaluate().isNotEmpty);
    expect(find.textContaining('notes.txt'), findsWidgets);
  });

  testWidgets('cancels a running workflow', (WidgetTester tester) async {
    harness.services = harness.servicesWith(<AgentAdapter>[
      harness.solo(
        implement: (AgentRunRequest request, ScriptedAgentSession session) async {
          await Completer<void>().future;
          return 'never';
        },
      ),
    ]);
    await harness.launch(tester);

    await harness.startFromForm(tester, 'Add notes');
    await pumpUntil(tester, () => find.byKey(const Key('cancel')).evaluate().isNotEmpty && find.text('Implementing').evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('cancel')));
    await pumpUntil(tester, () => find.text('Cancel this workflow?').evaluate().isNotEmpty);
    expect(find.text('This run cannot be resumed after cancellation.'), findsOneWidget);
    await tapReal(tester, find.byKey(const Key('cancel-confirm')));

    await pumpUntil(tester, () => find.text('Cancelled').evaluate().isNotEmpty);
    expect(find.byKey(const Key('cancel')), findsNothing);
    expect(find.textContaining('Cancelled by user.'), findsWidgets);
  });

  testWidgets('shows a quota recovery dialog and can cancel from it', (WidgetTester tester) async {
    harness.services = harness.servicesWith(<AgentAdapter>[
      ScriptedAgentAdapter(
        id: 'solo',
        displayName: 'Solo Agent',
        handler: (AgentRunRequest request, ScriptedAgentSession session) => switch (request.role) {
          AgentRole.planner => 'Plan: add notes.txt',
          AgentRole.implementer => throw const ScriptedAgentFailure('Usage limit reached.', kind: AgentFailureKind.rateLimit),
          AgentRole.reviewer => 'VERDICT: APPROVED',
        },
      ),
    ]);
    await harness.launch(tester);
    await harness.startFromForm(tester, 'Add notes');

    await pumpUntil(tester, () => find.text('Connection or quota interrupted').evaluate().isNotEmpty);
    expect(find.textContaining('Usage limit reached.'), findsOneWidget);
    await tapReal(tester, find.byKey(const Key('agent-unavailable-cancel')));
    await pumpUntil(tester, () => find.text('Cancelled').evaluate().isNotEmpty);
  });

  testWidgets('cancelling from the quota dialog while planning hides Cancel and stops the timeline at Plan', (WidgetTester tester) async {
    harness.services = harness.servicesWith(<AgentAdapter>[
      ScriptedAgentAdapter(
        id: 'solo',
        displayName: 'Solo Agent',
        handler: (AgentRunRequest request, ScriptedAgentSession session) => switch (request.role) {
          AgentRole.planner => throw const ScriptedAgentFailure('You have hit your usage limit.', kind: AgentFailureKind.rateLimit),
          AgentRole.implementer => 'never',
          AgentRole.reviewer => 'VERDICT: APPROVED',
        },
      ),
    ]);
    await harness.launch(tester);
    await harness.startFromForm(tester, 'Add notes');

    await pumpUntil(tester, () => find.text('Connection or quota interrupted').evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('agent-unavailable-cancel')));
    await pumpUntil(tester, () => find.text('Workflow cancelled').evaluate().isNotEmpty);
    // Let the page cross-fade from New Task finish.
    await tester.pump(WeaveMotion.standard + const Duration(milliseconds: 50));

    expect(find.byKey(const Key('cancel')), findsNothing, reason: 'a cancelled workflow cannot be cancelled again');
    final WeaveStepTimeline timeline = tester.widget<WeaveStepTimeline>(find.byType(WeaveStepTimeline));
    expect(timeline.steps.first.status, WeaveStepStatus.failed, reason: 'the run stopped while planning');
    expect(timeline.steps.first.subtitle, 'Cancelled');
    expect(timeline.steps.skip(1).map((WeaveStep step) => step.status), everyElement(WeaveStepStatus.pending));
    expect(find.text('Editing the repository working tree…'), findsNothing);
  });

  testWidgets('deletes a finished workflow after confirmation, leaving the repository alone', (WidgetTester tester) async {
    await harness.launch(tester);
    await harness.startFromForm(tester, 'Add notes');
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);
    await settleCommitCheck(tester);
    final Finder delete = find.byKey(const Key('delete-workflow'));
    expect(delete, findsOneWidget);

    await tapReal(tester, delete);
    await pumpUntil(tester, () => find.text('Delete this workflow?').evaluate().isNotEmpty);
    expect(find.text('Repository untouched'), findsOneWidget);
    await tapReal(tester, find.byKey(const Key('delete-keep')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(delete, findsOneWidget, reason: 'Keep leaves the workflow');

    await tapReal(tester, delete);
    await pumpUntil(tester, () => find.byKey(const Key('delete-confirm')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('delete-confirm')));
    await pumpUntil(tester, () => find.text('What should Weave build?').evaluate().isNotEmpty);

    expect(await tester.runAsync(() => harness.services.tasks.list()), isEmpty);
    expect(File(path.join(harness.repository.path, 'notes.txt')).existsSync(), isTrue, reason: 'the repository keeps its changes');
    expect(find.text('Recent workflows'), findsNothing);
  });

  testWidgets('a recent workflow shows Delete on hover and is deleted from the Home list after confirmation', (WidgetTester tester) async {
    await harness.launch(tester);
    await harness.startFromForm(tester, 'Add notes');
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);
    await settleCommitCheck(tester);
    final String taskId = (await tester.runAsync(() => harness.services.tasks.list()))!.single.id;
    await tapReal(tester, find.byKey(const Key('sidebar-home')));
    final Finder card = find.byKey(ValueKey<String>('home-recent-$taskId'));
    await pumpUntil(tester, () => card.evaluate().isNotEmpty);
    final Finder delete = find.byKey(ValueKey<String>('delete-recent-$taskId'));
    double deleteOpacity() => tester.widget<Opacity>(find.ancestor(of: delete, matching: find.byType(Opacity)).first).opacity;
    expect(deleteOpacity(), 0, reason: 'hidden until the card is hovered');

    final TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getTopLeft(card) + const Offset(4, 4));
    await tester.pump();
    expect(deleteOpacity(), 1, reason: 'hovering anywhere on the card shows Delete');
    expect(
      tester.widget<WeaveMarqueeText>(find.descendant(of: card, matching: find.byType(WeaveMarqueeText))).active,
      isTrue,
      reason: 'and lets a long title scroll',
    );

    await tapReal(tester, delete);
    await pumpUntil(tester, () => find.byKey(const Key('delete-confirm')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('delete-confirm')));
    await pumpUntil(tester, () => card.evaluate().isEmpty);
    expect(await tester.runAsync(() => harness.services.tasks.list()), isEmpty);
  });

  testWidgets('a running workflow offers no delete action', (WidgetTester tester) async {
    harness.services = harness.servicesWith(<AgentAdapter>[
      harness.solo(
        implement: (AgentRunRequest request, ScriptedAgentSession session) async {
          await Completer<void>().future;
          return 'never';
        },
      ),
    ]);
    await harness.launch(tester);
    await harness.startFromForm(tester, 'Add notes');
    await pumpUntil(tester, () => find.text('Implementing').evaluate().isNotEmpty);
    expect(find.byKey(const Key('delete-workflow')), findsNothing);
    await tapReal(tester, find.byKey(const Key('cancel')));
    await pumpUntil(tester, () => find.byKey(const Key('cancel-confirm')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('cancel-confirm')));
    await pumpUntil(tester, () => find.byKey(const Key('delete-workflow')).evaluate().isNotEmpty);
  });

  testWidgets('opening a finished workflow fades in once its history is loaded', (WidgetTester tester) async {
    await harness.launch(tester);
    await harness.startFromForm(tester, 'Add notes');
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);
    final String taskId = (await tester.runAsync(() => harness.services.tasks.list()))!.single.id;
    // A fresh app reads the finished workflow from disk instead of a live run.
    await tester.pumpWidget(const SizedBox());
    await harness.launch(tester);

    await tester.tap(find.byKey(ValueKey<String>('home-recent-$taskId')));
    await tester.pump();
    double opacity() => tester.widget<AnimatedOpacity>(find.byKey(const Key('workflow-page-fade'))).opacity;
    expect(opacity(), 0, reason: 'hidden while the stored log is read, so the timeline does not jump');

    await pumpUntil(tester, () => opacity() == 1);
    final WeaveStepTimeline timeline = tester.widget<WeaveStepTimeline>(find.descendant(of: find.byKey(const Key('workflow-page-fade')), matching: find.byType(WeaveStepTimeline)));
    expect(timeline.steps.map((WeaveStep step) => step.status), everyElement(WeaveStepStatus.done), reason: 'first visible frame already shows the finished timeline');
  });

  testWidgets('works across repositories: add one, allow edits after planning, and commit each changed one', (WidgetTester tester) async {
    final Directory backend = Directory(path.join(harness.temporaryDirectory.path, 'backend'))..createSync();
    await tester.runAsync(() async {
      await Process.run('git', <String>['init', '--quiet', '--initial-branch=main'], workingDirectory: backend.path);
    });
    harness.services = harness.servicesWith(<AgentAdapter>[
      ScriptedAgentAdapter(
        id: 'solo',
        displayName: 'Solo Agent',
        handler: (AgentRunRequest request, ScriptedAgentSession session) => switch (request.role) {
          AgentRole.planner => '## Tasks\n- [ ] T1: Add the notes API\n## Repositories to change\n- backend: add the notes API',
          AgentRole.implementer => () {
            final AgentDirectoryAccess access = request.additionalDirectories.single;
            File(path.join(access.path, 'notes_api.txt')).writeAsStringSync('notes api\n');
            return 'T1: done';
          }(),
          AgentRole.reviewer => 'T1: ok\nVERDICT: APPROVED',
        },
      ),
    ]);
    await harness.launch(tester);
    await harness.chooseRepository(tester, harness.repository.path);
    await harness.chooseAgents(tester);

    Future<void> addRepository(String directory) async {
      await tapReal(tester, find.byKey(const Key('repository-add')));
      await tester.pumpAndSettle();
      harness.picker.nextDirectory = directory;
      await tapReal(tester, find.byKey(const Key('repository-browse')));
      await pumpUntil(tester, () => find.byType(WeaveDialog).evaluate().isEmpty);
    }

    await addRepository(backend.path);
    final String backendRoot = backend.resolveSymbolicLinksSync();
    expect(find.byKey(ValueKey<String>('repository-$backendRoot')), findsOneWidget);
    expect(find.text('Repositories'), findsOneWidget);
    await addRepository(backend.path);
    expect(find.text('backend is already part of this task.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('request')), 'Using backend, add the notes API');
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tester.pump(const Duration(milliseconds: 100));
    await tapReal(tester, find.byKey(const Key('start')));
    await pumpUntil(tester, () => find.byKey(const Key('advanced-save')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('advanced-save')));

    await pumpUntil(tester, () => find.text('Allow edits to these repositories?').evaluate().isNotEmpty);
    bool allowed(String name) => tester.widget<WeaveCheckbox>(find.descendant(of: find.byKey(ValueKey<String>('repository-choice-$name')), matching: find.byType(WeaveCheckbox))).value;
    expect(allowed('backend'), isTrue, reason: 'the plan proposed it');
    expect(allowed('repo'), isFalse);
    expect(find.text('add the notes API'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('checkpoint-approve')));
    await tester.pump(const Duration(milliseconds: 100));
    await tapReal(tester, find.byKey(const Key('checkpoint-approve')));

    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);
    expect(File(path.join(backend.path, 'notes_api.txt')).existsSync(), isTrue);
    expect(find.text('Repositories: repo, backend'), findsOneWidget);

    // Commit appears once Weave has seen that there are changes.
    await pumpUntil(tester, () => find.byKey(const Key('commit')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('commit')));
    await pumpUntil(tester, () => find.text('Commit backend').evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('commit-next')));
    await pumpUntil(tester, () => find.byKey(const Key('commit-approve')).evaluate().isNotEmpty);
    expect(find.text('notes_api.txt'), findsOneWidget, reason: 'the exact file list of the backend commit');
    await tapReal(tester, find.byKey(const Key('commit-approve')));
    await pumpUntil(tester, () => find.textContaining('backend: Committed').evaluate().isNotEmpty);
    final ProcessResult log = (await tester.runAsync(() => Process.run('git', <String>['log', '--format=%s'], workingDirectory: backend.path)))!;
    expect((log.stdout as String).trim(), isNotEmpty);
    await pumpUntil(tester, () => find.byKey(const Key('no-changes')).evaluate().isNotEmpty);
  });

  testWidgets('shows the agent sign-in dialog without storing credentials', (WidgetTester tester) async {
    harness.services = harness.servicesWith(<AgentAdapter>[_AuthenticationFailureAdapter()]);
    await harness.launch(tester);
    await harness.startFromForm(tester, 'Add notes');

    await pumpUntil(tester, () => find.text('Solo Agent needs you to sign in').evaluate().isNotEmpty);
    expect(find.text('Weave never asks for or stores your password.'), findsOneWidget);
    expect(find.text('solo auth login'), findsOneWidget);
    await tapReal(tester, find.byKey(const Key('agent-unavailable-cancel')));
    await pumpUntil(tester, () => find.text('Cancelled').evaluate().isNotEmpty);
  });

  testWidgets('renders the execution timeline and reflows at minimum width', (WidgetTester tester) async {
    harness.services = harness.servicesWith(<AgentAdapter>[
      harness.solo(
        implement: (AgentRunRequest request, ScriptedAgentSession session) async {
          session.write('Editing notes.txt\n');
          await Completer<void>().future;
          return 'never';
        },
      ),
    ]);
    await harness.launch(tester, size: WeaveLayout.defaultWindow);
    await harness.startFromForm(tester, 'Add notes');
    await pumpUntil(tester, () => find.text('Execution timeline').evaluate().isNotEmpty && find.textContaining('Editing notes.txt').evaluate().isNotEmpty);

    tester.view.physicalSize = WeaveLayout.minimumWindow;
    await tester.pump();
    expect(find.text('Execution timeline'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tapReal(tester, find.byKey(const Key('cancel')));
    await pumpUntil(tester, () => find.byKey(const Key('cancel-confirm')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('cancel-confirm')));
    await pumpUntil(tester, () => find.text('Cancelled').evaluate().isNotEmpty);
  });

  testWidgets('commits a completed workflow after approval', (WidgetTester tester) async {
    for (final List<String> setting in <List<String>>[
      <String>['user.name', 'Weave Test'],
      <String>['user.email', 'weave@example.com'],
      <String>['commit.gpgsign', 'false'],
      <String>['core.hooksPath', '/dev/null'],
    ]) {
      await tester.runAsync(() => Process.run('git', <String>['config', ...setting], workingDirectory: harness.repository.path));
    }
    await harness.launch(tester);
    await harness.startFromForm(tester, 'Add notes');
    await pumpUntil(tester, () => find.byKey(const Key('commit')).evaluate().isNotEmpty);
    final Rect commit = tester.getRect(find.byKey(const Key('commit')));
    final Rect delete = tester.getRect(find.byKey(const Key('delete-workflow')));
    expect(find.descendant(of: find.byKey(const Key('workflow-actions')), matching: find.byKey(const Key('commit'))), findsOneWidget);
    expect(commit.top, greaterThan(tester.getRect(find.byKey(const Key('activity-tab'))).bottom), reason: 'at the bottom of the page');
    expect(commit.left, greaterThan(delete.right), reason: 'the primary action is last, at the right');
    expect(tester.view.physicalSize.width / tester.view.devicePixelRatio - commit.right, WeaveSpacing.s28, reason: 'aligned with the page\'s right edge');

    await tester.tap(find.byKey(const Key('commit')));
    await pumpUntil(tester, () => find.byKey(const Key('commit-message')).evaluate().isNotEmpty);
    expect(find.textContaining('Created by Weave workflow'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('commit-message')), 'Add team notes');
    await tapReal(tester, find.byKey(const Key('commit-next')));
    await pumpUntil(tester, () => find.text('Commit 1 file to main').evaluate().isNotEmpty);
    expect(find.text('notes.txt'), findsOneWidget);

    await tapReal(tester, find.byKey(const Key('commit-approve')));
    await pumpUntil(tester, () => find.textContaining('Committed ').evaluate().isNotEmpty);

    final ProcessResult log = await tester.runAsync(() => Process.run('git', <String>['log', '-1', '--format=%s'], workingDirectory: harness.repository.path)) as ProcessResult;
    expect((log.stdout as String).trim(), 'Add team notes');
    await pumpUntil(tester, () => find.byKey(const Key('no-changes')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('commit')), findsNothing, reason: 'nothing is left to commit');
  });

  testWidgets('a completed workflow that changed nothing offers no commit', (WidgetTester tester) async {
    harness.services = harness.servicesWith(<AgentAdapter>[harness.solo(implement: (AgentRunRequest request, ScriptedAgentSession session) => 'Nothing to change')]);
    await harness.launch(tester);
    await harness.startFromForm(tester, 'hello');
    await pumpUntil(tester, () => find.byKey(const Key('no-changes')).evaluate().isNotEmpty);

    expect(find.text('Completed'), findsWidgets);
    expect(find.byKey(const Key('commit')), findsNothing);
  });

  testWidgets('the activity log follows new lines at its end, but not after the user scrolls up', (WidgetTester tester) async {
    final List<Completer<void>> steps = <Completer<void>>[Completer<void>(), Completer<void>()];
    harness.services = harness.servicesWith(<AgentAdapter>[
      harness.solo(
        implement: (AgentRunRequest request, ScriptedAgentSession session) async {
          for (final Completer<void> step in steps) {
            for (int line = 0; line < 60; line++) {
              session.write('output line $line\n');
            }
            await step.future;
          }
          return harness.writeNotes(request, session);
        },
      ),
    ]);
    await harness.launch(tester);
    await harness.startFromForm(tester, 'Add notes');
    final Finder list = find.byKey(const Key('activity-list'));
    ScrollPosition position() => tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable))).position;
    await pumpUntil(tester, () => list.evaluate().isNotEmpty && position().maxScrollExtent > 0);
    await tester.pump();
    expect(position().pixels, position().maxScrollExtent, reason: 'follows the newest line');

    await tester.drag(list, const Offset(0, 400));
    await tester.pump();
    final double reading = position().pixels;
    expect(reading, lessThan(position().maxScrollExtent));
    steps[0].complete();
    await pumpUntil(tester, () => find.textContaining('output line 59').evaluate().length > 1 || position().maxScrollExtent > reading + 600);
    await tester.pump();
    expect(position().pixels, reading, reason: 'reading older lines is not interrupted');

    position().jumpTo(position().maxScrollExtent);
    await tester.pump();
    steps[1].complete();
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);
    await tester.pump();
    expect(position().pixels, position().maxScrollExtent, reason: 'back at the end, it follows again');
  });

  testWidgets('reviews the changes on the Code Review screen before verification', (WidgetTester tester) async {
    harness.services = harness.servicesWith(<AgentAdapter>[
      ScriptedAgentAdapter(
        id: 'solo',
        displayName: 'Solo Agent',
        handler: (AgentRunRequest request, ScriptedAgentSession session) => switch (request.role) {
          AgentRole.planner => '## Tasks\n- [ ] T1: Add notes.txt\n## Test cases\n- [ ] TC1: notes.txt exists',
          AgentRole.implementer => '${harness.writeNotes(request, session)}\nT1: done\nTC1: done',
          AgentRole.reviewer => 'T1: ok\nTC1: covered\nVERDICT: APPROVED',
        },
      ),
    ]);
    await harness.launch(tester);
    await harness.chooseRepository(tester, harness.repository.path);
    await harness.chooseAgents(tester);
    await tester.enterText(find.byKey(const Key('request')), 'Add notes');
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tapReal(tester, find.byKey(const Key('start')));
    await pumpUntil(tester, () => find.byKey(const Key('approve-changes')).evaluate().isNotEmpty);
    await tester.ensureVisible(find.byKey(const Key('approve-changes')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('approve-changes')));
    await tester.pump();
    await tapReal(tester, find.byKey(const Key('advanced-save')));

    await pumpUntil(tester, () => find.byKey(const ValueKey<String>('review-diff-notes.txt')).evaluate().isNotEmpty);
    expect(find.text('Review changes'), findsNWidgets(2), reason: 'breadcrumb and title');
    expect(find.text('1 file · +1 −0'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('review-file-notes.txt')), findsOneWidget);
    expect(find.widgetWithText(WeaveStatusPill, 'Added'), findsOneWidget);
    expect(find.text('notes'), findsOneWidget, reason: 'the added line is shown in the Updated column');
    expect(find.text('After approval'), findsNothing, reason: 'no verification commands are configured');
    expect(find.text('No verification commands configured.'), findsOneWidget);
    expect(find.widgetWithText(WeaveStatusPill, 'Complete'), findsOneWidget);
    expect(find.text('notes.txt exists'), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byKey(const Key('review-agent-summary'))).data, isNot(contains('Changed files:')));

    tester.view.physicalSize = WeaveLayout.minimumWindow;
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('review-diff-notes.txt')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the stacked layout fits the minimum window');
    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('checkpoint-approve')));
    await tester.pump(const Duration(milliseconds: 100));
    await tapReal(tester, find.byKey(const Key('checkpoint-approve')));
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);
    expect(find.text('Review changes'), findsNothing);
  });

  testWidgets('pauses at the plan checkpoint, revises, and shows the checklist and usage', (WidgetTester tester) async {
    final List<String> plannerPrompts = <String>[];
    harness.services = harness.servicesWith(<AgentAdapter>[
      ScriptedAgentAdapter(
        id: 'solo',
        displayName: 'Solo Agent',
        usage: const AgentUsage(inputTokens: 100, outputTokens: 20),
        handler: (AgentRunRequest request, ScriptedAgentSession session) => switch (request.role) {
          AgentRole.planner => () {
            plannerPrompts.add(request.instructions);
            return '## Tasks\n- [ ] T1: Add notes.txt\n## Test cases\n- [ ] TC1: notes.txt exists';
          }(),
          AgentRole.implementer => '${harness.writeNotes(request, session)}\nT1: done\nTC1: done',
          AgentRole.reviewer => 'T1: ok\nTC1: covered\nVERDICT: APPROVED',
        },
      ),
    ]);
    await harness.launch(tester);
    await harness.chooseRepository(tester, harness.repository.path);
    await harness.chooseAgents(tester);
    await tester.enterText(find.byKey(const Key('request')), 'Add notes');
    await tester.ensureVisible(find.byKey(const Key('start')));
    await tapReal(tester, find.byKey(const Key('start')));
    await pumpUntil(tester, () => find.byKey(const Key('approve-plan')).evaluate().isNotEmpty);
    await tester.ensureVisible(find.byKey(const Key('approve-plan')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('approve-plan')));
    await tester.pump();
    expect(tester.widget<WeaveSwitch>(find.byKey(const Key('approve-plan'))).value, isTrue);
    await tapReal(tester, find.byKey(const Key('advanced-save')));

    await pumpUntil(tester, () => find.byKey(const Key('checkpoint-revise')).evaluate().isNotEmpty);
    expect(find.text('Review the implementation plan'), findsNWidgets(2));
    expect(find.text('Implementation plan'), findsOneWidget);
    expect(find.text('Review checklist'), findsOneWidget);
    expect(find.text('Planner was read-only'), findsOneWidget);
    tester.view.physicalSize = WeaveLayout.minimumWindow;
    await tester.pumpAndSettle();
    expect(find.text('Review checklist'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const Key('checkpoint-feedback')), matching: find.byType(TextField)), 'Mention the README');
    await tester.ensureVisible(find.byKey(const Key('checkpoint-revise')));
    await tester.pumpAndSettle();
    await tapReal(tester, find.byKey(const Key('checkpoint-revise')));
    await pumpUntil(tester, () => plannerPrompts.length == 2 && find.byKey(const Key('checkpoint-approve')).evaluate().isNotEmpty);
    expect(plannerPrompts.last, contains('Mention the README'));
    await tester.ensureVisible(find.byKey(const Key('checkpoint-approve')));
    await tester.pumpAndSettle();
    await tapReal(tester, find.byKey(const Key('checkpoint-approve')));
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);

    expect(find.byKey(const Key('checkpoint-approve')), findsNothing);
    final WeaveBadge usage = tester.widget<WeaveBadge>(find.byKey(const Key('usage')));
    expect(usage.label, '600 tokens (500 in, 100 out)');
    await tapReal(tester, find.byKey(const Key('checklist-tab')));
    await tester.pumpAndSettle();
    expect(DefaultTabController.of(tester.element(find.byType(TabBar))).index, 1);
    await pumpUntil(tester, () => find.text('Add notes.txt').evaluate().isNotEmpty);
    expect(find.text('Verified'), findsNWidgets(2));
    expect(find.textContaining('Implemented by Solo Agent · reviewed by Solo Agent'), findsNWidgets(2));
  });

  testWidgets('resumes an interrupted workflow from its page', (WidgetTester tester) async {
    final String root = (await tester.runAsync(harness.repository.resolveSymbolicLinks))!;
    final WorkflowTask task = WorkflowTask.create(id: 'wf-interrupted', request: 'Add notes', repositoryPath: root, createdAt: DateTime.now()).transitionTo(WorkflowStatus.planning, at: DateTime.now());
    await tester.runAsync(() async {
      await harness.services.tasks.save(task);
      await harness.services.settings.saveForTask(
        task.id,
        WorkflowSettings(
          assignments: AgentAssignments(plannerAgentId: 'solo', implementerAgentId: 'solo', reviewerAgentId: 'solo'),
        ),
      );
    });
    await harness.launch(tester);
    await pumpUntil(tester, () => find.byKey(const ValueKey<String>('home-recent-wf-interrupted')).evaluate().isNotEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('home-recent-wf-interrupted')));
    await pumpUntil(tester, () => find.byKey(const Key('resume')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('resume')));
    await pumpUntil(tester, () => find.text('Completed').evaluate().isNotEmpty);

    expect(find.byKey(const Key('resume')), findsNothing);
    expect(File(path.join(harness.repository.path, 'notes.txt')).existsSync(), isTrue);
  });
}

final class _AuthenticationFailureAdapter implements AgentAdapter {
  _AuthenticationFailureAdapter()
    : _delegate = ScriptedAgentAdapter(
        id: 'solo',
        displayName: 'Solo Agent',
        handler: (AgentRunRequest request, ScriptedAgentSession session) => switch (request.role) {
          AgentRole.planner => 'Plan: add notes.txt',
          AgentRole.implementer => throw const ScriptedAgentFailure('Authentication required.', kind: AgentFailureKind.authentication),
          AgentRole.reviewer => 'VERDICT: APPROVED',
        },
      );

  final ScriptedAgentAdapter _delegate;

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
  bool get reportsPlanUsage => _delegate.reportsPlanUsage;

  @override
  Future<AgentPlanUsage> readPlanUsage() => _delegate.readPlanUsage();

  @override
  bool get supportsMcp => _delegate.supportsMcp;

  @override
  Future<AgentAvailability> checkAvailability() async => _delegate.requests.isEmpty ? AgentAvailability.available(version: 'scripted', executablePath: 'scripted:solo') : AgentAvailability.signInRequired(version: 'scripted', executablePath: 'scripted:solo', signInCommand: 'solo auth login');

  @override
  Future<AgentExecution> start(AgentRunRequest request) => _delegate.start(request);
}
