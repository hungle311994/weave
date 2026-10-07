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

const String _plan = '''
## Tasks
- [ ] T1: Add the endpoint to the backend
## Test cases
- [ ] TC1: The endpoint answers
## Repositories to change
- backend: add the /notes endpoint
''';

void main() {
  late Directory temporaryDirectory;
  late Directory flutter;
  late Directory backend;
  late WeaveStoragePaths paths;

  Future<void> git(Directory repository, List<String> arguments) async {
    final ProcessResult result = await Process.run('git', <String>['-c', 'user.name=Weave Test', '-c', 'user.email=weave@example.com', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', ...arguments], workingDirectory: repository.path);
    if (result.exitCode != 0) {
      fail('git ${arguments.first} failed: ${result.stderr}');
    }
  }

  Future<Directory> repository(String name) async {
    final Directory directory = await Directory(path.join(temporaryDirectory.path, name)).create();
    await git(directory, <String>['init', '--quiet', '--initial-branch=main']);
    File(path.join(directory.path, 'README.md')).writeAsStringSync('# $name\n');
    await git(directory, <String>['add', '--all']);
    await git(directory, <String>['commit', '--quiet', '-m', 'Initial commit']);
    return directory;
  }

  /// Git reports real paths (`/private/var/...` on macOS), and so does Weave.
  String root(Directory directory) => directory.resolveSymbolicLinksSync();

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-multi-repo-');
    flutter = await repository('flutter');
    backend = await repository('backend');
    paths = WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: <String, String>{'WEAVE_HOME': path.join(temporaryDirectory.path, 'home')});
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  WorkflowOrchestrator orchestrator(List<AgentAdapter> agents) => WorkflowOrchestrator(
    agents: AgentRegistry(agents),
    tasks: FileWorkflowTaskStore(workflowsDirectory: paths.workflowsDirectory),
    artifacts: FileWorkflowArtifactStore(workflowsDirectory: paths.workflowsDirectory, redactor: SecretRedactor()),
    createTaskId: () => 'task-1',
  );

  final WorkflowSettings settings = WorkflowSettings(
    assignments: AgentAssignments(plannerAgentId: 'planner', implementerAgentId: 'implementer', reviewerAgentId: 'reviewer'),
  );

  ScriptedAgentAdapter agent(String id, FutureOr<String> Function(AgentRunRequest request) handler, {List<AgentRunRequest>? requests}) => ScriptedAgentAdapter(id: id, handler: (AgentRunRequest request, ScriptedAgentSession session) => handler(request));

  /// Answers the repositories checkpoint with [answer] and returns it.
  Future<WorkflowCheckpoint> answerRepositories(WorkflowRun run, void Function(WorkflowCheckpoint checkpoint) answer) async {
    final WorkflowCheckpoint checkpoint = (await run.events.firstWhere((WorkflowEvent event) => event is WorkflowCheckpointRequested && event.checkpoint.kind == WorkflowCheckpointKind.repositories) as WorkflowCheckpointRequested).checkpoint;
    answer(checkpoint);
    return checkpoint;
  }

  test('asks which repositories may be edited after planning, and only lets the implementer edit those', () async {
    final List<AgentRunRequest> requests = <AgentRunRequest>[];
    final WorkflowRun run = await orchestrator(<AgentAdapter>[
      agent('planner', (AgentRunRequest request) {
        requests.add(request);
        return _plan;
      }),
      agent('implementer', (AgentRunRequest request) {
        requests.add(request);
        File(path.join(backend.path, 'notes.dart')).writeAsStringSync('// notes endpoint\n');
        return 'T1: done\nTC1: done';
      }),
      agent('reviewer', (AgentRunRequest request) {
        requests.add(request);
        return 'T1: ok\nTC1: covered\nVERDICT: APPROVED';
      }),
    ]).start(request: 'Using the backend repo, add an API for the flutter app', repositoryPath: flutter.path, additionalRepositoryPaths: <String>[backend.path], settings: settings);

    final WorkflowCheckpoint checkpoint = await answerRepositories(run, (WorkflowCheckpoint checkpoint) => run.resolveCheckpoint(checkpoint.id, CheckpointDecision.approve, editableRepositories: <String>{root(backend)}));
    final WorkflowTask task = await run.result;

    expect(task.status, WorkflowStatus.completed);
    expect(task.additionalRepositoryPaths, <String>[root(backend)]);
    expect(checkpoint.repositories.map((WorkflowRepositoryChoice choice) => (choice.name, choice.proposed, choice.reason)), <(String, bool, String?)>[('flutter', true, 'Mentioned in your request'), ('backend', true, 'add the /notes endpoint')], reason: 'the request names both; the plan explains the backend');

    final AgentRunRequest plan = requests.firstWhere((AgentRunRequest request) => request.role == AgentRole.planner);
    expect(plan.additionalDirectories.single.writable, isFalse, reason: 'the planner only reads other repositories');
    expect(plan.instructions, contains('- backend: ${root(backend)}'));
    expect(plan.instructions, contains('## Repositories to change'));

    final AgentRunRequest implement = requests.firstWhere((AgentRunRequest request) => request.role == AgentRole.implementer);
    expect(implement.additionalDirectories.single.writable, isTrue);
    expect(implement.instructions, contains('- backend: ${root(backend)} — may edit'));
    expect(implement.instructions, contains('- flutter: ${root(flutter)} — read only'));

    final AgentRunRequest review = requests.lastWhere((AgentRunRequest request) => request.role == AgentRole.reviewer);
    expect(review.instructions, contains('### Repository backend (${root(backend)})'));
    expect(review.instructions, contains('notes endpoint'));
  });

  test('fails when the implementer edits a repository the user did not allow', () async {
    final WorkflowRun run = await orchestrator(<AgentAdapter>[
      agent('planner', (AgentRunRequest request) => _plan),
      agent('implementer', (AgentRunRequest request) {
        File(path.join(flutter.path, 'stray.dart')).writeAsStringSync('// not allowed\n');
        return 'T1: done';
      }),
      agent('reviewer', (AgentRunRequest request) => 'VERDICT: APPROVED'),
    ]).start(request: 'Add the API', repositoryPath: flutter.path, additionalRepositoryPaths: <String>[backend.path], settings: settings);

    await answerRepositories(run, (WorkflowCheckpoint checkpoint) => run.resolveCheckpoint(checkpoint.id, CheckpointDecision.approve, editableRepositories: <String>{root(backend)}));
    final WorkflowTask task = await run.result;

    expect(task.status, WorkflowStatus.failed);
    expect(run.history.whereType<WorkflowFinished>().single.reason, 'The implementer changed flutter, which you did not allow it to edit.');
  });

  test('fails when a read-only role changes any of the repositories', () async {
    final WorkflowRun run = await orchestrator(<AgentAdapter>[
      agent('planner', (AgentRunRequest request) {
        File(path.join(backend.path, 'planner.txt')).writeAsStringSync('oops\n');
        return _plan;
      }),
      agent('implementer', (AgentRunRequest request) => 'T1: done'),
      agent('reviewer', (AgentRunRequest request) => 'VERDICT: APPROVED'),
    ]).start(request: 'Add the API', repositoryPath: flutter.path, additionalRepositoryPaths: <String>[backend.path], settings: settings);

    final WorkflowTask task = await run.result;

    expect(task.status, WorkflowStatus.failed);
    expect(run.history.whereType<WorkflowFinished>().single.reason, 'The planner changed backend although its role is read-only.');
  });

  test('approving without a choice keeps the plan proposal; revising asks the planner again', () async {
    final List<String> plannerPrompts = <String>[];
    final WorkflowRun run = await orchestrator(<AgentAdapter>[
      agent('planner', (AgentRunRequest request) {
        plannerPrompts.add(request.instructions);
        return plannerPrompts.length == 1 ? '## Tasks\n- [ ] T1: Something' : _plan;
      }),
      agent('implementer', (AgentRunRequest request) {
        File(path.join(backend.path, 'notes.dart')).writeAsStringSync('// notes\n');
        return 'T1: done';
      }),
      agent('reviewer', (AgentRunRequest request) => 'VERDICT: APPROVED'),
    ]).start(request: 'Add the API', repositoryPath: flutter.path, additionalRepositoryPaths: <String>[backend.path], settings: settings);

    final List<WorkflowCheckpoint> checkpoints = <WorkflowCheckpoint>[];
    final StreamSubscription<WorkflowEvent> subscription = run.events.listen((WorkflowEvent event) {
      if (event case WorkflowCheckpointRequested(:final WorkflowCheckpoint checkpoint)) {
        checkpoints.add(checkpoint);
        run.resolveCheckpoint(checkpoint.id, checkpoints.length == 1 ? CheckpointDecision.revise : CheckpointDecision.approve, feedback: 'Change the backend instead');
      }
    });
    final WorkflowTask task = await run.result;
    await subscription.cancel();

    expect(checkpoints.first.repositories.where((WorkflowRepositoryChoice choice) => choice.proposed).map((WorkflowRepositoryChoice choice) => choice.name), <String>['flutter'], reason: 'a plan that names no repository proposes the working directory');
    expect(plannerPrompts.last, contains('Change the backend instead'));
    expect(checkpoints.last.repositories.where((WorkflowRepositoryChoice choice) => choice.proposed).map((WorkflowRepositoryChoice choice) => choice.name), <String>['backend']);
    expect(task.status, WorkflowStatus.completed, reason: 'approve without a choice allowed the proposed backend');
  });

  test('an approval must name repositories of the workflow', () async {
    final WorkflowRun run = await orchestrator(<AgentAdapter>[
      agent('planner', (AgentRunRequest request) => _plan),
      agent('implementer', (AgentRunRequest request) => 'T1: done'),
      agent('reviewer', (AgentRunRequest request) => 'VERDICT: APPROVED'),
    ]).start(request: 'Add the API', repositoryPath: flutter.path, additionalRepositoryPaths: <String>[backend.path], settings: settings);

    await answerRepositories(run, (WorkflowCheckpoint checkpoint) {
      expect(() => run.resolveCheckpoint(checkpoint.id, CheckpointDecision.approve, editableRepositories: <String>{}), throwsArgumentError);
      expect(() => run.resolveCheckpoint(checkpoint.id, CheckpointDecision.approve, editableRepositories: <String>{'/elsewhere'}), throwsArgumentError);
      run.resolveCheckpoint(checkpoint.id, CheckpointDecision.cancel);
    });
    expect((await run.result).status, WorkflowStatus.cancelled);
  });

  group('helpers', () {
    test('plannedRepositories reads names, folder names and full paths, ignoring others', () {
      const List<String> repositories = <String>['/p/flutter', '/p/backend', '/p/admin'];
      final Map<String, String?> planned = plannedRepositories('## Tasks\n- [ ] T1: x\n## Repositories to change\n- `backend` — add endpoint\n- /p/flutter: call it\n- unknown: nothing\n## Notes\n- admin: not in the section', repositories);

      expect(planned, <String, String?>{'/p/backend': 'add endpoint', '/p/flutter': 'call it'});
    });

    test('mentionedRepositories finds repositories named in the request as whole words', () {
      const List<String> repositories = <String>['/p/famnucleus-flutter', '/p/famnucleus-backend', '/p/admin'];

      expect(mentionedRepositories('Using famnucleus-backend, add an API for the Famnucleus-Flutter app', repositories), <String>{'/p/famnucleus-flutter', '/p/famnucleus-backend'});
      expect(mentionedRepositories('Update the administrator page', repositories), isEmpty, reason: 'admin inside administrator is not a mention');
      expect(mentionedRepositories('Fix /p/admin please', repositories), <String>{'/p/admin'});
    });

    test('repositoryNames disambiguates folders with the same name', () {
      expect(repositoryNames(<String>['/a/app', '/b/app', '/c/api']), <String, String>{'/a/app': 'a/app', '/b/app': 'b/app', '/c/api': 'api'});
    });

    test('run state keeps baselines and the editable repositories', () {
      final WorkflowRunState state = WorkflowRunState(
        repositoryBaselines: <String, WorkflowRepositoryHead>{'/p/backend': const WorkflowRepositoryHead(branch: 'main', commit: 'abc')},
        editableRepositories: <String>['/p/backend'],
      );
      final WorkflowRunState restored = WorkflowRunState.fromJson(state.toJson());

      expect(restored.repositoryBaselines['/p/backend']?.commit, 'abc');
      expect(restored.editableRepositories, <String>['/p/backend']);
      expect(WorkflowRunState.fromJson(WorkflowRunState().toJson()).editableRepositories, isNull, reason: 'single-repository state is unchanged');
    });
  });
}
