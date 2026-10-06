import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_security/weave_security.dart';

/// Emits each stdout line and completes with the last one on exit code 0.
final class _LineParser implements AgentOutputParser {
  String? _lastLine;

  @override
  Iterable<AgentEvent> parseLine(String line, DateTime timestamp) {
    if (line.trim().isEmpty) {
      return const <AgentEvent>[];
    }
    _lastLine = line;
    return <AgentEvent>[AgentOutputEvent(timestamp: timestamp, text: '$line\n')];
  }

  @override
  AgentEvent finish(int exitCode, DateTime timestamp) => exitCode == 0 ? AgentCompletedEvent(timestamp: timestamp, summary: _lastLine ?? 'done') : AgentFailedEvent(timestamp: timestamp, message: 'Exited with $exitCode.', exitCode: exitCode);
}

CommandAgentAdapter _fakeAdapter(Map<String, String> environment) => CommandAgentAdapter(
  AgentDefinition(
    id: 'fake',
    displayName: 'Fake agent',
    executable: 'fake-agent',
    sandboxArguments: const <SandboxMode, List<String>>{
      SandboxMode.readOnly: <String>['--sandbox', 'readOnly'],
      SandboxMode.workspaceWrite: <String>['--sandbox', 'workspaceWrite'],
    },
  ),
  environment: environment,
);

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-agents-process-test-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  Future<ProcessAgentExecution> start(String executable, List<String> arguments, {String input = '', Duration timeout = const Duration(minutes: 1), Map<String, String>? environment}) =>
      ProcessAgentExecution.start(executionId: 'execution-1', executable: executable, arguments: arguments, workingDirectory: temporaryDirectory.path, input: input, parser: _LineParser(), timeout: timeout, cancelGracePeriod: const Duration(milliseconds: 200), environment: environment);

  Future<File> writeExecutable(String name, String contents) async {
    final File file = File(path.join(temporaryDirectory.path, 'bin', name));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
    await Process.run('chmod', <String>['755', file.path]);
    return file;
  }

  test('roles map to fixed sandbox modes', () {
    expect(AgentRole.planner.sandboxMode, SandboxMode.readOnly);
    expect(AgentRole.reviewer.sandboxMode, SandboxMode.readOnly);
    expect(AgentRole.implementer.sandboxMode, SandboxMode.workspaceWrite);

    final AgentRunRequest request = AgentRunRequest(
      task: WorkflowTask.create(id: 'task-1', request: 'Build Weave', repositoryPath: '/repo', createdAt: DateTime.utc(2026)),
      role: AgentRole.reviewer,
      instructions: 'Review',
      workingDirectory: '/repo',
    );
    expect(request.sandboxMode, SandboxMode.readOnly);
  });

  group('ProcessAgentExecution', () {
    test('sends the prompt on stdin and streams parsed events', () async {
      final ProcessAgentExecution execution = await start('cat', const <String>[], input: 'first line\n  second  line\n');

      final List<AgentEvent> events = await execution.events.toList();

      expect(execution.executionId, 'execution-1');
      expect(events.whereType<AgentOutputEvent>().map((AgentOutputEvent event) => event.text), <String>['first line\n', '  second  line\n']);
      expect(events.last, isA<AgentCompletedEvent>());
      expect((events.last as AgentCompletedEvent).summary, '  second  line');
    });

    test('redacts secrets from every event', () async {
      final ProcessAgentExecution execution = await start('cat', const <String>[], input: 'key sk-ant-api03-abcdefghijklmnopqrstuvwxyz\n');

      final List<AgentEvent> events = await execution.events.toList();

      for (final AgentEvent event in events) {
        final String text = switch (event) {
          AgentOutputEvent(:final String text) => text,
          AgentCompletedEvent(:final String summary) => summary,
          _ => '',
        };
        expect(text, isNot(contains('sk-ant-')));
        expect(text, contains(SecretRedactor.placeholder));
      }
    });

    test('forwards stderr and reports a failing exit code', () async {
      final ProcessAgentExecution execution = await start('ls', <String>[path.join(temporaryDirectory.path, 'missing')]);

      final List<AgentEvent> events = await execution.events.toList();

      expect(events.whereType<AgentOutputEvent>().single.channel, AgentOutputChannel.stderr);
      expect(events.last, isA<AgentFailedEvent>().having((AgentFailedEvent event) => event.exitCode, 'exitCode', isNot(0)));
    });

    test('cancels a running process', () async {
      final ProcessAgentExecution execution = await start('sleep', <String>['30']);
      final Future<List<AgentEvent>> events = execution.events.toList();

      await execution.cancel();

      expect((await events).single, isA<AgentFailedEvent>().having((AgentFailedEvent event) => event.message, 'message', 'Cancelled by user.'));
    });

    test('stops a process that exceeds its timeout', () async {
      final ProcessAgentExecution execution = await start('sleep', <String>['30'], timeout: const Duration(milliseconds: 100));

      final List<AgentEvent> events = await execution.events.toList();

      expect(events.single, isA<AgentFailedEvent>().having((AgentFailedEvent event) => event.message, 'message', startsWith('Timed out')));
    });

    test('raises a typed error when the process cannot start', () async {
      await expectLater(start(path.join(temporaryDirectory.path, 'missing-agent'), const <String>[]), throwsA(isA<AgentStartException>()));
    });

    test('does not support interactive approvals', () async {
      final ProcessAgentExecution execution = await start('cat', const <String>[]);

      await expectLater(execution.resolveApproval(approvalId: 'approval-1', decision: ApprovalDecision.approve), throwsUnsupportedError);
      await execution.events.drain<void>();
    });
  });

  group('AgentExecutableLocator', () {
    test('finds executables on PATH and in common directories', () async {
      final File executable = await writeExecutable('fake-agent', '#!/bin/sh\n');
      await File(path.join(executable.parent.path, 'not-executable')).writeAsString('');
      final AgentExecutableLocator locator = AgentExecutableLocator(environment: <String, String>{'PATH': executable.parent.path, 'HOME': '/nonexistent'});

      expect(await locator.locate('fake-agent'), executable.path);
      expect(await locator.locate('not-executable'), isNull);
      expect(await locator.locate('missing-agent'), isNull);
      expect(await locator.locate(executable.path), executable.path);
      expect(locator.searchDirectories, contains('/opt/homebrew/bin'));
      expect(locator.searchDirectories, contains('/nonexistent/.local/bin'));
      expect(() => locator.locate('bin/fake-agent'), throwsArgumentError);
    });
  });

  group('CommandAgentAdapter', () {
    late Map<String, String> environment;

    setUp(() async {
      final File executable = await writeExecutable(
        'fake-agent',
        '#!/bin/sh\n'
            'if [ "\$1" = "--version" ]; then echo "fake-agent 1.2.3"; exit 0; fi\n'
            'echo "args: \$*"\n'
            'echo "git dir: \${GIT_DIR:-unset}"\n'
            'cat\n',
      );
      environment = <String, String>{'PATH': '${executable.parent.path}:/usr/bin:/bin', 'HOME': temporaryDirectory.path, 'GIT_DIR': '/elsewhere/.git'};
    });

    test('reports availability with the CLI version', () async {
      final AgentAvailability availability = await _fakeAdapter(environment).checkAvailability();

      expect(availability.isAvailable, isTrue);
      expect(availability.version, 'fake-agent 1.2.3');
    });

    test('reports a missing CLI as unavailable', () async {
      final AgentAvailability availability = await _fakeAdapter(<String, String>{'PATH': '/nonexistent', 'HOME': '/nonexistent'}).checkAvailability();

      expect(availability.isAvailable, isFalse);
      expect(availability.reason, contains('fake-agent'));
    });

    test('runs with role sandbox arguments and a clean environment', () async {
      final CommandAgentAdapter adapter = _fakeAdapter(environment);
      final AgentExecution execution = await adapter.start(
        AgentRunRequest(
          task: WorkflowTask.create(id: 'task-1', request: 'Build Weave', repositoryPath: temporaryDirectory.path, createdAt: DateTime.utc(2026)),
          role: AgentRole.planner,
          instructions: 'Plan the change',
          workingDirectory: temporaryDirectory.path,
        ),
      );

      final String output = (await execution.events.toList()).whereType<AgentOutputEvent>().map((AgentOutputEvent event) => event.text).join();

      expect(execution.executionId, 'fake-task-1-planner-1');
      expect(output, contains('args: --sandbox readOnly'));
      expect(output, contains('git dir: unset'));
      expect(output, contains('Plan the change'));
    });
  });
}
