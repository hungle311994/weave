import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';

final DateTime _timestamp = DateTime.utc(2026, 10, 6);

AgentRunRequest _request(AgentRole role, {String workingDirectory = '/repo with space', String? resumeSessionId}) => AgentRunRequest(
  task: WorkflowTask.create(id: 'task-1', request: 'Build Weave', repositoryPath: workingDirectory, createdAt: DateTime.utc(2026)),
  role: role,
  instructions: 'Do the work',
  workingDirectory: workingDirectory,
  resumeSessionId: resumeSessionId,
);

List<AgentEvent> _parse(CodexOutputParser parser, List<Object> records) => <AgentEvent>[for (final Object record in records) ...parser.parseLine(record is String ? record : jsonEncode(record), _timestamp)];

void main() {
  group('arguments', () {
    test('runs planners and reviewers in a read-only sandbox', () {
      final AgentDefinition definition = AgentDefinition.codex();

      for (final AgentRole role in <AgentRole>[AgentRole.planner, AgentRole.reviewer]) {
        expect(definition.buildArguments(_request(role)), <String>['exec', '--json', '--color', 'never', '--cd', '/repo with space', '--sandbox', 'read-only', '-']);
      }
    });

    test('runs implementers with workspace write access and resume', () {
      final List<String> arguments = AgentDefinition.codex(model: 'gpt-5-codex').buildArguments(_request(AgentRole.implementer, resumeSessionId: 'thread-1'));

      expect(arguments, <String>['exec', '--json', '--color', 'never', '--cd', '/repo with space', '--sandbox', 'workspace-write', '--model', 'gpt-5-codex', 'resume', 'thread-1', '-']);
      expect(arguments, isNot(contains('danger-full-access')));
    });
  });

  group('CodexOutputParser', () {
    test('maps a successful turn to output and completion', () {
      final CodexOutputParser parser = CodexOutputParser();

      final List<AgentEvent> events = _parse(parser, <Object>[
        <String, String>{'type': 'thread.started', 'thread_id': 'thread-1'},
        <String, String>{'type': 'turn.started'},
        <String, Object>{
          'type': 'item.completed',
          'item': <String, String>{'type': 'reasoning', 'text': 'thinking'},
        },
        <String, Object>{
          'type': 'item.started',
          'item': <String, String>{'type': 'command_execution', 'command': 'ls -la'},
        },
        <String, Object>{
          'type': 'item.completed',
          'item': <String, Object>{'type': 'command_execution', 'command': 'ls -la', 'aggregated_output': 'secret file contents', 'exit_code': 0},
        },
        <String, Object>{
          'type': 'item.completed',
          'item': <String, Object>{
            'type': 'file_change',
            'changes': <Map<String, String>>[
              <String, String>{'path': 'lib/a b.dart', 'kind': 'update'},
            ],
          },
        },
        <String, Object>{
          'type': 'item.completed',
          'item': <String, String>{'type': 'agent_message', 'text': 'Plan:\n1. Do it'},
        },
        <String, Object>{
          'type': 'turn.completed',
          'usage': <String, int>{'input_tokens': 1},
        },
      ]);
      final AgentEvent terminal = parser.finish(0, _timestamp);

      final String output = events.cast<AgentOutputEvent>().map((AgentOutputEvent event) => event.text).join();
      expect(
        output,
        '\$ ls -la\n  exit 0\n  update lib/a b.dart\n'
        'Plan:\n1. Do it\n',
      );
      expect(output, isNot(contains('secret file contents')));
      expect(terminal, isA<AgentCompletedEvent>().having((AgentCompletedEvent event) => event.summary, 'summary', 'Plan:\n1. Do it').having((AgentCompletedEvent event) => event.sessionId, 'sessionId', 'thread-1'));
    });

    test('reports failed turns and top-level errors', () {
      final CodexOutputParser failedTurn = CodexOutputParser();
      _parse(failedTurn, <Object>[
        <String, Object>{
          'type': 'turn.failed',
          'error': <String, String>{'message': 'Rate limited'},
        },
      ]);
      expect((failedTurn.finish(1, _timestamp) as AgentFailedEvent).message, 'Rate limited');

      final CodexOutputParser error = CodexOutputParser();
      final List<AgentEvent> events = _parse(error, <Object>[
        <String, String>{'type': 'error', 'message': 'stream disconnected'},
      ]);
      expect((events.single as AgentOutputEvent).channel, AgentOutputChannel.stderr);
      expect(error.finish(1, _timestamp), isA<AgentFailedEvent>());
    });

    test('fails when the process exits before the turn completes', () {
      final CodexOutputParser parser = CodexOutputParser();
      _parse(parser, <Object>[
        <String, String>{'type': 'thread.started', 'thread_id': 'thread-1'},
      ]);

      final AgentFailedEvent terminal = parser.finish(0, _timestamp) as AgentFailedEvent;

      expect(terminal.message, contains('before finishing'));
    });

    test('passes plain text lines through and ignores blank lines', () {
      final List<AgentEvent> events = _parse(CodexOutputParser(), <Object>['Reading prompt from stdin...', '   ', '{not json']);

      expect(events.cast<AgentOutputEvent>().map((AgentOutputEvent event) => event.text), <String>['Reading prompt from stdin...\n', '{not json\n']);
    });
  });

  test('runs a codex executable end to end', () async {
    final Directory temporaryDirectory = await Directory.systemTemp.createTemp('weave-codex-test-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final File executable = File(path.join(temporaryDirectory.path, 'codex'));
    final String argumentsFile = path.join(temporaryDirectory.path, 'arguments');
    final String stdinFile = path.join(temporaryDirectory.path, 'stdin');
    await executable.writeAsString(
      '#!/bin/sh\n'
      'printf "%s\\n" "\$@" > "$argumentsFile"\n'
      'cat > "$stdinFile"\n'
      'echo \'{"type":"thread.started","thread_id":"thread-9"}\'\n'
      'echo \'{"type":"item.completed","item":{"type":"agent_message",'
      '"text":"Done"}}\'\n'
      'echo \'{"type":"turn.completed"}\'\n',
    );
    await Process.run('chmod', <String>['755', executable.path]);

    final CommandAgentAdapter adapter = CommandAgentAdapter(AgentDefinition.codex(), environment: <String, String>{'PATH': '${temporaryDirectory.path}:/usr/bin:/bin', 'HOME': temporaryDirectory.path});
    final AgentExecution execution = await adapter.start(_request(AgentRole.planner, workingDirectory: temporaryDirectory.path));
    final List<AgentEvent> events = await execution.events.toList();

    expect(events.last, isA<AgentCompletedEvent>().having((AgentCompletedEvent event) => event.summary, 'summary', 'Done').having((AgentCompletedEvent event) => event.sessionId, 'sessionId', 'thread-9'));
    expect(await File(stdinFile).readAsString(), 'Do the work');
    expect(await File(argumentsFile).readAsLines(), containsAllInOrder(<String>['exec', '--json', '--sandbox', 'read-only', '-']));
  });
}
