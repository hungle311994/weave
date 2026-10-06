import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';

final DateTime _timestamp = DateTime.utc(2026, 10, 6);

AgentRunRequest _request(AgentRole role, {String workingDirectory = '/repo', String? resumeSessionId}) => AgentRunRequest(
  task: WorkflowTask.create(id: 'task-1', request: 'Build Weave', repositoryPath: workingDirectory, createdAt: DateTime.utc(2026)),
  role: role,
  instructions: 'Do the work',
  workingDirectory: workingDirectory,
  resumeSessionId: resumeSessionId,
);

List<AgentEvent> _parse(ClaudeCodeOutputParser parser, List<Object> records) => <AgentEvent>[for (final Object record in records) ...parser.parseLine(record is String ? record : jsonEncode(record), _timestamp)];

void main() {
  group('arguments', () {
    test('restricts planners and reviewers to reading', () {
      final AgentDefinition definition = AgentDefinition.claudeCode();

      for (final AgentRole role in <AgentRole>[AgentRole.planner, AgentRole.reviewer]) {
        expect(definition.buildArguments(_request(role)), <String>['--print', '--output-format', 'stream-json', '--verbose', '--restricted', '--permission-prompts', 'none', '--strict-mcp-config', '--permission-mode', 'manual', '--disallowedTools', 'Edit,Write,NotebookEdit']);
      }
    });

    test('lets implementers edit and resume a session', () {
      final List<String> arguments = AgentDefinition.claudeCode(model: 'sonnet').buildArguments(_request(AgentRole.implementer, resumeSessionId: 'session-1'));

      expect(arguments, <String>['--print', '--output-format', 'stream-json', '--verbose', '--restricted', '--permission-prompts', 'none', '--strict-mcp-config', '--permission-mode', 'acceptEdits', '--model', 'sonnet', '--resume', 'session-1']);
      expect(arguments, isNot(contains('bypassPermissions')));
      expect(arguments, isNot(contains('--dangerously-skip-permissions')));
    });
  });

  group('ClaudeCodeOutputParser', () {
    test('maps a successful session to output and completion', () {
      final ClaudeCodeOutputParser parser = ClaudeCodeOutputParser();

      final List<AgentEvent> events = _parse(parser, <Object>[
        <String, String>{'type': 'system', 'subtype': 'init', 'session_id': 'session-1'},
        <String, Object>{
          'type': 'assistant',
          'session_id': 'session-1',
          'message': <String, List<Map<String, Object>>>{
            'content': <Map<String, Object>>[
              <String, String>{'type': 'text', 'text': 'Reading the code.'},
              <String, Object>{
                'type': 'tool_use',
                'name': 'Read',
                'input': <String, String>{'file_path': '/repo/lib/a b.dart'},
              },
              <String, String>{'type': 'thinking', 'thinking': 'private'},
            ],
          },
        },
        <String, Object>{
          'type': 'user',
          'message': <String, List<Map<String, String>>>{
            'content': <Map<String, String>>[
              <String, String>{'type': 'tool_result', 'content': 'secret file contents'},
            ],
          },
        },
        <String, Object>{'type': 'result', 'subtype': 'success', 'is_error': false, 'result': 'Plan:\n1. Do it', 'session_id': 'session-1', 'permission_denials': <Object>[]},
      ]);
      final AgentEvent terminal = parser.finish(0, _timestamp);

      expect(events.cast<AgentOutputEvent>().map((AgentOutputEvent event) => event.text), <String>['Reading the code.\n', '  tool Read /repo/lib/a b.dart\n']);
      expect(terminal, isA<AgentCompletedEvent>().having((AgentCompletedEvent event) => event.summary, 'summary', 'Plan:\n1. Do it').having((AgentCompletedEvent event) => event.sessionId, 'sessionId', 'session-1'));
    });

    test('reports sandbox denials and error results', () {
      final ClaudeCodeOutputParser parser = ClaudeCodeOutputParser();

      final List<AgentEvent> events = _parse(parser, <Object>[
        <String, Object>{
          'type': 'result',
          'subtype': 'error_max_turns',
          'is_error': true,
          'session_id': 'session-1',
          'permission_denials': <Map<String, String>>[
            <String, String>{'tool_name': 'Bash'},
          ],
        },
      ]);

      expect((events.single as AgentOutputEvent).text, '1 tool call(s) were denied by the sandbox.\n');
      expect(parser.finish(1, _timestamp), isA<AgentFailedEvent>().having((AgentFailedEvent event) => event.message, 'message', 'Claude Code reported an error.'));
    });

    test('fails when the process exits without a result', () {
      final ClaudeCodeOutputParser parser = ClaudeCodeOutputParser();
      _parse(parser, <Object>['Error: not logged in']);

      final AgentFailedEvent terminal = parser.finish(1, _timestamp) as AgentFailedEvent;

      expect(terminal.message, contains('before reporting a result'));
      expect(terminal.exitCode, 1);
    });

    test('fails a success result when the process exits non-zero', () {
      final ClaudeCodeOutputParser parser = ClaudeCodeOutputParser();
      _parse(parser, <Object>[
        <String, String>{'type': 'result', 'subtype': 'success', 'result': 'Done'},
      ]);

      expect(parser.finish(2, _timestamp), isA<AgentFailedEvent>());
    });
  });

  test('runs a claude executable end to end', () async {
    final Directory temporaryDirectory = await Directory.systemTemp.createTemp('weave-claude-test-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final File executable = File(path.join(temporaryDirectory.path, 'claude'));
    final String stdinFile = path.join(temporaryDirectory.path, 'stdin');
    await executable.writeAsString(
      '#!/bin/sh\n'
      'cat > "$stdinFile"\n'
      'echo \'{"type":"system","subtype":"init","session_id":"s-9"}\'\n'
      'echo \'{"type":"result","subtype":"success","is_error":false,'
      '"result":"Done","session_id":"s-9"}\'\n',
    );
    await Process.run('chmod', <String>['755', executable.path]);

    final CommandAgentAdapter adapter = CommandAgentAdapter(AgentDefinition.claudeCode(), environment: <String, String>{'PATH': '${temporaryDirectory.path}:/usr/bin:/bin', 'HOME': temporaryDirectory.path});
    final AgentExecution execution = await adapter.start(_request(AgentRole.implementer, workingDirectory: temporaryDirectory.path));
    final List<AgentEvent> events = await execution.events.toList();

    expect(events.last, isA<AgentCompletedEvent>().having((AgentCompletedEvent event) => event.summary, 'summary', 'Done').having((AgentCompletedEvent event) => event.sessionId, 'sessionId', 's-9'));
    expect(await File(stdinFile).readAsString(), 'Do the work');
  });
}
