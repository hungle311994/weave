import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_security/weave_security.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

void main() {
  late Directory temporaryDirectory;
  late WeaveServices services;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-services-test-');
    final WeaveStoragePaths paths = WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: <String, String>{'WEAVE_HOME': temporaryDirectory.path});
    services = WeaveServices(paths: paths, agents: AgentRegistry(const <AgentAdapter>[]), environment: const <String, String>{});
    await services.tasks.save(WorkflowTask.create(id: 'wf-1', request: 'Add notes', repositoryPath: path.join(temporaryDirectory.path, 'repo'), createdAt: DateTime.utc(2026, 10, 7)));
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('deleteWorkflow removes the workflow from storage', () async {
    await services.deleteWorkflow('wf-1');

    expect(await services.tasks.list(), isEmpty);
    expect(await workflowTaskDirectory(services.paths.workflowsDirectory, 'wf-1').exists(), isFalse);
  });

  test('deleteWorkflow refuses while another Weave process runs the workflow', () async {
    final Process other = await Process.start('sleep', <String>['30']);
    addTearDown(other.kill);
    await File(path.join(workflowTaskDirectory(services.paths.workflowsDirectory, 'wf-1').path, 'run.lock')).writeAsString('${other.pid}\n');

    await expectLater(services.deleteWorkflow('wf-1'), throwsA(isA<StateError>()));
    expect(await services.tasks.load('wf-1'), isNotNull, reason: 'nothing is deleted');
  });

  test('custom agents are saved to and removed from agents.json, and reload', () async {
    final AgentDefinition custom = AgentDefinition(
      id: 'my-agent',
      displayName: 'My Agent',
      executable: 'my-agent',
      vendor: 'Acme',
      sandboxArguments: const <SandboxMode, List<String>>{
        SandboxMode.readOnly: <String>['--read-only'],
        SandboxMode.workspaceWrite: <String>[],
      },
    );
    await saveCustomAgent(services.paths, custom);
    await saveCustomAgent(services.paths, custom.withModel('large'));

    final List<AgentDefinition> saved = await loadCustomAgents(services.paths);
    expect(saved.single.model, 'large', reason: 'saving the same ID replaces it');
    expect(saved.single.vendor, 'Acme');
    await services.reloadAgents();
    expect(services.agents['my-agent'], isNotNull);

    await removeCustomAgent(services.paths, 'my-agent');
    await services.reloadAgents();
    expect(services.agents['my-agent'], isNull);
    expect(await loadCustomAgents(services.paths), isEmpty);
  });

  group('agent accounts', () {
    test('an account runs as its agent with its own configuration folder', () async {
      final AgentAccount account = await addAgentAccount(services.paths, agentId: 'claude-code', name: 'Work', takenIds: const <String>{});
      expect(account.id, 'claude-code-work');
      expect(await Directory(agentAccountDirectory(services.paths, account.id)).exists(), isTrue);

      final AgentRegistry registry = await loadAgentRegistry(services.paths, environment: const <String, String>{});
      final CommandAgentAdapter adapter = registry.require('claude-code-work') as CommandAgentAdapter;
      expect(adapter.displayName, 'Claude Code · Work');
      expect(adapter.account?.agentId, 'claude-code');
      expect(adapter.definition.environment, <String, String>{'CLAUDE_CONFIG_DIR': agentAccountDirectory(services.paths, 'claude-code-work')});
      expect(registry.ids, containsAll(<String>['claude-code', 'codex']), reason: 'the default sign-ins stay');
    });

    test('IDs stay unique, and removing an account deletes its folder', () async {
      final AgentAccount first = await addAgentAccount(services.paths, agentId: 'codex', name: 'Work', takenIds: const <String>{});
      final AgentAccount second = await addAgentAccount(services.paths, agentId: 'codex', name: 'Work', takenIds: const <String>{});
      final AgentAccount clash = await addAgentAccount(services.paths, agentId: 'codex', name: 'Team', takenIds: const <String>{'codex-team'});
      expect(<String>[first.id, second.id, clash.id], <String>['codex-work', 'codex-work-2', 'codex-team-2']);

      await removeAgentAccount(services.paths, 'codex-work');
      expect((await loadAgentAccounts(services.paths)).map((AgentAccount account) => account.id), <String>['codex-work-2', 'codex-team-2']);
      expect(await Directory(agentAccountDirectory(services.paths, 'codex-work')).exists(), isFalse);
    });

    test('accounts of a removed or account-less agent are skipped', () async {
      await addAgentAccount(services.paths, agentId: 'gone', name: 'Work', takenIds: const <String>{});
      await saveCustomAgent(
        services.paths,
        AgentDefinition(id: 'plain', displayName: 'Plain', executable: 'plain', sandboxArguments: const <SandboxMode, List<String>>{SandboxMode.readOnly: <String>[], SandboxMode.workspaceWrite: <String>[]}),
      );
      await addAgentAccount(services.paths, agentId: 'plain', name: 'Work', takenIds: const <String>{});

      final AgentRegistry registry = await loadAgentRegistry(services.paths, environment: const <String, String>{});
      expect(registry.ids, isNot(contains('gone-work')));
      expect(registry.ids, isNot(contains('plain-work')));
    });
  });
}
