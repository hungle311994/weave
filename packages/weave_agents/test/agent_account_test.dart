import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_security/weave_security.dart';

const Map<SandboxMode, List<String>> _noSandbox = <SandboxMode, List<String>>{SandboxMode.readOnly: <String>[], SandboxMode.workspaceWrite: <String>[]};

void main() {
  late Directory temporaryDirectory;

  setUp(() async => temporaryDirectory = await Directory.systemTemp.createTemp('weave-accounts-'));
  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  group('AgentAccount', () {
    test('round-trips through accounts.json', () {
      final List<AgentAccount> accounts = <AgentAccount>[AgentAccount(id: 'claude-code-work', agentId: 'claude-code', name: ' Work ')];
      final List<AgentAccount> restored = decodeAgentAccounts(encodeAgentAccounts(accounts));

      expect(restored.single.id, 'claude-code-work');
      expect(restored.single.agentId, 'claude-code');
      expect(restored.single.name, 'Work', reason: 'names are trimmed');
    });

    test('rejects invalid documents, IDs and empty names', () {
      expect(() => decodeAgentAccounts('{"schemaVersion": 2, "accounts": []}'), throwsFormatException);
      expect(() => decodeAgentAccounts('{"schemaVersion": 1, "accounts": [{"id": "a"}]}'), throwsFormatException);
      expect(
        () => decodeAgentAccounts(
          encodeAgentAccounts(<AgentAccount>[
            AgentAccount(id: 'a', agentId: 'x', name: 'One'),
            AgentAccount(id: 'a', agentId: 'x', name: 'Two'),
          ]),
        ),
        throwsFormatException,
      );
      expect(() => AgentAccount(id: 'Bad ID', agentId: 'x', name: 'n'), throwsArgumentError);
      expect(() => AgentAccount(id: 'ok', agentId: 'x', name: '  '), throwsArgumentError);
    });

    test('shellQuote leaves plain words alone and quotes the rest', () {
      expect(shellQuote('/Users/me/accounts/work'), '/Users/me/accounts/work');
      expect(shellQuote('/Users/me/Application Support/x'), "'/Users/me/Application Support/x'");
      expect(shellQuote("it's"), r"'it'\''s'");
    });
  });

  group('AgentDefinition accounts', () {
    test('presets declare their configuration folder variable as data', () {
      expect(AgentDefinition.claudeCode().accountDirectoryVariable, 'CLAUDE_CONFIG_DIR');
      expect(AgentDefinition.claudeCode().accountFormat, AgentAccountFormat.authStatusJson);
      expect(AgentDefinition.codex().accountDirectoryVariable, 'CODEX_HOME');
      expect(AgentDefinition.codex().accountFormat, AgentAccountFormat.codexAppServer);
      expect(AgentDefinition.claudeCode().supportsAccounts, isTrue);
    });

    test('an account is the same agent under its own ID, name and configuration folder', () {
      final AgentDefinition claude = AgentDefinition.claudeCode(model: 'opus');
      final AgentDefinition work = claude.forAccount(
        AgentAccount(id: 'claude-code-work', agentId: 'claude-code', name: 'Work'),
        directory: '/Users/me/Library/Application Support/Weave/accounts/claude-code-work',
      );

      expect(work.id, 'claude-code-work');
      expect(work.displayName, 'Claude Code · Work');
      expect(work.executable, claude.executable);
      expect(work.arguments, claude.arguments);
      expect(work.model, 'opus');
      expect(work.environment, <String, String>{'CLAUDE_CONFIG_DIR': '/Users/me/Library/Application Support/Weave/accounts/claude-code-work'});
      expect(work.account?.name, 'Work');
      expect(work.supportsAccounts, isFalse, reason: 'an account cannot have accounts');
      expect(work.withModel('haiku').environment, work.environment, reason: 'copies keep the account');
      expect(work.signInCommandText, "CLAUDE_CONFIG_DIR='/Users/me/Library/Application Support/Weave/accounts/claude-code-work' claude auth login");
      expect(claude.signInCommandText, 'claude auth login');
    });

    test('only an agent with a configuration folder variable can have accounts', () {
      final AgentDefinition plain = AgentDefinition(id: 'plain', displayName: 'Plain', executable: 'plain', sandboxArguments: _noSandbox);

      expect(plain.supportsAccounts, isFalse);
      expect(
        () => plain.forAccount(
          AgentAccount(id: 'plain-two', agentId: 'plain', name: 'Two'),
          directory: '/tmp/x',
        ),
        throwsStateError,
      );
      expect(
        () => AgentDefinition.codex().forAccount(
          AgentAccount(id: 'codex-two', agentId: 'claude-code', name: 'Two'),
          directory: '/tmp/x',
        ),
        throwsArgumentError,
      );
      expect(() => AgentDefinition(id: 'bad', displayName: 'Bad', executable: 'bad', sandboxArguments: _noSandbox, accountDirectoryVariable: 'NOT VALID'), throwsArgumentError);
    });

    test('account settings and extra environment survive agents.json', () {
      final AgentDefinition custom = AgentDefinition(
        id: 'gemini',
        displayName: 'Gemini',
        executable: 'gemini',
        sandboxArguments: _noSandbox,
        accountDirectoryVariable: 'GEMINI_HOME',
        accountFormat: AgentAccountFormat.authStatusJson,
        accountArguments: const <String>['whoami', '--json'],
        accountEmailJsonField: 'user',
        accountPlanJsonField: 'tier',
        environment: const <String, String>{'NO_COLOR': '1'},
      );
      final AgentDefinition restored = AgentDefinition.fromJson(jsonDecode(jsonEncode(custom.toJson())) as Map<String, Object?>);

      expect(restored.accountDirectoryVariable, 'GEMINI_HOME');
      expect(restored.accountFormat, AgentAccountFormat.authStatusJson);
      expect(restored.accountArguments, <String>['whoami', '--json']);
      expect(restored.accountEmailJsonField, 'user');
      expect(restored.accountPlanJsonField, 'tier');
      expect(restored.environment, <String, String>{'NO_COLOR': '1'});
      expect(
        () => AgentDefinition.fromJson(<String, Object?>{
          ...custom.toJson(),
          'environment': <String, Object?>{'A': 1},
        }),
        throwsFormatException,
      );
    });
  });

  group('CommandAgentAdapter accounts', () {
    /// A CLI that is signed in only when `FAKE_HOME` is [signedInHome].
    Future<AgentDefinition> fakeAgent(String signedInHome) async {
      final File executable = File(path.join(temporaryDirectory.path, 'fake-agent'));
      await executable.writeAsString(
        '#!/bin/sh\n'
        'if [ "\$1" = "auth" ]; then\n'
        '  if [ "\$FAKE_HOME" = "$signedInHome" ]; then echo \'{"loggedIn":true,"email":"b@example.com","subscriptionType":"max"}\'; else echo \'{"loggedIn":false}\'; fi\n'
        '  exit 0\n'
        'fi\n'
        'echo "fake-agent 1.0"\n',
      );
      await Process.run('chmod', <String>['755', executable.path]);
      return AgentDefinition(
        id: 'fake',
        displayName: 'Fake',
        executable: executable.path,
        sandboxArguments: _noSandbox,
        authStatusArguments: const <String>['auth', 'status'],
        authStatusJsonField: 'loggedIn',
        signInCommand: const <String>['fake', 'login'],
        accountDirectoryVariable: 'FAKE_HOME',
        accountFormat: AgentAccountFormat.authStatusJson,
        accountArguments: const <String>['auth', 'status'],
        accountEmailJsonField: 'email',
        accountPlanJsonField: 'subscriptionType',
      );
    }

    test('each account runs with its own folder and reports its own sign-in', () async {
      final String home = path.join(temporaryDirectory.path, 'accounts', 'fake-b');
      final AgentDefinition fake = await fakeAgent(home);
      final Map<String, String> environment = <String, String>{'PATH': '/usr/bin:/bin', 'HOME': temporaryDirectory.path};
      final CommandAgentAdapter base = CommandAgentAdapter(fake, environment: environment);
      final CommandAgentAdapter second = CommandAgentAdapter(
        fake.forAccount(
          AgentAccount(id: 'fake-b', agentId: 'fake', name: 'B'),
          directory: home,
        ),
        environment: environment,
      );

      expect(base.supportsAccounts, isTrue);
      expect(base.account, isNull);
      expect(second.supportsAccounts, isFalse);
      expect(second.account?.id, 'fake-b');

      final AgentAvailability baseAvailability = await base.checkAvailability();
      expect(baseAvailability.isAvailable, isFalse);
      expect(baseAvailability.signInCommand, 'fake login');
      expect(await base.readAccount(), isNull, reason: 'the default folder is signed out');

      expect((await second.checkAvailability()).isAvailable, isTrue);
      final AgentAccountInfo? info = await second.readAccount();
      expect(info?.email, 'b@example.com');
      expect(info?.plan, 'max');
    });

    test('a signed-out account shows the sign-in command for its own folder', () async {
      final AgentDefinition fake = await fakeAgent('/nowhere');
      final CommandAgentAdapter second = CommandAgentAdapter(
        fake.forAccount(
          AgentAccount(id: 'fake-c', agentId: 'fake', name: 'C'),
          directory: '/tmp/weave accounts/fake-c',
        ),
        environment: <String, String>{'PATH': '/usr/bin:/bin'},
      );

      expect((await second.checkAvailability()).signInCommand, "FAKE_HOME='/tmp/weave accounts/fake-c' fake login");
    });

    test('reads the account from an app server', () async {
      const String response = '{"id":2,"result":{"account":{"type":"chatgpt","email":"a@example.com","planType":"plus"},"requiresOpenaiAuth":true}}';
      final File executable = File(path.join(temporaryDirectory.path, 'app-server-agent'));
      await executable.writeAsString(
        '#!/bin/sh\n'
        'while read line; do\n'
        '  case "\$line" in\n'
        '    *\'"id":1\'*) echo \'{"id":1,"result":{"userAgent":"fake"}}\' ;;\n'
        '    *\'"account/read"\'*) echo \'$response\' ;;\n'
        '  esac\n'
        'done\n',
      );
      await Process.run('chmod', <String>['755', executable.path]);
      final CommandAgentAdapter agent = CommandAgentAdapter(
        AgentDefinition(id: 'server', displayName: 'Server', executable: executable.path, sandboxArguments: _noSandbox, accountFormat: AgentAccountFormat.codexAppServer, accountArguments: const <String>['app-server']),
        environment: <String, String>{'PATH': '/usr/bin:/bin', 'HOME': temporaryDirectory.path},
      );

      final AgentAccountInfo? info = await agent.readAccount();
      expect(info?.email, 'a@example.com');
      expect(info?.plan, 'plus');
      expect(
        parseCodexAccount(<String, Object?>{
          'id': 2,
          'result': <String, Object?>{'account': null},
        }),
        isNull,
        reason: 'signed out',
      );
    });
  });
}
