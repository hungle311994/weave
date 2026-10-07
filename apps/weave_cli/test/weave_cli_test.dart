import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/testing.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_cli/weave_cli.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

final class _PassingVerifier implements VerificationRunner {
  final List<String> commands = <String>[];

  @override
  Future<VerificationResult> run(VerificationCommand command, {required String workingDirectory}) async {
    commands.add(command.label);
    return VerificationResult(command: command, exitCode: 0, output: '', duration: Duration.zero);
  }
}

void main() {
  late Directory temporaryDirectory;
  late Directory repository;
  late WeaveStoragePaths paths;
  late StringBuffer out;
  late StringBuffer error;
  late StreamController<String> input;
  late StreamController<void> interrupts;
  late _PassingVerifier verifier;

  ScriptedAgentAdapter solo({ScriptedAgentHandler? implement, bool isAvailable = true}) => ScriptedAgentAdapter(
    id: 'solo',
    displayName: 'Solo Agent',
    isAvailable: isAvailable,
    handler: (AgentRunRequest request, ScriptedAgentSession session) async => switch (request.role) {
      AgentRole.planner => 'Plan: add notes.txt',
      AgentRole.implementer => implement == null ? _writeNotes(request, session) : await implement(request, session),
      AgentRole.reviewer => 'Fine.\nVERDICT: APPROVED',
    },
  );

  Future<int> weave(List<String> arguments, {List<AgentAdapter>? agents}) async {
    final WeaveServices services = WeaveServices(paths: paths, agents: AgentRegistry(agents ?? <AgentAdapter>[solo()]), mcp: await loadMcpRegistry(paths), environment: Platform.environment);
    return runWeaveCli(
      arguments,
      services: services,
      console: CliConsole(out: out, error: error, input: input.stream, interrupts: () => interrupts.stream),
      currentDirectory: repository.path,
      verifier: verifier,
    );
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-cli-test-');
    repository = await Directory(path.join(temporaryDirectory.path, 'repo')).create();
    paths = WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: <String, String>{'WEAVE_HOME': path.join(temporaryDirectory.path, 'home')});
    out = StringBuffer();
    error = StringBuffer();
    input = StreamController<String>();
    interrupts = StreamController<void>.broadcast();
    verifier = _PassingVerifier();
    final ProcessResult init = await Process.run('git', <String>['init', '--quiet', '--initial-branch=main'], workingDirectory: repository.path);
    expect(init.exitCode, 0);
  });

  tearDown(() async {
    // Closing an unlistened single-subscription controller never completes.
    unawaited(input.close());
    await interrupts.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('runs a workflow and shows it afterwards', () async {
    final int exitCode = await weave(<String>['run', '--verify', 'fvm dart test', 'Add', 'notes']);

    expect(exitCode, ExitCodes.success, reason: '$out\n$error');
    expect(out.toString(), allOf(contains('== planning'), contains('[implementer] wrote notes.txt'), contains('[verify] PASS fvm dart test'), contains('Finished: completed')));
    expect(verifier.commands, <String>['fvm dart test']);
    expect(File(path.join(repository.path, 'notes.txt')).existsSync(), isTrue);

    final String id = RegExp(r'Workflow (\S+) in').firstMatch(out.toString())!.group(1)!;
    out.clear();
    expect(await weave(<String>['list']), ExitCodes.success);
    expect(out.toString(), allOf(contains(id), contains('completed'), contains('Add notes')));

    out.clear();
    expect(await weave(<String>['show', '--log', id]), ExitCodes.success);
    expect(out.toString(), allOf(contains('## plan (round 0)'), contains('Plan: add notes.txt'), contains('## review (round 0)'), contains('## log'), contains('Solo Agent (solo)')));
  });

  test('asks the user to answer approval requests', () async {
    final ScriptedAgentAdapter agent = solo(
      implement: (AgentRunRequest request, ScriptedAgentSession session) async {
        final ApprovalDecision decision = await session.requestApproval(action: 'network', details: 'Fetch a package');
        return 'decision ${decision.name}';
      },
    );
    // The implementer asks once while implementing and once in self-review.
    input
      ..add('y')
      ..add('no');

    final int exitCode = await weave(<String>['run', 'Add notes'], agents: <AgentAdapter>[agent]);

    expect(exitCode, ExitCodes.success, reason: '$out\n$error');
    expect(out.toString(), allOf(contains('approval needed: network'), contains('Approve? [y/N]'), contains(': approve'), contains(': deny')));
  });

  test('cancels the workflow on Ctrl+C', () async {
    final Completer<void> started = Completer<void>();
    final ScriptedAgentAdapter agent = solo(
      implement: (AgentRunRequest request, ScriptedAgentSession session) async {
        started.complete();
        await Completer<void>().future;
        return 'never';
      },
    );
    unawaited(started.future.then((void _) => interrupts.add(null)));

    final int exitCode = await weave(<String>['run', 'Add notes'], agents: <AgentAdapter>[agent]);

    expect(exitCode, ExitCodes.cancelled);
    expect(out.toString(), allOf(contains('Cancelling...'), contains('Finished: cancelled')));
  });

  test('returns a failure exit code when the workflow fails', () async {
    final ScriptedAgentAdapter agent = solo(implement: (AgentRunRequest request, ScriptedAgentSession session) => throw StateError('quota exceeded'));

    expect(await weave(<String>['run', 'Add notes'], agents: <AgentAdapter>[agent]), ExitCodes.failure);
    expect(out.toString(), contains('quota exceeded'));
  });

  test('saves and applies repository defaults', () async {
    expect(await weave(<String>['config', '--agent', 'solo', '--verify', 'fvm dart analyze', '--max-reviews', '2']), ExitCodes.success);
    expect(out.toString(), allOf(contains('Saved defaults'), contains('fvm dart analyze'), contains('up to 2')));

    out.clear();
    expect(await weave(<String>['config']), ExitCodes.success);
    expect(out.toString(), allOf(contains('Defaults for'), contains('fvm dart analyze')));

    expect(await weave(<String>['run', 'Add notes']), ExitCodes.success);
    expect(verifier.commands, <String>['fvm dart analyze']);

    out.clear();
    expect(await weave(<String>['config', '--clear-verify']), ExitCodes.success);
    expect(out.toString(), contains('(none)'));
  });

  test('reports usage errors', () async {
    expect(await weave(<String>['run']), ExitCodes.usage);
    expect(await weave(<String>['run', '--planner', 'missing', 'x']), ExitCodes.usage);
    expect(error.toString(), contains('Unknown agent "missing"'));
    expect(await weave(<String>['config', '--max-reviews', '0']), ExitCodes.usage);
    expect(await weave(<String>['run', '--verify', 'a && b', 'x']), ExitCodes.usage);
    expect(await weave(<String>['show']), ExitCodes.usage);
    expect(await weave(<String>['unknown']), ExitCodes.usage);
  });

  test('reports missing workflows, repositories, and agents', () async {
    expect(await weave(<String>['show', 'missing']), ExitCodes.failure);
    expect(error.toString(), contains('No workflow with ID missing'));

    final Directory outside = await Directory(path.join(temporaryDirectory.path, 'outside')).create();
    expect(await weave(<String>['run', '--repo', outside.path, 'x']), ExitCodes.failure);
    expect(error.toString(), contains('not inside a Git repository'));

    expect(await weave(<String>['run', 'x'], agents: <AgentAdapter>[solo(isAvailable: false)]), ExitCodes.failure);
    expect(error.toString(), contains('No coding agent is available'));
  });

  test('lists agents and checks the setup', () async {
    expect(await weave(<String>['agents']), ExitCodes.success);
    expect(out.toString(), allOf(contains('solo'), contains('Solo Agent'), contains('agents.json')));

    out.clear();
    expect(await weave(<String>['doctor']), ExitCodes.success);
    expect(out.toString(), allOf(contains('Git:     git version'), contains('ok      solo')));

    expect(await weave(<String>['doctor'], agents: <AgentAdapter>[solo(isAvailable: false)]), ExitCodes.failure);
  });

  group('MCP', () {
    const String figmaRequest = 'Build the login screen from https://www.figma.com/design/AbC123/Login?node-id=1-2';

    test('offers an MCP server for a Figma link and enables the chosen one', () async {
      final ScriptedAgentAdapter agent = solo();
      input.add('2');

      expect(await weave(<String>['run', figmaRequest], agents: <AgentAdapter>[agent]), ExitCodes.success, reason: '$out\n$error');

      expect(out.toString(), allOf(contains('1) Figma (figma)'), contains('2) Figma (desktop app) (figma-desktop)'), contains('Enabled Figma (desktop app)'), contains('mcp         Figma (desktop app) (figma-desktop)')));
      expect(agent.requests.map((AgentRunRequest request) => request.mcpServers.single.id).toSet(), <String>{'figma-desktop'});
    });

    test('continues without MCP when the offer is skipped', () async {
      final ScriptedAgentAdapter agent = solo();
      input.add('');

      expect(await weave(<String>['run', figmaRequest], agents: <AgentAdapter>[agent]), ExitCodes.success);
      expect(out.toString(), contains('Continuing without MCP.'));
      expect(agent.requests.every((AgentRunRequest request) => request.mcpServers.isEmpty), isTrue);

      out.clear();
      expect(await weave(<String>['run', '--no-mcp-prompt', figmaRequest], agents: <AgentAdapter>[agent]), ExitCodes.success);
      expect(out.toString(), isNot(contains('MCP server can open')));
    });

    test('does not ask again when a matching server is already enabled', () async {
      expect(await weave(<String>['config', '--mcp', 'figma']), ExitCodes.success);
      out.clear();

      expect(await weave(<String>['run', figmaRequest]), ExitCodes.success);
      expect(out.toString(), allOf(isNot(contains('MCP server can open')), contains('mcp         Figma (figma)')));

      out.clear();
      expect(await weave(<String>['config', '--clear-mcp']), ExitCodes.success);
      expect(out.toString(), contains('mcp         (none)'));
    });

    test('adds, lists, and removes custom servers', () async {
      expect(await weave(<String>['mcp', 'add', 'tracker', '--name', 'Tracker', '--url', 'https://tracker.example.com/mcp', '--header', r'Authorization=Bearer ${TRACKER_TOKEN}', '--link', r'https://tracker\.example\.com/issues/\d+']), ExitCodes.success);
      expect(await weave(<String>['mcp', 'add', 'local', '--command', 'npx', '--arg', '-y', '--arg', 'local-mcp', '--env', 'MODE=read-only']), ExitCodes.success);

      out.clear();
      expect(await weave(<String>['mcp', 'list']), ExitCodes.success);
      expect(out.toString(), allOf(contains('figma'), contains('Tracker — https://tracker.example.com/mcp'), contains('local — npx -y local-mcp'), contains('mcp.json')));
      expect(File(mcpFilePath(paths)).readAsStringSync(), contains(r'${TRACKER_TOKEN}'));

      expect(await weave(<String>['mcp', 'remove', 'local']), ExitCodes.success);
      expect(await weave(<String>['mcp', 'remove', 'figma']), ExitCodes.failure);
      expect(error.toString(), contains('built-in presets'));
      expect((await loadCustomMcpServers(paths)).map((McpServerDefinition server) => server.id), <String>['tracker']);
    });

    test('rejects invalid MCP options', () async {
      expect(await weave(<String>['run', '--mcp', 'missing', 'x']), ExitCodes.usage);
      expect(error.toString(), contains('Unknown MCP server "missing"'));
      expect(await weave(<String>['mcp', 'add', 'x']), ExitCodes.usage);
      expect(await weave(<String>['mcp', 'add', 'x', '--url', 'https://a.dev', '--command', 'npx']), ExitCodes.usage);
      expect(await weave(<String>['mcp', 'add', 'x', '--url', 'ftp://a.dev']), ExitCodes.usage);
      expect(await weave(<String>['mcp', 'add', 'x', '--command', 'npx', '--env', 'novalue']), ExitCodes.usage);
    });
  });

  group('commit', () {
    Future<void> configureIdentity() async {
      for (final List<String> setting in <List<String>>[
        <String>['user.name', 'Weave Test'],
        <String>['user.email', 'weave@example.com'],
        <String>['commit.gpgsign', 'false'],
        <String>['core.hooksPath', '/dev/null'],
      ]) {
        expect((await Process.run('git', <String>['config', ...setting], workingDirectory: repository.path)).exitCode, 0);
      }
    }

    Future<String> completeWorkflow() async {
      expect(await weave(<String>['run', 'Add notes for the team']), ExitCodes.success);
      return RegExp(r'Workflow (\S+) in').firstMatch(out.toString())!.group(1)!;
    }

    test('commits a completed workflow after approval', () async {
      await configureIdentity();
      final String id = await completeWorkflow();
      out.clear();
      input.add('y');

      expect(await weave(<String>['commit', id]), ExitCodes.success, reason: '$out\n$error');

      expect(out.toString(), allOf(contains('Commit 1 file to main'), contains('  notes.txt'), contains('Add notes for the team'), contains('Committed ')));
      final ProcessResult log = await Process.run('git', <String>['log', '-1', '--format=%B'], workingDirectory: repository.path);
      expect(log.stdout as String, contains('Created by Weave workflow $id.'));
    });

    test('does nothing when the commit is not approved', () async {
      await configureIdentity();
      final String id = await completeWorkflow();
      out.clear();
      input.add('n');

      expect(await weave(<String>['commit', '-m', 'Custom message', id]), ExitCodes.failure);

      expect(out.toString(), allOf(contains('Custom message'), contains('Commit cancelled')));
      final ProcessResult status = await Process.run('git', <String>['status', '--porcelain'], workingDirectory: repository.path);
      expect(status.stdout as String, '?? notes.txt\n');
    });

    test('rejects unknown and unfinished workflows', () async {
      expect(await weave(<String>['commit', 'missing']), ExitCodes.failure);
      expect(error.toString(), contains('No workflow with ID missing'));

      final ScriptedAgentAdapter failing = solo(implement: (AgentRunRequest request, ScriptedAgentSession session) => throw StateError('broken'));
      expect(await weave(<String>['run', 'Add notes'], agents: <AgentAdapter>[failing]), ExitCodes.failure);
      final String id = RegExp(r'Workflow (\S+) in').firstMatch(out.toString())!.group(1)!;
      expect(await weave(<String>['commit', id]), ExitCodes.failure);
      expect(error.toString(), contains('Only completed workflows can be committed'));
    });
  });

  group('checkpoints, checklist, and resume', () {
    const String checklistPlan = '## Tasks\n- [ ] T1: Add notes.txt\n## Test cases\n- [ ] TC1: notes.txt exists';

    ScriptedAgentAdapter planningAgent({List<String>? plannerPrompts}) => ScriptedAgentAdapter(
      id: 'solo',
      displayName: 'Solo Agent',
      usage: const AgentUsage(inputTokens: 10, outputTokens: 5),
      handler: (AgentRunRequest request, ScriptedAgentSession session) => switch (request.role) {
        AgentRole.planner => () {
          plannerPrompts?.add(request.instructions);
          return checklistPlan;
        }(),
        AgentRole.implementer => '${_writeNotes(request, session)}\nT1: done\nTC1: done',
        AgentRole.reviewer => 'T1: ok\nTC1: covered\nVERDICT: APPROVED',
      },
    );

    test('asks for plan approval and passes revision feedback to the planner', () async {
      final List<String> plannerPrompts = <String>[];
      input
        ..add('r')
        ..add('Mention the README')
        ..add('a');

      expect(
        await weave(<String>['run', '--approve-plan', 'Add notes'], agents: <AgentAdapter>[planningAgent(plannerPrompts: plannerPrompts)]),
        ExitCodes.success,
        reason: '$out\n$error',
      );

      expect(out.toString(), allOf(contains('== Approve the plan'), contains('- [ ] T1: Add notes.txt'), contains('[a]pprove, [r]evise, or [c]ancel?'), contains('What should change?')));
      expect(plannerPrompts, hasLength(2));
      expect(plannerPrompts.last, contains('Mention the README'));
      expect(out.toString(), allOf(contains('[checklist] 2 of 2 done'), contains('solo finished plan — 15 tokens'), contains('Usage: 75 tokens')));
    });

    test('runs with another repository and asks which repositories may be edited', () async {
      final Directory backend = await Directory(path.join(temporaryDirectory.path, 'backend')).create();
      expect((await Process.run('git', <String>['init', '--quiet', '--initial-branch=main'], workingDirectory: backend.path)).exitCode, 0);
      final List<AgentRunRequest> implementerRequests = <AgentRunRequest>[];
      final ScriptedAgentAdapter agent = ScriptedAgentAdapter(
        id: 'solo',
        displayName: 'Solo Agent',
        handler: (AgentRunRequest request, ScriptedAgentSession session) => switch (request.role) {
          AgentRole.planner => '$checklistPlan\n## Repositories to change\n- backend: add notes.txt',
          AgentRole.implementer => () {
            implementerRequests.add(request);
            File(path.join(backend.path, 'notes.txt')).writeAsStringSync('notes\n');
            return 'T1: done\nTC1: done';
          }(),
          AgentRole.reviewer => 'T1: ok\nTC1: covered\nVERDICT: APPROVED',
        },
      );
      input.add('a');

      expect(await weave(<String>['run', '--also', backend.path, 'Add notes to the backend'], agents: <AgentAdapter>[agent]), ExitCodes.success, reason: '$out\n$error');

      expect(out.toString(), allOf(contains('== Allow edits to these repositories?'), contains('- backend ('), contains('the plan changes it — add notes.txt'), contains('- repo ('), contains('read only')));
      expect(implementerRequests, hasLength(2), reason: 'implement and self-review');
      expect(implementerRequests.map((AgentRunRequest request) => request.additionalDirectories.single.writable), everyElement(isTrue), reason: 'approve allowed the proposed backend');
      expect(File(path.join(backend.path, 'notes.txt')).existsSync(), isTrue);
    });

    test('cancels at a checkpoint when input ends', () async {
      unawaited(input.close());
      expect(await weave(<String>['run', '--approve-changes', 'Add notes'], agents: <AgentAdapter>[planningAgent()]), ExitCodes.cancelled);
      expect(out.toString(), contains('== Approve the changes before review'));
    });

    test('shows the checklist and usage of a finished workflow', () async {
      expect(await weave(<String>['run', 'Add notes'], agents: <AgentAdapter>[planningAgent()]), ExitCodes.success);
      final String id = RegExp(r'Workflow (\S+) in').firstMatch(out.toString())!.group(1)!;
      out.clear();

      expect(await weave(<String>['show', id], agents: <AgentAdapter>[planningAgent()]), ExitCodes.success);

      expect(out.toString(), allOf(contains('Usage:      60 tokens'), contains('T1    verified     Add notes.txt (by solo, reviewed by solo)'), contains('TC1   verified     notes.txt exists')));
    });

    test('lists and resumes an interrupted workflow', () async {
      final WorkflowTask task = WorkflowTask.create(id: 'wf-interrupted', request: 'Add notes', repositoryPath: await repository.resolveSymbolicLinks(), createdAt: DateTime.now()).transitionTo(WorkflowStatus.planning, at: DateTime.now());
      await FileWorkflowTaskStore(workflowsDirectory: paths.workflowsDirectory).save(task);
      await FileWorkflowSettingsStore(paths: paths).saveForTask(
        task.id,
        WorkflowSettings(
          assignments: AgentAssignments(plannerAgentId: 'solo', implementerAgentId: 'solo', reviewerAgentId: 'solo'),
        ),
      );

      expect(await weave(<String>['list']), ExitCodes.success);
      expect(out.toString(), allOf(contains('planning (interrupted)'), contains('weave resume <workflow-id>')));

      out.clear();
      expect(await weave(<String>['resume', task.id], agents: <AgentAdapter>[planningAgent()]), ExitCodes.success, reason: '$out\n$error');
      expect(out.toString(), allOf(contains('Resuming workflow wf-interrupted (planning)'), contains('Finished: completed')));

      expect(await weave(<String>['resume', task.id]), ExitCodes.failure);
      expect(error.toString(), contains('already completed'));
      expect(await weave(<String>['resume']), ExitCodes.usage);
    });

    test('saves models, fallbacks, checkpoints, and budgets as defaults', () async {
      final ScriptedAgentAdapter backup = ScriptedAgentAdapter(id: 'backup', handler: (AgentRunRequest request, ScriptedAgentSession session) => '');
      expect(
        await weave(<String>['config', '--model', 'planner=fast', '--fallback', 'implementer=backup', '--approve-plan', '--review-plan', '--max-tokens', '50000'], agents: <AgentAdapter>[solo(), backup]),
        ExitCodes.success,
      );
      expect(out.toString(), allOf(contains('model       planner: fast'), contains('fallback    implementer: backup'), contains('checkpoints reviewer checks the plan, you approve the plan'), contains('budget      50000 tokens')));

      out.clear();
      expect(await weave(<String>['config', '--no-approve-plan', '--max-tokens', '0'], agents: <AgentAdapter>[solo(), backup]), ExitCodes.success);
      expect(out.toString(), allOf(contains('checkpoints reviewer checks the plan'), contains('budget      no token limit'), contains('model       planner: fast')));

      expect(await weave(<String>['config', '--fallback', 'boss=backup']), ExitCodes.usage);
      expect(await weave(<String>['config', '--fallback', 'implementer=ghost']), ExitCodes.usage);
      expect(await weave(<String>['config', '--max-tokens', '-1']), ExitCodes.usage);
    });
  });

  test('lists nothing before the first workflow', () async {
    expect(await weave(<String>['list']), ExitCodes.success);
    expect(out.toString(), contains('No workflows yet'));
  });
}

String _writeNotes(AgentRunRequest request, ScriptedAgentSession session) {
  File(path.join(request.workingDirectory, 'notes.txt')).writeAsStringSync('notes\n');
  session.write('wrote notes.txt\n');
  return 'Added notes.txt';
}
