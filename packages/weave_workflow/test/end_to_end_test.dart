import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_security/weave_security.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

/// A command-line "agent" that answers by role, read from the prompt on stdin.
const String _agentScript = r'''#!/bin/sh
if [ "$1" = "--version" ]; then echo "script-agent 1.0.0"; exit 0; fi
prompt=$(cat)
case "$prompt" in
  *"You are the planner"*)
    echo "1. Create notes.txt with a greeting."
    ;;
  *"You are the implementer"*)
    if [ -f notes.txt ]; then echo "hello again" > notes.txt; else echo "hello" > notes.txt; fi
    echo "Wrote notes.txt"
    ;;
  *"Review the changes you just made"*)
    echo "notes.txt is complete."
    ;;
  *"You are the reviewer"*)
    case "$prompt" in
      *"+hello again"*) echo "Looks good."; echo "VERDICT: APPROVED" ;;
      *) echo "Say hello again."; echo "VERDICT: CHANGES_REQUESTED" ;;
    esac
    ;;
  *)
    echo "unexpected prompt" >&2
    exit 3
    ;;
esac
''';

void main() {
  test('runs a full workflow through real processes, Git, verification, and storage', () async {
    final Directory temporaryDirectory = await Directory.systemTemp.createTemp('weave-e2e-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final Directory repository = await Directory(path.join(temporaryDirectory.path, 'project')).create();
    final File agent = File(path.join(temporaryDirectory.path, 'bin', 'script-agent'));
    await agent.parent.create();
    await agent.writeAsString(_agentScript);
    expect((await Process.run('chmod', <String>['755', agent.path])).exitCode, 0);
    expect((await Process.run('git', <String>['init', '--quiet', '--initial-branch=main'], workingDirectory: repository.path)).exitCode, 0);

    final Map<String, String> environment = <String, String>{'PATH': '${agent.parent.path}:/usr/bin:/bin', 'HOME': temporaryDirectory.path};
    final WeaveStoragePaths paths = WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: <String, String>{'WEAVE_HOME': path.join(temporaryDirectory.path, 'weave')});
    final WeaveServices services = WeaveServices(
      paths: paths,
      agents: AgentRegistry.fromDefinitions(
        customDefinitions: <AgentDefinition>[
          AgentDefinition(
            id: 'script',
            displayName: 'Script Agent',
            executable: 'script-agent',
            sandboxArguments: const <SandboxMode, List<String>>{SandboxMode.readOnly: <String>[], SandboxMode.workspaceWrite: <String>[]},
          ),
        ],
        environment: environment,
      ),
      environment: environment,
    );

    final WorkflowRun run = await services.createOrchestrator().start(
      request: 'Add a greeting file',
      repositoryPath: repository.path,
      settings: WorkflowSettings(
        assignments: AgentAssignments(plannerAgentId: 'script', implementerAgentId: 'script', reviewerAgentId: 'script'),
        verificationCommands: <VerificationCommand>[VerificationCommand.parse('ls notes.txt')],
      ),
    );
    final WorkflowTask task = await run.result;

    expect(task.status, WorkflowStatus.completed, reason: (run.history.last as WorkflowFinished).reason);
    expect(task.reviewCycle, 1);
    expect(File(path.join(repository.path, 'notes.txt')).readAsStringSync(), 'hello again\n');

    final List<WorkflowArtifact> artifacts = await services.artifacts.readArtifacts(task.id);
    expect(artifacts.map((WorkflowArtifact artifact) => '${artifact.cycle}:${artifact.kind.name}'), <String>[
      '0:plan',
      '0:implementation',
      '0:selfReview',
      '0:verification',
      '0:review',
      '1:implementation',
      '1:selfReview',
      '1:verification',
      '1:review',
    ]);
    expect(artifacts.last.content, contains('VERDICT: APPROVED'));
    expect(artifacts.firstWhere((WorkflowArtifact artifact) => artifact.kind == WorkflowArtifactKind.verification).content, contains('PASS `ls notes.txt`'));
    expect((await services.tasks.list()).single.id, task.id);
    expect((await services.artifacts.readLog(task.id)).map((WorkflowLogEntry entry) => entry.message), contains('Wrote notes.txt\n'));

    // Weave keeps every piece of state outside the repository.
    final List<String> repositoryEntries = repository.listSync().map((FileSystemEntity entity) => path.basename(entity.path)).toList()..sort();
    expect(repositoryEntries, <String>['.git', 'notes.txt']);
  });
}
