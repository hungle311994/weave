import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/testing.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_security/weave_security.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

final class _Verifier implements VerificationRunner {
  _Verifier(this.outcomes);

  final List<bool> outcomes;
  int runs = 0;

  @override
  Future<VerificationResult> run(VerificationCommand command, {required String workingDirectory}) async {
    final bool passed = runs < outcomes.length ? outcomes[runs] : true;
    runs++;
    return VerificationResult(command: command, exitCode: passed ? 0 : 1, output: passed ? '' : 'test failed', duration: Duration.zero);
  }
}

const String _plan = '''
## Tasks
- [ ] T1: Add hello.txt
## Test cases
- [ ] TC1: hello.txt contains a greeting
''';

void main() {
  late Directory temporaryDirectory;
  late Directory repository;
  late WeaveStoragePaths paths;
  late FileWorkflowTaskStore tasks;
  late FileWorkflowArtifactStore artifacts;
  late FileWorkflowSettingsStore settingsStore;
  late FileWorkflowRunStateStore runStates;
  late WorkflowRunLock locks;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-resilience-test-');
    repository = await Directory(path.join(temporaryDirectory.path, 'repo')).create();
    paths = WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: <String, String>{'WEAVE_HOME': path.join(temporaryDirectory.path, 'home')});
    tasks = FileWorkflowTaskStore(workflowsDirectory: paths.workflowsDirectory);
    artifacts = FileWorkflowArtifactStore(workflowsDirectory: paths.workflowsDirectory, redactor: SecretRedactor());
    settingsStore = FileWorkflowSettingsStore(paths: paths);
    runStates = FileWorkflowRunStateStore(workflowsDirectory: paths.workflowsDirectory);
    locks = WorkflowRunLock(workflowsDirectory: paths.workflowsDirectory);
    expect((await Process.run('git', <String>['init', '--quiet', '--initial-branch=main'], workingDirectory: repository.path)).exitCode, 0);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  WorkflowOrchestrator orchestratorFor(List<AgentAdapter> adapters, {VerificationRunner? verifier}) => WorkflowOrchestrator(agents: AgentRegistry(adapters), tasks: tasks, artifacts: artifacts, settingsStore: settingsStore, runStates: runStates, locks: locks, verifier: verifier ?? _Verifier(<bool>[]), createTaskId: () => 'task-1', environment: const <String, String>{});

  WorkflowSettings settingsFor({String implementer = 'implementer', Map<AgentRole, List<String>> fallbacks = const <AgentRole, List<String>>{}, int verificationCommands = 0, bool requirePlanApproval = false, bool requireChangesApproval = false, bool reviewPlan = false, int? maxTokens, int maxRetries = 3}) => WorkflowSettings(
    assignments: AgentAssignments(plannerAgentId: 'planner', implementerAgentId: implementer, reviewerAgentId: 'reviewer'),
    verificationCommands: <VerificationCommand>[for (int index = 0; index < verificationCommands; index++) VerificationCommand.parse('check $index')],
    fallbackAgentIds: fallbacks,
    requirePlanApproval: requirePlanApproval,
    requireChangesApproval: requireChangesApproval,
    reviewPlan: reviewPlan,
    maxTokens: maxTokens,
    maxRetries: maxRetries,
    retryDelay: Duration.zero,
  );

  ScriptedAgentAdapter planner({ScriptedAgentHandler? handler, AgentUsage? usage}) => ScriptedAgentAdapter(id: 'planner', usage: usage, handler: handler ?? (AgentRunRequest request, ScriptedAgentSession session) => _plan);

  ScriptedAgentAdapter implementer({String id = 'implementer', ScriptedAgentHandler? handler, AgentUsage? usage}) => ScriptedAgentAdapter(
    id: id,
    usage: usage,
    handler:
        handler ??
        (AgentRunRequest request, ScriptedAgentSession session) {
          File(path.join(request.workingDirectory, 'hello.txt')).writeAsStringSync('hello ${request.task.reviewCycle}\n');
          return 'Added hello.txt\nT1: done\nTC1: done';
        },
  );

  ScriptedAgentAdapter reviewer(List<String> replies, {AgentUsage? usage}) {
    int index = 0;
    return ScriptedAgentAdapter(id: 'reviewer', usage: usage, handler: (AgentRunRequest request, ScriptedAgentSession session) => replies[index++]);
  }

  /// Answers every checkpoint with the next entry of [answers].
  void answerCheckpoints(WorkflowRun run, List<(CheckpointDecision, String?)> answers) {
    int index = 0;
    run.events.listen((WorkflowEvent event) {
      if (event is WorkflowCheckpointRequested) {
        final (CheckpointDecision decision, String? feedback) = answers[index++];
        run.resolveCheckpoint(event.checkpoint.id, decision, feedback: feedback);
      }
    });
  }

  group('usage and budget', () {
    test('adds up tokens per role and reports each finished agent', () async {
      const AgentUsage usage = AgentUsage(inputTokens: 100, outputTokens: 10, costUsd: 0.01);
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
        planner(usage: usage),
        implementer(usage: usage),
        reviewer(<String>['VERDICT: APPROVED'], usage: usage),
      ]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor());

      expect((await run.result).status, WorkflowStatus.completed);
      expect(run.usage.totalTokens, 440);
      expect(run.usage.costUsd, closeTo(0.04, 1e-9));
      expect(run.usageByRole[AgentRole.implementer]!.totalTokens, 220);
      expect(run.history.whereType<WorkflowAgentFinished>().map((WorkflowAgentFinished event) => event.phase), <String>['plan', 'implement', 'self-review', 'review']);
      expect((await runStates.load('task-1'))!.totalUsage.totalTokens, 440);
    });

    test('stops when the token budget is exceeded', () async {
      const AgentUsage usage = AgentUsage(inputTokens: 600);
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
        planner(usage: usage),
        implementer(usage: usage),
        reviewer(<String>['VERDICT: APPROVED']),
      ]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor(maxTokens: 1000));

      expect((await run.result).status, WorkflowStatus.failed);
      expect((run.history.last as WorkflowFinished).reason, 'Token budget exceeded: 1200 of 1000 tokens used.');
    });

    test('skips the reviewer while verification fails', () async {
      final ScriptedAgentAdapter reviewerAgent = reviewer(<String>['VERDICT: APPROVED']);
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[planner(), implementer(), reviewerAgent], verifier: _Verifier(<bool>[false, true])).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor(verificationCommands: 1));

      final WorkflowTask task = await run.result;

      expect(task.status, WorkflowStatus.completed);
      expect(task.reviewCycle, 1);
      expect(reviewerAgent.requests, hasLength(1));
    });
  });

  group('checkpoints', () {
    test('waits for plan approval and revises the plan with feedback', () async {
      final ScriptedAgentAdapter plannerAgent = planner();
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
        plannerAgent,
        implementer(),
        reviewer(<String>['VERDICT: APPROVED']),
      ]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor(requirePlanApproval: true));
      answerCheckpoints(run, <(CheckpointDecision, String?)>[(CheckpointDecision.revise, 'Also update the README'), (CheckpointDecision.approve, null)]);

      expect((await run.result).status, WorkflowStatus.completed);
      expect(plannerAgent.requests, hasLength(2));
      expect(plannerAgent.requests.last.instructions, allOf(contains('Also update the README'), contains('Previous plan:')));
      final WorkflowCheckpoint checkpoint = run.history.whereType<WorkflowCheckpointRequested>().first.checkpoint;
      expect(checkpoint.kind, WorkflowCheckpointKind.plan);
      expect(checkpoint.details, contains('T1: Add hello.txt'));
    });

    test('cancels from the plan checkpoint', () async {
      final ScriptedAgentAdapter implementerAgent = implementer();
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[planner(), implementerAgent, reviewer(<String>[])]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor(requirePlanApproval: true));
      answerCheckpoints(run, <(CheckpointDecision, String?)>[(CheckpointDecision.cancel, null)]);

      expect((await run.result).status, WorkflowStatus.cancelled);
      expect(implementerAgent.requests, isEmpty);
    });

    test('revises the changes before review when the user asks', () async {
      final ScriptedAgentAdapter implementerAgent = implementer();
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
        planner(),
        implementerAgent,
        reviewer(<String>['VERDICT: APPROVED']),
      ]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor(requireChangesApproval: true));
      answerCheckpoints(run, <(CheckpointDecision, String?)>[(CheckpointDecision.revise, 'Use a friendlier greeting'), (CheckpointDecision.approve, null)]);

      expect((await run.result).status, WorkflowStatus.completed);
      expect(implementerAgent.requests, hasLength(4));
      expect(implementerAgent.requests[2].instructions, contains('Use a friendlier greeting'));
      final WorkflowCheckpoint checkpoint = run.history.whereType<WorkflowCheckpointRequested>().first.checkpoint;
      expect(checkpoint.details, contains('- hello.txt'));
      expect(() => run.resolveCheckpoint('missing', CheckpointDecision.approve), throwsStateError);
    });

    test('lets the reviewer send the plan back before any code changes', () async {
      final ScriptedAgentAdapter plannerAgent = planner();
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
        plannerAgent,
        implementer(),
        reviewer(<String>['Missing an error case.\nVERDICT: CHANGES_REQUESTED', 'VERDICT: APPROVED', 'VERDICT: APPROVED']),
      ]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor(reviewPlan: true));

      expect((await run.result).status, WorkflowStatus.completed);
      expect(plannerAgent.requests, hasLength(2));
      expect(plannerAgent.requests.last.instructions, contains('Missing an error case.'));
      expect((await artifacts.readArtifacts('task-1')).where((WorkflowArtifact artifact) => artifact.kind == WorkflowArtifactKind.planReview), hasLength(1));
    });
  });

  group('agent failures', () {
    test('retries network failures and resumes the session', () async {
      int calls = 0;
      final ScriptedAgentAdapter implementerAgent = implementer(
        handler: (AgentRunRequest request, ScriptedAgentSession session) {
          calls++;
          if (calls == 1) {
            throw const ScriptedAgentFailure('ECONNRESET', kind: AgentFailureKind.network, sessionId: 'session-before-drop');
          }
          File(path.join(request.workingDirectory, 'hello.txt')).writeAsStringSync('hello\n');
          return 'T1: done';
        },
      );
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
        planner(),
        implementerAgent,
        reviewer(<String>['VERDICT: APPROVED']),
      ]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor());

      expect((await run.result).status, WorkflowStatus.completed);
      expect(implementerAgent.requests[1].resumeSessionId, 'session-before-drop');
      final WorkflowRetryScheduled retry = run.history.whereType<WorkflowRetryScheduled>().single;
      expect(retry.attempt, 2);
      expect(retry.reason, 'ECONNRESET');
    });

    test('fails after the retry limit', () async {
      final ScriptedAgentAdapter offline = implementer(handler: (AgentRunRequest request, ScriptedAgentSession session) => throw const ScriptedAgentFailure('getaddrinfo ENOTFOUND', kind: AgentFailureKind.network));
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[planner(), offline, reviewer(<String>[])]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor(maxRetries: 2));

      expect((await run.result).status, WorkflowStatus.failed);
      expect(offline.requests, hasLength(3));
      expect(run.history.whereType<WorkflowRetryScheduled>(), hasLength(2));
    });

    test('switches to a fallback agent when the usage limit is reached', () async {
      final ScriptedAgentAdapter limited = implementer(handler: (AgentRunRequest request, ScriptedAgentSession session) => throw const ScriptedAgentFailure('usage limit reached', kind: AgentFailureKind.rateLimit));
      final ScriptedAgentAdapter offlineFallback = ScriptedAgentAdapter(id: 'offline', isAvailable: false, handler: (AgentRunRequest request, ScriptedAgentSession session) => '');
      final ScriptedAgentAdapter backup = implementer(id: 'backup');
      final WorkflowRun run =
          await orchestratorFor(<AgentAdapter>[
            planner(),
            limited,
            offlineFallback,
            backup,
            reviewer(<String>['VERDICT: APPROVED']),
          ]).start(
            request: 'Add hello',
            repositoryPath: repository.path,
            settings: settingsFor(
              fallbacks: <AgentRole, List<String>>{
                AgentRole.implementer: <String>['offline', 'backup'],
              },
            ),
          );

      expect((await run.result).status, WorkflowStatus.completed);
      expect(limited.requests, hasLength(1));
      expect(backup.requests, hasLength(2));
      expect(backup.requests.first.resumeSessionId, isNull);
      expect(run.agentFor(AgentRole.implementer), 'backup');
      final WorkflowAgentSwitched switched = run.history.whereType<WorkflowAgentSwitched>().single;
      expect((switched.fromAgentId, switched.toAgentId), ('implementer', 'backup'));
      expect((await runStates.load('task-1'))!.activeAgents[AgentRole.implementer], 'backup');
    });

    test('asks the user when no fallback is left, then retries', () async {
      int calls = 0;
      final ScriptedAgentAdapter limited = implementer(
        handler: (AgentRunRequest request, ScriptedAgentSession session) {
          if (++calls == 1) {
            throw const ScriptedAgentFailure('429 Too Many Requests', kind: AgentFailureKind.rateLimit);
          }
          return 'T1: done';
        },
      );
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
        planner(),
        limited,
        reviewer(<String>['VERDICT: APPROVED']),
      ]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor());
      answerCheckpoints(run, <(CheckpointDecision, String?)>[(CheckpointDecision.approve, null)]);

      expect((await run.result).status, WorkflowStatus.completed);
      final WorkflowCheckpoint checkpoint = run.history.whereType<WorkflowCheckpointRequested>().single.checkpoint;
      expect(checkpoint.kind, WorkflowCheckpointKind.agentUnavailable);
      expect(checkpoint.title, 'implementer reached a usage limit');
      expect(checkpoint.allowsRevision, isFalse);
    });

    test('ends the workflow when the user cancels after a sign-in failure', () async {
      final ScriptedAgentAdapter signedOut = implementer(handler: (AgentRunRequest request, ScriptedAgentSession session) => throw const ScriptedAgentFailure('Invalid API key · Please run /login', kind: AgentFailureKind.authentication));
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[planner(), signedOut, reviewer(<String>[])]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor());
      run.events.listen((WorkflowEvent event) {
        if (event is WorkflowCheckpointRequested) {
          expect(() => run.resolveCheckpoint(event.checkpoint.id, CheckpointDecision.revise), throwsArgumentError);
          run.resolveCheckpoint(event.checkpoint.id, CheckpointDecision.cancel);
        }
      });

      expect((await run.result).status, WorkflowStatus.cancelled);
      expect(run.history.whereType<WorkflowCheckpointRequested>().single.checkpoint.title, 'implementer needs you to sign in');
    });
  });

  group('checklist', () {
    test('tracks tasks and test cases and blocks approval while a test case is missing', () async {
      final ScriptedAgentAdapter implementerAgent = implementer();
      final ScriptedAgentAdapter reviewerAgent = reviewer(<String>['T1: ok\nTC1: missing — no test asserts the greeting\nVERDICT: APPROVED', 'T1: ok\nTC1: covered\nVERDICT: APPROVED']);
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[planner(), implementerAgent, reviewerAgent]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor());

      final WorkflowTask task = await run.result;

      expect(task.status, WorkflowStatus.completed);
      expect(task.reviewCycle, 1);
      expect(implementerAgent.requests[2].instructions, allOf(contains('TC1'), contains('no test asserts the greeting')));
      expect(reviewerAgent.requests.first.instructions, contains('TC1 [done] hello.txt contains a greeting'));
      expect(run.checklist.items.map((ChecklistItem item) => (item.id, item.status, item.implementedBy, item.reviewedBy)), <(String, ChecklistItemStatus, String?, String?)>[
        ('T1', ChecklistItemStatus.verified, 'implementer', 'reviewer'),
        ('TC1', ChecklistItemStatus.verified, 'implementer', 'reviewer'),
      ]);
      expect(run.history.whereType<WorkflowChecklistUpdated>(), isNotEmpty);
    });

    test('parses plans and reports', () {
      final WorkflowChecklist checklist = WorkflowChecklist.fromPlan('''
Intro
- [ ] **T1**: First task
- [x] Second task without ID
* [ ] TC1. Edge case
- [ ] T1: duplicate is ignored
1. numbered lines are not items
''');

      expect(checklist.items.map((ChecklistItem item) => '${item.id}|${item.kind.name}|${item.title}'), <String>['T1|task|First task', 'T2|task|Second task without ID', 'TC1|testCase|Edge case']);
      expect(checklist.tasks, hasLength(2));
      expect(checklist.testCases, hasLength(1));

      final WorkflowChecklist reported = checklist.start('impl').applyImplementerReport('T1: done\nt2: not done — blocked by API\nTC1 - done', 'impl').applyReviewerReport('- T1: needs changes — off by one\nTC1: covered', 'rev');
      expect(reported.items.map((ChecklistItem item) => '${item.id}:${item.status.name}:${item.note ?? ''}'), <String>['T1:needsChanges:off by one', 'T2:notDone:blocked by API', 'TC1:verified:']);
      expect(reported.needingChanges.single.id, 'T1');
      expect(WorkflowChecklist.fromJson(reported.toJson()).toJson(), reported.toJson());
    });
  });

  group('resume', () {
    Future<void> interruptedAt(WorkflowStatus status, WorkflowRunState state) async {
      final List<WorkflowStatus> path = switch (status) {
        WorkflowStatus.implementing => <WorkflowStatus>[WorkflowStatus.planning, WorkflowStatus.readyForImplementation, WorkflowStatus.implementing],
        WorkflowStatus.reviewing => <WorkflowStatus>[WorkflowStatus.planning, WorkflowStatus.readyForImplementation, WorkflowStatus.implementing, WorkflowStatus.readyForReview, WorkflowStatus.reviewing],
        _ => <WorkflowStatus>[status],
      };
      WorkflowTask task = WorkflowTask.create(id: 'task-1', request: 'Add hello', repositoryPath: await repository.resolveSymbolicLinks(), createdAt: DateTime.now());
      for (final WorkflowStatus next in path) {
        task = task.transitionTo(next, at: DateTime.now());
      }
      await tasks.save(task);
      await settingsStore.saveForTask('task-1', settingsFor());
      await runStates.save('task-1', state);
    }

    test('continues an interrupted implementation with its saved session and plan', () async {
      await interruptedAt(WorkflowStatus.implementing, WorkflowRunState(baselineBranch: 'main', plan: _plan, implementerSession: 'saved-session', checklist: WorkflowChecklist.fromPlan(_plan)));
      final ScriptedAgentAdapter plannerAgent = planner();
      final ScriptedAgentAdapter implementerAgent = implementer();
      final WorkflowOrchestrator orchestrator = orchestratorFor(<AgentAdapter>[
        plannerAgent,
        implementerAgent,
        reviewer(<String>['VERDICT: APPROVED']),
      ]);

      expect(await orchestrator.isInterrupted((await tasks.load('task-1'))!), isTrue);
      final WorkflowRun run = await orchestrator.resume('task-1');

      expect((await run.result).status, WorkflowStatus.completed);
      expect(plannerAgent.requests, isEmpty);
      expect(implementerAgent.requests.first.resumeSessionId, 'saved-session');
      expect(implementerAgent.requests.first.instructions, contains('T1: Add hello.txt'));
    });

    test('goes straight back to review when interrupted while reviewing', () async {
      await interruptedAt(WorkflowStatus.reviewing, WorkflowRunState(baselineBranch: 'main', plan: _plan));
      File(path.join(repository.path, 'hello.txt')).writeAsStringSync('hello\n');
      final ScriptedAgentAdapter implementerAgent = implementer();
      final ScriptedAgentAdapter reviewerAgent = reviewer(<String>['VERDICT: APPROVED']);

      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[planner(), implementerAgent, reviewerAgent]).resume('task-1');

      expect((await run.result).status, WorkflowStatus.completed);
      expect(implementerAgent.requests, isEmpty);
      expect(reviewerAgent.requests.single.instructions, contains('+hello'));
    });

    test('refuses finished, unknown, settings-less, and locked workflows', () async {
      final WorkflowOrchestrator orchestrator = orchestratorFor(<AgentAdapter>[planner(), implementer(), reviewer(<String>[])]);
      await expectLater(orchestrator.resume('missing'), throwsA(isA<WorkflowStartException>()));

      await tasks.save(WorkflowTask.create(id: 'task-1', request: 'x', repositoryPath: repository.path, createdAt: DateTime.now()).transitionTo(WorkflowStatus.cancelled, at: DateTime.now()));
      await expectLater(orchestrator.resume('task-1'), throwsA(isA<WorkflowStartException>().having((WorkflowStartException error) => error.message, 'message', contains('already cancelled'))));

      await tasks.save(WorkflowTask.create(id: 'task-2', request: 'x', repositoryPath: repository.path, createdAt: DateTime.now()).transitionTo(WorkflowStatus.planning, at: DateTime.now()));
      await expectLater(orchestrator.resume('task-2'), throwsA(isA<WorkflowStartException>().having((WorkflowStartException error) => error.message, 'message', contains('settings'))));

      await settingsStore.saveForTask('task-2', settingsFor());
      final Process holder = await Process.start('sleep', <String>['30']);
      addTearDown(holder.kill);
      await writeFileAtomically(File(path.join(workflowTaskDirectory(paths.workflowsDirectory, 'task-2').path, 'run.lock')), '${holder.pid}\n');
      expect(await orchestrator.isInterrupted((await tasks.load('task-2'))!), isFalse);
      await expectLater(orchestrator.resume('task-2'), throwsA(isA<WorkflowStartException>().having((WorkflowStartException error) => error.message, 'message', contains('still running'))));

      holder.kill();
      await holder.exitCode;
      expect(await orchestrator.isInterrupted((await tasks.load('task-2'))!), isTrue);
    });

    test('holds the lock while running and releases it afterwards', () async {
      final Completer<void> release = Completer<void>();
      final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
        planner(
          handler: (AgentRunRequest request, ScriptedAgentSession session) async {
            await release.future;
            return _plan;
          },
        ),
        implementer(),
        reviewer(<String>['VERDICT: APPROVED']),
      ]).start(request: 'Add hello', repositoryPath: repository.path, settings: settingsFor());
      final File lock = File(path.join(workflowTaskDirectory(paths.workflowsDirectory, 'task-1').path, 'run.lock'));

      expect(lock.readAsStringSync().trim(), '$pid');
      release.complete();
      await run.result;
      expect(lock.existsSync(), isFalse);
    });
  });

  test('settings round-trip every new option through JSON', () {
    final WorkflowSettings settings = settingsFor(
      fallbacks: <AgentRole, List<String>>{
        AgentRole.implementer: <String>['backup', 'implementer'],
      },
      requirePlanApproval: true,
      requireChangesApproval: true,
      reviewPlan: true,
      maxTokens: 5000,
      maxRetries: 1,
    ).copyWith(modelOverrides: <AgentRole, String>{AgentRole.planner: 'fast-model'});

    final WorkflowSettings restored = WorkflowSettings.fromJson(settings.toJson());

    expect(restored.toJson(), settings.toJson());
    expect(restored.fallbackAgentIds[AgentRole.implementer], <String>['backup']);
    expect(restored.modelOverrides[AgentRole.planner], 'fast-model');
    expect(restored.allAgentIds, <String>{'planner', 'implementer', 'reviewer', 'backup'});
    expect(
      () => WorkflowSettings.fromJson(<String, Object?>{
        ...settings.toJson(),
        'models': <String, Object?>{'boss': 'x'},
      }),
      throwsFormatException,
    );
    expect(() => WorkflowSettings.fromJson(<String, Object?>{...settings.toJson(), 'reviewPlan': 'yes'}), throwsFormatException);
  });
}
