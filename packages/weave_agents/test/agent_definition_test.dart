import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_security/weave_security.dart';

AgentRunRequest _request(AgentRole role, {String workingDirectory = '/repo', String instructions = 'Do the work', String? resumeSessionId}) => AgentRunRequest(
  task: WorkflowTask.create(id: 'task-1', request: 'Build Weave', repositoryPath: workingDirectory, createdAt: DateTime.utc(2026)),
  role: role,
  instructions: instructions,
  workingDirectory: workingDirectory,
  resumeSessionId: resumeSessionId,
);

AgentDefinition _custom({List<String> arguments = const <String>['run'], Map<SandboxMode, List<String>>? sandboxArguments, List<String> resumeArguments = const <String>['--session', '{sessionId}'], String executable = 'my-agent', String? model}) => AgentDefinition(
  id: 'my-agent',
  displayName: 'My Agent',
  executable: executable,
  arguments: arguments,
  sandboxArguments:
      sandboxArguments ??
      const <SandboxMode, List<String>>{
        SandboxMode.readOnly: <String>['--read-only'],
        SandboxMode.workspaceWrite: <String>['--write', '{workingDirectory}'],
      },
  resumeArguments: resumeArguments,
  installCommand: const <String>['brew', 'install', 'my-agent'],
  model: model,
);

void main() {
  group('AgentDefinition', () {
    test('builds arguments in a fixed order with placeholders', () {
      final AgentDefinition definition = _custom(model: 'large');

      expect(definition.buildArguments(_request(AgentRole.reviewer)), <String>['run', '--read-only', '--model', 'large']);
      expect(definition.buildArguments(_request(AgentRole.implementer, workingDirectory: '/my repo/{model}', resumeSessionId: 'session-1')), <String>['run', '--write', '/my repo/{model}', '--model', 'large', '--session', 'session-1']);
      expect(definition.takesPromptArgument, isFalse);
    });

    test('passes the prompt as one argument when requested', () {
      final AgentDefinition definition = _custom(arguments: const <String>['ask', '--prompt={prompt}']);
      final String instructions = 'Fix "it"; rm -rf / \$(whoami)';

      final List<String> arguments = definition.buildArguments(_request(AgentRole.planner, instructions: instructions));

      expect(definition.takesPromptArgument, isTrue);
      expect(arguments, <String>['ask', '--prompt=$instructions', '--read-only']);
    });

    test('rejects invalid definitions', () {
      expect(() => _custom(executable: 'bin/agent'), throwsArgumentError);
      expect(() => _custom(executable: ' '), throwsArgumentError);
      expect(() => _custom(arguments: const <String>['{unknown}']), throwsArgumentError);
      expect(
        () => _custom(
          sandboxArguments: const <SandboxMode, List<String>>{
            SandboxMode.readOnly: <String>['--read-only'],
          },
        ),
        throwsArgumentError,
      );
      expect(() => AgentDefinition(id: 'Bad Id', displayName: 'Bad', executable: 'agent', sandboxArguments: const <SandboxMode, List<String>>{SandboxMode.readOnly: <String>[], SandboxMode.workspaceWrite: <String>[]}), throwsArgumentError);
    });

    test('round-trips through JSON', () {
      for (final AgentDefinition definition in <AgentDefinition>[_custom(model: 'large'), AgentDefinition.codex(), AgentDefinition.claudeCode(model: 'sonnet')]) {
        final AgentDefinition restored = AgentDefinition.fromJson(definition.toJson());

        expect(restored.toJson(), definition.toJson());
        expect(restored.buildArguments(_request(AgentRole.implementer)), definition.buildArguments(_request(AgentRole.implementer)));
      }
    });

    test('supports multiple provider-published installation options and legacy commands', () {
      final AgentDefinition codex = AgentDefinition.codex();
      final AgentDefinition legacy = _custom();

      expect(codex.installOptions.map((AgentInstallOption option) => option.commandText), <String>['brew install --cask codex', 'npm install -g @openai/codex@latest']);
      expect(codex.installCommandText, 'brew install --cask codex');
      expect(legacy.installOptions.single.label, 'Terminal');
      expect(legacy.installCommandText, 'brew install my-agent');
    });

    test('rejects malformed JSON definitions', () {
      final Map<String, Object?> valid = _custom().toJson();

      for (final Map<String, Object?> invalid in <Map<String, Object?>>[
        <String, Object?>{...valid, 'id': 42},
        <String, Object?>{...valid, 'arguments': 'run'},
        <String, Object?>{...valid, 'sandboxArguments': <String, Object?>{}},
        <String, Object?>{...valid, 'outputFormat': 'xml'},
        <String, Object?>{...valid, 'executable': '../agent'},
        <String, Object?>{...valid, 'installOptions': 'npm'},
      ]) {
        expect(() => AgentDefinition.fromJson(invalid), throwsFormatException, reason: '$invalid');
      }
    });

    test('changes the model without changing anything else', () {
      final AgentDefinition definition = AgentDefinition.codex().withModel('fast');

      expect(definition.model, 'fast');
      expect(definition.id, 'codex');
      expect(definition.withModel(null).model, isNull);
      expect(definition.withModel(null).installCommand, definition.installCommand);
    });
  });

  group('AgentRegistry', () {
    test('includes built-in presets and custom agents', () {
      final AgentRegistry registry = AgentRegistry.fromDefinitions(customDefinitions: <AgentDefinition>[_custom()]);

      expect(registry.ids, containsAll(<String>['codex', 'claude-code', 'my-agent']));
      expect(registry.require('my-agent').displayName, 'My Agent');
      expect(registry['missing'], isNull);
      expect(() => registry.require('missing'), throwsA(isA<StateError>().having((StateError error) => error.message, 'message', contains('my-agent'))));
    });

    test('lets a custom definition replace a preset', () {
      final AgentRegistry registry = AgentRegistry.fromDefinitions(customDefinitions: <AgentDefinition>[AgentDefinition.codex(model: 'pinned')]);

      final CommandAgentAdapter codex = registry.require('codex') as CommandAgentAdapter;
      expect(codex.definition.model, 'pinned');
      expect(registry.ids.where((String id) => id == 'codex'), hasLength(1));
    });

    test('reads and writes agents.json', () {
      final String source = encodeAgentDefinitions(<AgentDefinition>[_custom()]);

      expect(decodeAgentDefinitions(source).single.toJson(), _custom().toJson());
      expect(() => decodeAgentDefinitions('{"schemaVersion": 2, "agents": []}'), throwsFormatException);
      expect(() => decodeAgentDefinitions(encodeAgentDefinitions(<AgentDefinition>[_custom(), _custom()])), throwsFormatException);
    });
  });

  group('TextOutputParser', () {
    test('streams lines and summarizes the whole output', () {
      final TextOutputParser parser = TextOutputParser();
      final DateTime timestamp = DateTime.utc(2026);

      final List<AgentEvent> events = <AgentEvent>[...parser.parseLine('first', timestamp), ...parser.parseLine('', timestamp), ...parser.parseLine('  second', timestamp)];

      expect(events.cast<AgentOutputEvent>().map((AgentOutputEvent event) => event.text), <String>['first\n', '  second\n']);
      expect((parser.finish(0, timestamp) as AgentCompletedEvent).summary, 'first\n\n  second');
      expect(parser.finish(3, timestamp), isA<AgentFailedEvent>());
    });
  });

  test('runs a custom text agent with the prompt as an argument', () async {
    final Directory temporaryDirectory = await Directory.systemTemp.createTemp('weave-custom-agent-test-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final File executable = File(path.join(temporaryDirectory.path, 'echo-agent'));
    await executable.writeAsString('#!/bin/sh\nfor argument in "\$@"; do echo "[\$argument]"; done\n');
    await Process.run('chmod', <String>['755', executable.path]);

    final CommandAgentAdapter adapter = CommandAgentAdapter(
      AgentDefinition(
        id: 'echo',
        displayName: 'Echo',
        executable: executable.path,
        arguments: const <String>['{prompt}'],
        sandboxArguments: const <SandboxMode, List<String>>{
          SandboxMode.readOnly: <String>['read only'],
          SandboxMode.workspaceWrite: <String>['write'],
        },
      ),
      environment: <String, String>{'PATH': '/usr/bin:/bin', 'HOME': temporaryDirectory.path},
    );
    final AgentExecution execution = await adapter.start(_request(AgentRole.planner, workingDirectory: temporaryDirectory.path, instructions: 'plan; echo injected'));
    final List<AgentEvent> events = await execution.events.toList();

    expect((events.last as AgentCompletedEvent).summary, '[plan; echo injected]\n[read only]');
  });

  group('additional repositories', () {
    AgentRunRequest request(AgentRole role, List<AgentDirectoryAccess> directories) => AgentRunRequest(
      task: WorkflowTask.create(id: 'task-1', request: 'Add the API', repositoryPath: '/projects/flutter', createdAt: DateTime.utc(2026)),
      role: role,
      instructions: 'Do the work',
      workingDirectory: '/projects/flutter',
      additionalDirectories: directories,
    );

    test('Claude Code adds every other repository; Codex only the ones it may edit', () {
      final List<AgentDirectoryAccess> directories = <AgentDirectoryAccess>[AgentDirectoryAccess(path: '/projects/backend', writable: true), AgentDirectoryAccess(path: '/projects/admin', writable: false)];

      final List<String> claude = AgentDefinition.claudeCode().buildArguments(request(AgentRole.implementer, directories));
      expect(claude.join(' '), contains('--add-dir /projects/backend --add-dir /projects/admin'));
      final List<String> codex = AgentDefinition.codex().buildArguments(request(AgentRole.implementer, directories));
      expect(codex.join(' '), contains('--add-dir /projects/backend'));
      expect(codex, isNot(contains('/projects/admin')), reason: 'Codex reads outside its workspace already');
    });

    test('a read-only role can never be given a writable repository', () {
      expect(() => request(AgentRole.reviewer, <AgentDirectoryAccess>[AgentDirectoryAccess(path: '/projects/backend', writable: true)]), throwsArgumentError);
      expect(request(AgentRole.planner, <AgentDirectoryAccess>[AgentDirectoryAccess(path: '/projects/backend', writable: false)]).additionalDirectories.single.writable, isFalse);
    });

    test('the directory arguments are agent data that survive agents.json and a model change', () {
      final AgentDefinition claude = AgentDefinition.claudeCode();
      final AgentDefinition restored = AgentDefinition.fromJson(jsonDecode(jsonEncode(claude.toJson())) as Map<String, Object?>);

      expect(restored.readableDirectoryArguments, <String>['--add-dir', '{directory}']);
      expect(restored.writableDirectoryArguments, <String>['--add-dir', '{directory}']);
      expect(claude.withModel('opus').readableDirectoryArguments, claude.readableDirectoryArguments);
    });
  });

  test('presets name their vendor and brand mark as data, which survive agents.json', () {
    expect((AgentDefinition.codex().vendor, AgentDefinition.codex().brand), ('OpenAI', 'openai'));
    expect((AgentDefinition.claudeCode().vendor, AgentDefinition.claudeCode().brand), ('Anthropic', 'anthropic'));
    final AgentDefinition restored = AgentDefinition.fromJson(jsonDecode(jsonEncode(AgentDefinition.codex().toJson())) as Map<String, Object?>);
    expect((restored.vendor, restored.brand), ('OpenAI', 'openai'));
    expect(AgentDefinition.codex().withModel('o3').brand, 'openai');
  });
}
