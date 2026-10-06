import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_security/weave_security.dart';

final DateTime _timestamp = DateTime.utc(2026, 10, 6);

AgentRunRequest _request({String? model, String workingDirectory = '/repo'}) => AgentRunRequest(
  task: WorkflowTask.create(id: 'task-1', request: 'Build it', repositoryPath: workingDirectory, createdAt: DateTime.utc(2026)),
  role: AgentRole.planner,
  instructions: 'Plan',
  workingDirectory: workingDirectory,
  model: model,
);

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-agent-health-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  /// An agent whose `auth status` prints [authOutput] and exits [authExit].
  Future<CommandAgentAdapter> fakeAgent({required String authOutput, int authExit = 0, String? jsonField = 'loggedIn', String body = 'echo done'}) async {
    final File executable = File(path.join(temporaryDirectory.path, 'health-agent'));
    await executable.writeAsString(
      '#!/bin/sh\n'
      'if [ "\$1" = "--version" ]; then echo "health-agent 2.0"; exit 0; fi\n'
      'if [ "\$1" = "auth" ]; then echo \'$authOutput\'; exit $authExit; fi\n'
      'cat > /dev/null\n'
      '$body\n',
    );
    await Process.run('chmod', <String>['755', executable.path]);
    return CommandAgentAdapter(
      AgentDefinition(
        id: 'health',
        displayName: 'Health Agent',
        executable: executable.path,
        sandboxArguments: const <SandboxMode, List<String>>{SandboxMode.readOnly: <String>[], SandboxMode.workspaceWrite: <String>[]},
        authStatusArguments: const <String>['auth', 'status'],
        authStatusJsonField: jsonField,
        signInCommand: const <String>['health-agent', 'auth', 'login'],
        failurePatterns: const <AgentFailureKind, List<String>>{
          AgentFailureKind.rateLimit: <String>['plan exhausted'],
        },
      ),
      environment: <String, String>{'PATH': '/usr/bin:/bin', 'HOME': temporaryDirectory.path},
    );
  }

  group('sign-in status', () {
    test('is available when the auth status says signed in', () async {
      final AgentAvailability availability = await (await fakeAgent(authOutput: '{"loggedIn": true, "email": "someone@example.com"}')).checkAvailability();

      expect(availability.isAvailable, isTrue);
      expect(availability.needsSignIn, isFalse);
    });

    test('asks to sign in when the auth status says signed out', () async {
      final AgentAvailability availability = await (await fakeAgent(authOutput: '{"loggedIn": false}')).checkAvailability();

      expect(availability.isAvailable, isFalse);
      expect(availability.needsSignIn, isTrue);
      expect(availability.signInCommand, 'health-agent auth login');
      expect(availability.reason, contains('Run `health-agent auth login` in Terminal'));
      expect(availability.version, 'health-agent 2.0');
    });

    test('uses the exit code when no JSON field is declared', () async {
      expect((await (await fakeAgent(authOutput: 'Not logged in', authExit: 1, jsonField: null)).checkAvailability()).needsSignIn, isTrue);
      expect((await (await fakeAgent(authOutput: 'Logged in using ChatGPT', jsonField: null)).checkAvailability()).isAvailable, isTrue);
    });

    test('does not block when the auth status cannot be read', () async {
      expect((await (await fakeAgent(authOutput: 'not json')).checkAvailability()).isAvailable, isTrue);
    });

    test('presets declare how to check and sign in', () {
      expect(AgentDefinition.claudeCode().authStatusArguments, <String>['auth', 'status']);
      expect(AgentDefinition.claudeCode().authStatusJsonField, 'loggedIn');
      expect(AgentDefinition.claudeCode().signInCommand, <String>['claude', 'auth', 'login']);
      expect(AgentDefinition.codex().signInCommand, <String>['codex', 'login']);
    });
  });

  group('failure classification', () {
    final AgentFailureClassifier classifier = AgentFailureClassifier(
      extraPatterns: const <AgentFailureKind, List<String>>{
        AgentFailureKind.network: <String>['tunnel collapsed'],
      },
    );

    test('recognizes common network, quota, and sign-in errors', () {
      const Map<String, AgentFailureKind> cases = <String, AgentFailureKind>{
        'Error: getaddrinfo ENOTFOUND api.anthropic.com': AgentFailureKind.network,
        'stream disconnected before completion': AgentFailureKind.network,
        'API Error: 529 Overloaded': AgentFailureKind.network,
        'tunnel collapsed': AgentFailureKind.network,
        'Claude AI usage limit reached|1760000000': AgentFailureKind.rateLimit,
        '429 Too Many Requests': AgentFailureKind.rateLimit,
        'You exceeded your current quota': AgentFailureKind.rateLimit,
        'Invalid API key · Please run /login': AgentFailureKind.authentication,
        'HTTP 401 Unauthorized': AgentFailureKind.authentication,
        'TypeError: undefined is not a function': AgentFailureKind.unknown,
      };
      for (final MapEntry<String, AgentFailureKind>(key: String text, value: AgentFailureKind kind) in cases.entries) {
        expect(classifier.classify(text), kind, reason: text);
      }
    });

    test('classifies failures of a running agent from its message and stderr', () async {
      final CommandAgentAdapter adapter = await fakeAgent(authOutput: '{"loggedIn": true}', body: 'echo "warning: plan exhausted for today" >&2\nexit 2');

      final AgentExecution execution = await adapter.start(_request(workingDirectory: temporaryDirectory.path));
      final AgentFailedEvent failure = (await execution.events.toList()).last as AgentFailedEvent;

      expect(failure.kind, AgentFailureKind.rateLimit);
      expect(failure.exitCode, 2);
    });
  });

  group('usage', () {
    test('Claude Code reports tokens and cost', () {
      final ClaudeCodeOutputParser parser = ClaudeCodeOutputParser()
        ..parseLine(
          jsonEncode(<String, Object?>{
            'type': 'result',
            'subtype': 'success',
            'is_error': false,
            'result': 'Done',
            'session_id': 's-1',
            'total_cost_usd': 0.0123,
            'usage': <String, Object?>{'input_tokens': 100, 'cache_creation_input_tokens': 20, 'cache_read_input_tokens': 900, 'output_tokens': 50},
          }),
          _timestamp,
        );

      final AgentUsage usage = (parser.finish(0, _timestamp) as AgentCompletedEvent).usage!;

      expect(usage.inputTokens, 120);
      expect(usage.cachedInputTokens, 900);
      expect(usage.outputTokens, 50);
      expect(usage.costUsd, 0.0123);
      expect(usage.totalTokens, 1070);
    });

    test('Codex reports tokens and keeps the session of a failed turn', () {
      final CodexOutputParser parser = CodexOutputParser();
      for (final Map<String, Object?> record in <Map<String, Object?>>[
        <String, Object?>{'type': 'thread.started', 'thread_id': 'thread-7'},
        <String, Object?>{
          'type': 'turn.completed',
          'usage': <String, Object?>{'input_tokens': 1000, 'cached_input_tokens': 600, 'output_tokens': 80},
        },
        <String, Object?>{
          'type': 'turn.failed',
          'error': <String, Object?>{'message': 'stream disconnected'},
        },
      ]) {
        parser.parseLine(jsonEncode(record), _timestamp);
      }

      final AgentFailedEvent failure = parser.finish(1, _timestamp) as AgentFailedEvent;

      expect(failure.sessionId, 'thread-7');
      expect(failure.usage!.inputTokens, 400);
      expect(failure.usage!.cachedInputTokens, 600);
      expect(failure.usage!.costUsd, isNull);
    });

    test('adds up and serializes usage', () {
      const AgentUsage first = AgentUsage(inputTokens: 10, outputTokens: 5, costUsd: 0.5);
      const AgentUsage second = AgentUsage(inputTokens: 1, cachedInputTokens: 2);

      final AgentUsage total = first + second;

      expect(total.totalTokens, 18);
      expect(total.costUsd, 0.5);
      expect(AgentUsage.fromJson(total.toJson()).toJson(), total.toJson());
      expect((second + second).costUsd, isNull);
    });
  });

  test('a request can override the model per run', () {
    final AgentDefinition definition = AgentDefinition.codex(model: 'default-model');

    expect(definition.buildArguments(_request()), containsAllInOrder(<String>['--model', 'default-model']));
    expect(definition.buildArguments(_request(model: 'fast-model')), containsAllInOrder(<String>['--model', 'fast-model']));
    expect(AgentDefinition.codex().buildArguments(_request()), isNot(contains('--model')));
  });

  test('definitions round-trip auth and failure settings through JSON', () {
    final AgentDefinition definition = AgentDefinition(
      id: 'x',
      displayName: 'X',
      executable: 'x',
      sandboxArguments: const <SandboxMode, List<String>>{SandboxMode.readOnly: <String>[], SandboxMode.workspaceWrite: <String>[]},
      authStatusArguments: const <String>['whoami'],
      authStatusJsonField: 'ok',
      signInCommand: const <String>['x', 'login'],
      failurePatterns: const <AgentFailureKind, List<String>>{
        AgentFailureKind.network: <String>['lost link'],
      },
    );

    expect(AgentDefinition.fromJson(definition.toJson()).toJson(), definition.toJson());
    expect(
      () => AgentDefinition.fromJson(<String, Object?>{
        ...definition.toJson(),
        'failurePatterns': <String, Object?>{'flood': <String>[]},
      }),
      throwsFormatException,
    );
    expect(
      () => AgentDefinition.fromJson(<String, Object?>{
        ...definition.toJson(),
        'failurePatterns': <String, Object?>{
          'network': <String>['('],
        },
      }),
      throwsFormatException,
    );
  });
}
