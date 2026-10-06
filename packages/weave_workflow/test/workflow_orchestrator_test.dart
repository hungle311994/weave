import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/testing.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_git/weave_git.dart';
import 'package:weave_security/weave_security.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

/// Returns the next scripted outcome for each verification command.
final class _FakeVerifier implements VerificationRunner {
  _FakeVerifier(this.outcomes);

  final List<bool> outcomes;
  int runs = 0;

  @override
  Future<VerificationResult> run(VerificationCommand command, {required String workingDirectory}) async {
    final bool passed = runs < outcomes.length ? outcomes[runs] : true;
    runs++;
    return VerificationResult(command: command, exitCode: passed ? 0 : 1, output: passed ? '' : 'test failed', duration: Duration.zero);
  }
}

void main() {
  late Directory temporaryDirectory;
  late Directory repository;
  late WeaveStoragePaths paths;
  late FileWorkflowTaskStore tasks;
  late FileWorkflowArtifactStore artifacts;
  late FileWorkflowSettingsStore settingsStore;

  Future<String> git(List<String> arguments) async {
    final ProcessResult result = await Process.run('git', <String>['-c', 'user.name=Weave Test', '-c', 'user.email=weave@example.com', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', ...arguments], workingDirectory: repository.path);
    if (result.exitCode != 0) {
      fail('git ${arguments.first} failed: ${result.stderr}');
    }
    return result.stdout as String;
  }

  void write(String name, String contents) => File(path.join(repository.path, name)).writeAsStringSync(contents);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-workflow-test-');
    repository = await Directory(path.join(temporaryDirectory.path, 'my repo')).create();
    paths = WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: <String, String>{'WEAVE_HOME': path.join(temporaryDirectory.path, 'weave home')});
    tasks = FileWorkflowTaskStore(workflowsDirectory: paths.workflowsDirectory);
    artifacts = FileWorkflowArtifactStore(workflowsDirectory: paths.workflowsDirectory, redactor: SecretRedactor());
    settingsStore = FileWorkflowSettingsStore(paths: paths);
    await git(<String>['init', '--quiet', '--initial-branch=main']);
    write('README.md', 'weave\n');
    await git(<String>['add', '--all']);
    await git(<String>['commit', '--quiet', '-m', 'Initial commit']);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  WorkflowSettings settingsFor({String planner = 'planner', String implementer = 'implementer', String reviewer = 'reviewer', int verificationCommands = 0, int maxReviewCycles = 3}) => WorkflowSettings(
    assignments: AgentAssignments(plannerAgentId: planner, implementerAgentId: implementer, reviewerAgentId: reviewer),
    verificationCommands: <VerificationCommand>[for (int index = 0; index < verificationCommands; index++) VerificationCommand.parse('check $index')],
    maxReviewCycles: maxReviewCycles,
  );

  WorkflowOrchestrator orchestratorFor(List<AgentAdapter> adapters, {VerificationRunner? verifier, McpRegistry? mcpServers, Map<String, String> environment = const <String, String>{}}) =>
      WorkflowOrchestrator(agents: AgentRegistry(adapters), tasks: tasks, artifacts: artifacts, settingsStore: settingsStore, verifier: verifier ?? _FakeVerifier(<bool>[]), createTaskId: () => 'task-1', mcpServers: mcpServers, environment: environment);

  ScriptedAgentAdapter planner({ScriptedAgentHandler? handler}) => ScriptedAgentAdapter(id: 'planner', handler: handler ?? (AgentRunRequest request, ScriptedAgentSession session) => '1. Add hello.txt');

  ScriptedAgentAdapter implementer({ScriptedAgentHandler? handler}) => ScriptedAgentAdapter(
    id: 'implementer',
    handler:
        handler ??
        (AgentRunRequest request, ScriptedAgentSession session) {
          File(path.join(request.workingDirectory, 'hello.txt')).writeAsStringSync('hello ${request.task.reviewCycle}\n');
          session.write('edited hello.txt\n');
          return 'Added hello.txt';
        },
  );

  ScriptedAgentAdapter reviewer(List<String> verdicts) {
    int reviews = 0;
    return ScriptedAgentAdapter(id: 'reviewer', handler: (AgentRunRequest request, ScriptedAgentSession session) => 'Review ${reviews + 1}\nVERDICT: ${verdicts[reviews++]}');
  }

  List<WorkflowStatus> statusesOf(WorkflowRun run) => <WorkflowStatus>[
    for (final WorkflowEvent event in run.history)
      if (event is WorkflowStatusChanged) event.task.status,
  ];

  test('completes plan, implementation, self-review, verification, and review', () async {
    final ScriptedAgentAdapter implementerAgent = implementer();
    final ScriptedAgentAdapter reviewerAgent = reviewer(<String>['APPROVED']);
    final _FakeVerifier verifier = _FakeVerifier(<bool>[true]);
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[planner(), implementerAgent, reviewerAgent], verifier: verifier).start(request: 'Add a greeting', repositoryPath: repository.path, settings: settingsFor(verificationCommands: 1));

    final WorkflowTask task = await run.result;

    expect(task.status, WorkflowStatus.completed);
    expect(statusesOf(run), <WorkflowStatus>[WorkflowStatus.planning, WorkflowStatus.readyForImplementation, WorkflowStatus.implementing, WorkflowStatus.readyForReview, WorkflowStatus.reviewing, WorkflowStatus.completed]);
    expect(run.history.last, isA<WorkflowFinished>());
    expect(verifier.runs, 1);

    expect(implementerAgent.requests.map((AgentRunRequest request) => request.role), <AgentRole>[AgentRole.implementer, AgentRole.implementer]);
    expect(implementerAgent.requests.last.resumeSessionId, 'implementer-session-1');
    expect(implementerAgent.requests.first.instructions, contains('1. Add hello.txt'));
    final String reviewPrompt = reviewerAgent.requests.single.instructions;
    expect(reviewPrompt, allOf(contains('+hello 0'), contains('PASS `check 0`'), contains('Added hello.txt')));

    expect((await artifacts.readArtifacts('task-1')).map((WorkflowArtifact artifact) => artifact.kind), <WorkflowArtifactKind>[WorkflowArtifactKind.plan, WorkflowArtifactKind.implementation, WorkflowArtifactKind.selfReview, WorkflowArtifactKind.verification, WorkflowArtifactKind.review]);
    expect((await tasks.load('task-1'))!.status, WorkflowStatus.completed);
    expect((await settingsStore.loadForTask('task-1'))!.verificationCommands.single.label, 'check 0');
    final List<WorkflowLogEntry> log = await artifacts.readLog('task-1');
    expect(log.map((WorkflowLogEntry entry) => entry.message), contains('edited hello.txt\n'));
    expect(log.map((WorkflowLogEntry entry) => entry.message).join(), isNot(contains('+hello')));

    expect(Directory(path.join(repository.path, '.agents')).existsSync(), isFalse);
    expect(await git(<String>['status', '--porcelain']), '?? hello.txt\n');
  });

  test('loops back to the implementer with review feedback', () async {
    final ScriptedAgentAdapter implementerAgent = implementer();
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
      planner(),
      implementerAgent,
      reviewer(<String>['CHANGES_REQUESTED', 'APPROVED']),
    ]).start(request: 'Add a greeting', repositoryPath: repository.path, settings: settingsFor());

    final WorkflowTask task = await run.result;

    expect(task.status, WorkflowStatus.completed);
    expect(task.reviewCycle, 1);
    expect(implementerAgent.requests, hasLength(4));
    expect(implementerAgent.requests[2].instructions, allOf(contains('requested changes'), contains('Review 1')));
    expect(implementerAgent.requests[2].resumeSessionId, 'implementer-session-1');
    expect((await artifacts.readArtifacts('task-1')).where((WorkflowArtifact artifact) => artifact.kind == WorkflowArtifactKind.review).map((WorkflowArtifact artifact) => artifact.cycle), <int>[0, 1]);
  });

  test('never approves while verification fails', () async {
    final ScriptedAgentAdapter implementerAgent = implementer();
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
      planner(),
      implementerAgent,
      reviewer(<String>['APPROVED', 'APPROVED']),
    ], verifier: _FakeVerifier(<bool>[false, true])).start(request: 'Add a greeting', repositoryPath: repository.path, settings: settingsFor(verificationCommands: 1));

    final WorkflowTask task = await run.result;

    expect(task.status, WorkflowStatus.completed);
    expect(task.reviewCycle, 1);
    expect(implementerAgent.requests[2].instructions, allOf(contains('Verification failed'), contains('FAIL `check 0`'), contains('test failed')));
  });

  test('treats a missing verdict as requested changes', () async {
    final ScriptedAgentAdapter reviewerAgent = ScriptedAgentAdapter(id: 'reviewer', handler: (AgentRunRequest request, ScriptedAgentSession session) => 'Looks fine to me.');
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[planner(), implementer(), reviewerAgent]).start(request: 'Add a greeting', repositoryPath: repository.path, settings: settingsFor(maxReviewCycles: 1));

    final WorkflowTask task = await run.result;

    expect(task.status, WorkflowStatus.failed);
    expect((run.history.last as WorkflowFinished).reason, 'No approval after 1 review round(s).');
  });

  test('fails after the review round limit', () async {
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
      planner(),
      implementer(),
      reviewer(<String>['CHANGES_REQUESTED', 'CHANGES_REQUESTED']),
    ]).start(request: 'Add a greeting', repositoryPath: repository.path, settings: settingsFor(maxReviewCycles: 2));

    final WorkflowTask task = await run.result;

    expect(task.status, WorkflowStatus.failed);
    expect(task.reviewCycle, 2);
  });

  test('fails when a read-only planner changes the repository', () async {
    final ScriptedAgentAdapter plannerAgent = planner(
      handler: (AgentRunRequest request, ScriptedAgentSession session) {
        File(path.join(request.workingDirectory, 'PLAN.md')).writeAsStringSync('handoff');
        return 'plan';
      },
    );
    final ScriptedAgentAdapter implementerAgent = implementer();
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
      plannerAgent,
      implementerAgent,
      reviewer(<String>['APPROVED']),
    ]).start(request: 'Add a greeting', repositoryPath: repository.path, settings: settingsFor());

    final WorkflowTask task = await run.result;

    expect(task.status, WorkflowStatus.failed);
    expect((run.history.last as WorkflowFinished).reason, contains('planner changed the repository'));
    expect(implementerAgent.requests, isEmpty);
  });

  test('fails when the reviewer edits an already modified file', () async {
    final ScriptedAgentAdapter reviewerAgent = ScriptedAgentAdapter(
      id: 'reviewer',
      handler: (AgentRunRequest request, ScriptedAgentSession session) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        File(path.join(request.workingDirectory, 'hello.txt')).writeAsStringSync('rewritten by the reviewer\n');
        return 'VERDICT: APPROVED';
      },
    );
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[planner(), implementer(), reviewerAgent]).start(request: 'Add a greeting', repositoryPath: repository.path, settings: settingsFor());

    expect((await run.result).status, WorkflowStatus.failed);
    expect((run.history.last as WorkflowFinished).reason, contains('reviewer changed the repository'));
  });

  test('fails when the implementer commits', () async {
    final ScriptedAgentAdapter implementerAgent = implementer(
      handler: (AgentRunRequest request, ScriptedAgentSession session) async {
        if (request.resumeSessionId == null) {
          write('hello.txt', 'hello\n');
          await git(<String>['add', '--all']);
          await git(<String>['commit', '--quiet', '-m', 'Sneaky commit']);
        }
        return 'Committed';
      },
    );
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
      planner(),
      implementerAgent,
      reviewer(<String>['APPROVED']),
    ]).start(request: 'Add a greeting', repositoryPath: repository.path, settings: settingsFor());

    expect((await run.result).status, WorkflowStatus.failed);
    expect((run.history.last as WorkflowFinished).reason, contains('moved HEAD'));
  });

  test('fails when an agent fails', () async {
    final ScriptedAgentAdapter implementerAgent = implementer(handler: (AgentRunRequest request, ScriptedAgentSession session) => throw StateError('rate limited'));
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
      planner(),
      implementerAgent,
      reviewer(<String>['APPROVED']),
    ]).start(request: 'Add a greeting', repositoryPath: repository.path, settings: settingsFor());

    expect((await run.result).status, WorkflowStatus.failed);
    expect((run.history.last as WorkflowFinished).reason, allOf(contains('implementer failed during implement'), contains('rate limited')));
  });

  test('cancels the running agent', () async {
    final Completer<void> started = Completer<void>();
    final ScriptedAgentAdapter implementerAgent = implementer(
      handler: (AgentRunRequest request, ScriptedAgentSession session) async {
        started.complete();
        await Completer<void>().future;
        return 'unreachable';
      },
    );
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
      planner(),
      implementerAgent,
      reviewer(<String>['APPROVED']),
    ]).start(request: 'Add a greeting', repositoryPath: repository.path, settings: settingsFor());
    await started.future;

    await run.cancel();
    final WorkflowTask task = await run.result;

    expect(task.status, WorkflowStatus.cancelled);
    expect((run.history.last as WorkflowFinished).reason, 'Cancelled by user.');
    expect((await tasks.load('task-1'))!.status, WorkflowStatus.cancelled);
  });

  test('forwards approval requests to the running agent', () async {
    final ScriptedAgentAdapter implementerAgent = implementer(
      handler: (AgentRunRequest request, ScriptedAgentSession session) async {
        final ApprovalDecision decision = await session.requestApproval(action: 'network', details: 'Download a dependency');
        return 'Decision: ${decision.name}';
      },
    );
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[
      planner(),
      implementerAgent,
      reviewer(<String>['APPROVED']),
    ]).start(request: 'Add a greeting', repositoryPath: repository.path, settings: settingsFor());
    final StreamSubscription<WorkflowEvent> subscription = run.events.listen((WorkflowEvent event) {
      if (event is WorkflowApprovalRequested) {
        expect(run.pendingApprovals, contains(event.approvalId));
        run.resolveApproval(event.approvalId, ApprovalDecision.deny);
      }
    });

    expect((await run.result).status, WorkflowStatus.completed);
    await subscription.cancel();
    expect((await artifacts.readArtifacts('task-1')).firstWhere((WorkflowArtifact artifact) => artifact.kind == WorkflowArtifactKind.implementation).content, 'Decision: deny');
    expect(run.history.whereType<WorkflowApprovalResolved>(), hasLength(2));
    expect(() => run.resolveApproval('unknown', ApprovalDecision.approve), throwsStateError);
  });

  test('lets one agent play every role', () async {
    int calls = 0;
    final ScriptedAgentAdapter solo = ScriptedAgentAdapter(
      id: 'solo',
      handler: (AgentRunRequest request, ScriptedAgentSession session) {
        calls++;
        return switch (request.role) {
          AgentRole.planner => 'plan',
          AgentRole.implementer => 'done',
          AgentRole.reviewer => 'VERDICT: APPROVED',
        };
      },
    );
    final WorkflowRun run = await orchestratorFor(<AgentAdapter>[solo]).start(
      request: 'Do it',
      repositoryPath: repository.path,
      settings: settingsFor(planner: 'solo', implementer: 'solo', reviewer: 'solo'),
    );

    expect((await run.result).status, WorkflowStatus.completed);
    expect(calls, 4);
  });

  group('MCP servers', () {
    final McpServerDefinition tracker = McpServerDefinition(
      id: 'tracker',
      displayName: 'Tracker',
      transport: McpHttpTransport(url: 'https://tracker.example.com/mcp', headers: <String, String>{'Authorization': r'Bearer ${TRACKER_TOKEN}'}),
    );

    WorkflowSettings withMcp(List<String> ids) => WorkflowSettings(
      assignments: AgentAssignments(plannerAgentId: 'planner', implementerAgentId: 'implementer', reviewerAgentId: 'reviewer'),
      mcpServerIds: ids,
    );

    test('passes resolved servers to every role', () async {
      final ScriptedAgentAdapter plannerAgent = planner();
      final ScriptedAgentAdapter implementerAgent = implementer();
      final ScriptedAgentAdapter reviewerAgent = reviewer(<String>['APPROVED']);
      final WorkflowRun run = await orchestratorFor(
        <AgentAdapter>[plannerAgent, implementerAgent, reviewerAgent],
        mcpServers: McpRegistry.withBuiltIns(customServers: <McpServerDefinition>[tracker]),
        environment: <String, String>{'TRACKER_TOKEN': 'abc123'},
      ).start(request: 'Build https://www.figma.com/design/AbC/Login', repositoryPath: repository.path, settings: withMcp(<String>['figma', 'tracker']));

      expect((await run.result).status, WorkflowStatus.completed);
      for (final AgentRunRequest request in <AgentRunRequest>[...plannerAgent.requests, ...implementerAgent.requests, ...reviewerAgent.requests]) {
        expect(request.mcpServers.map((McpServerDefinition server) => server.id), <String>['figma', 'tracker'], reason: request.role.name);
        expect((request.mcpServers.last.transport as McpHttpTransport).headers['Authorization'], 'Bearer abc123');
      }
      expect((await settingsStore.loadForTask('task-1'))!.mcpServerIds, <String>['figma', 'tracker']);
    });

    test('rejects unknown servers, missing variables, and agents without MCP', () async {
      final McpRegistry registry = McpRegistry.withBuiltIns(customServers: <McpServerDefinition>[tracker]);
      final WorkflowOrchestrator orchestrator = orchestratorFor(<AgentAdapter>[
        planner(),
        implementer(),
        reviewer(<String>['APPROVED']),
      ], mcpServers: registry);

      await expectLater(orchestrator.start(request: 'x', repositoryPath: repository.path, settings: withMcp(<String>['missing'])), throwsA(isA<WorkflowStartException>().having((WorkflowStartException error) => error.message, 'message', contains('Unknown MCP server "missing"'))));
      await expectLater(orchestrator.start(request: 'x', repositoryPath: repository.path, settings: withMcp(<String>['tracker'])), throwsA(isA<WorkflowStartException>().having((WorkflowStartException error) => error.message, 'message', contains('TRACKER_TOKEN'))));

      final ScriptedAgentAdapter noMcp = ScriptedAgentAdapter(id: 'reviewer', supportsMcp: false, handler: (AgentRunRequest request, ScriptedAgentSession session) => 'VERDICT: APPROVED');
      await expectLater(orchestratorFor(<AgentAdapter>[planner(), implementer(), noMcp], mcpServers: registry).start(request: 'x', repositoryPath: repository.path, settings: withMcp(<String>['figma'])), throwsA(isA<WorkflowStartException>().having((WorkflowStartException error) => error.message, 'message', contains('cannot use MCP servers'))));
      expect(await tasks.list(), isEmpty);
    });
  });

  group('start validation', () {
    test('rejects unknown and unavailable agents before creating a task', () async {
      final WorkflowOrchestrator orchestrator = orchestratorFor(<AgentAdapter>[planner(), implementer(), ScriptedAgentAdapter(id: 'reviewer', isAvailable: false, handler: (AgentRunRequest request, ScriptedAgentSession session) => '')]);

      await expectLater(
        orchestrator.start(
          request: 'x',
          repositoryPath: repository.path,
          settings: settingsFor(implementer: 'missing'),
        ),
        throwsA(isA<WorkflowStartException>().having((WorkflowStartException error) => error.message, 'message', contains('Unknown agent "missing"'))),
      );
      await expectLater(orchestrator.start(request: 'x', repositoryPath: repository.path, settings: settingsFor()), throwsA(isA<WorkflowStartException>().having((WorkflowStartException error) => error.message, 'message', contains('not available'))));
      await expectLater(orchestrator.start(request: ' ', repositoryPath: repository.path, settings: settingsFor()), throwsA(isA<WorkflowStartException>()));
      expect(await tasks.list(), isEmpty);
    });

    test('rejects a directory outside any repository', () async {
      final Directory outside = await Directory(path.join(temporaryDirectory.path, 'outside')).create();

      await expectLater(orchestratorFor(<AgentAdapter>[planner(), implementer(), reviewer(<String>[])]).start(request: 'x', repositoryPath: outside.path, settings: settingsFor()), throwsA(isA<GitNotRepositoryException>()));
    });
  });
}
