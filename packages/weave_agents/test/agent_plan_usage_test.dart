import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_security/weave_security.dart';

/// The shape of a real `claude --print /usage` report, minus account details.
const String _report = '''
You are currently using your subscription to power your Claude Code usage

Current session: 28% used · resets Oct 7 at 8:10pm (Asia/Saigon)
Current week (all models): 74% used · resets Oct 10 at 6pm (Asia/Saigon)

Last 24h · 1029 requests · 9 sessions
  92% of your usage was at >150k context''';

void main() {
  late Directory temporaryDirectory;

  setUp(() async => temporaryDirectory = await Directory.systemTemp.createTemp('weave-plan-usage-'));
  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  /// An agent whose usage command prints [usageOutput] and exits [usageExit].
  Future<CommandAgentAdapter> fakeAgent({required String usageOutput, int usageExit = 0, String? jsonField = 'result', List<String> usageArguments = const <String>['--print', '/usage']}) async {
    final File output = File(path.join(temporaryDirectory.path, 'usage.out'));
    await output.writeAsString(usageOutput);
    final File executable = File(path.join(temporaryDirectory.path, 'usage-agent'));
    await executable.writeAsString(
      '#!/bin/sh\n'
      'if [ "\$2" = "/usage" ]; then cat "${output.path}"; exit $usageExit; fi\n'
      'echo "usage-agent 1.0"\n',
    );
    await Process.run('chmod', <String>['755', executable.path]);
    return CommandAgentAdapter(
      AgentDefinition(
        id: 'usage',
        displayName: 'Usage Agent',
        executable: executable.path,
        sandboxArguments: const <SandboxMode, List<String>>{SandboxMode.readOnly: <String>[], SandboxMode.workspaceWrite: <String>[]},
        planUsageArguments: usageArguments,
        planUsageJsonField: jsonField,
      ),
      environment: <String, String>{'PATH': '/usr/bin:/bin', 'HOME': temporaryDirectory.path},
    );
  }

  test('parses the limit windows and keeps nothing else from the report', () {
    final List<AgentPlanUsageWindow> windows = AgentPlanUsage.parseWindows(_report);

    expect(windows.map((AgentPlanUsageWindow window) => (window.label, window.percentUsed, window.resetsAt)), <(String, int, String?)>[
      ('Current session', 28, 'Oct 7 at 8:10pm (Asia/Saigon)'),
      ('Current week (all models)', 74, 'Oct 10 at 6pm (Asia/Saigon)'),
    ]);
  });

  test('reads plan usage from the JSON field of the agent report', () async {
    final CommandAgentAdapter agent = await fakeAgent(usageOutput: jsonEncode(<String, Object?>{'result': _report, 'total_cost_usd': 0}));

    expect(agent.reportsPlanUsage, isTrue);
    final AgentPlanUsage usage = await agent.readPlanUsage();
    expect(usage.windows, hasLength(2));
    expect(usage.windows.last.percentUsed, 74);
  });

  test('reads a plain-text report when no JSON field is configured', () async {
    final CommandAgentAdapter agent = await fakeAgent(usageOutput: _report, jsonField: null);

    expect((await agent.readPlanUsage()).windows.first.label, 'Current session');
  });

  test('fails clearly when the command fails or reports no limits', () async {
    await expectLater((await fakeAgent(usageOutput: 'boom', usageExit: 1)).readPlanUsage(), throwsA(isA<AgentPlanUsageException>().having((AgentPlanUsageException error) => error.message, 'message', contains('exit 1'))));
    await expectLater(
      (await fakeAgent(usageOutput: jsonEncode(<String, Object?>{'result': 'You are using an API key.'}))).readPlanUsage(),
      throwsA(isA<AgentPlanUsageException>().having((AgentPlanUsageException error) => error.message, 'message', contains('no plan limits'))),
    );
  });

  test('an agent without a usage command does not report plan usage', () async {
    final CommandAgentAdapter agent = await fakeAgent(usageOutput: '', usageArguments: const <String>[]);

    expect(agent.reportsPlanUsage, isFalse);
    await expectLater(agent.readPlanUsage(), throwsA(isA<AgentPlanUsageException>()));
  });

  test('the usage command is agent data that survives agents.json', () {
    final AgentDefinition claude = AgentDefinition.claudeCode();
    expect(claude.reportsPlanUsage, isTrue);
    expect(claude.planUsageFormat, AgentPlanUsageFormat.text);
    final AgentDefinition codex = AgentDefinition.codex();
    expect(codex.reportsPlanUsage, isTrue);
    expect(codex.planUsageFormat, AgentPlanUsageFormat.codexAppServer);
    expect(AgentDefinition.fromJson(jsonDecode(jsonEncode(codex.toJson())) as Map<String, Object?>).planUsageFormat, AgentPlanUsageFormat.codexAppServer);

    final AgentDefinition restored = AgentDefinition.fromJson(jsonDecode(jsonEncode(claude.toJson())) as Map<String, Object?>);
    expect(restored.planUsageArguments, claude.planUsageArguments);
    expect(restored.planUsageJsonField, 'result');
    expect(claude.withModel('opus').planUsageArguments, claude.planUsageArguments);
  });

  group('app server format', () {
    const String response = '{"id":2,"result":{"accountId":"acct-secret","rateLimits":{"limitId":"codex","primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":1791375303},"secondary":{"usedPercent":16,"windowDurationMins":10080,"resetsAt":1791962103},"planType":"plus"}}}';

    test('reads the 5-hour and weekly windows with exact reset times', () {
      final List<AgentPlanUsageWindow> windows = parseCodexPlanUsage(jsonDecode(response) as Map<String, Object?>);

      expect(windows.map((AgentPlanUsageWindow window) => (window.label, window.percentUsed)), <(String, int)>[('5-hour limit', 100), ('Weekly limit', 16)]);
      expect(windows.first.resetTime, DateTime.fromMillisecondsSinceEpoch(1791375303 * 1000, isUtc: true));
    });

    test('reports a JSON-RPC error as a readable failure', () {
      expect(
        () => parseCodexPlanUsage(<String, Object?>{
          'id': 2,
          'error': <String, Object?>{'message': 'not signed in'},
        }),
        throwsA(isA<AgentPlanUsageException>().having((AgentPlanUsageException error) => error.message, 'message', contains('not signed in'))),
      );
    });

    test('talks JSON-RPC to the app server and stops it', () async {
      final File executable = File(path.join(temporaryDirectory.path, 'app-server-agent'));
      await executable.writeAsString(
        '#!/bin/sh\n'
        'while read line; do\n'
        '  case "\$line" in\n'
        '    *\'"id":1\'*) echo \'{"id":1,"result":{"userAgent":"fake"}}\' ;;\n'
        '    *\'"id":2\'*) echo \'$response\' ;;\n'
        '  esac\n'
        'done\n',
      );
      await Process.run('chmod', <String>['755', executable.path]);
      final CommandAgentAdapter agent = CommandAgentAdapter(
        AgentDefinition(
          id: 'server',
          displayName: 'Server Agent',
          executable: executable.path,
          sandboxArguments: const <SandboxMode, List<String>>{SandboxMode.readOnly: <String>[], SandboxMode.workspaceWrite: <String>[]},
          planUsageArguments: const <String>['app-server'],
          planUsageFormat: AgentPlanUsageFormat.codexAppServer,
        ),
        environment: <String, String>{'PATH': '/usr/bin:/bin', 'HOME': temporaryDirectory.path},
      );

      final AgentPlanUsage usage = await agent.readPlanUsage();
      expect(usage.windows.map((AgentPlanUsageWindow window) => window.percentUsed), <int>[100, 16]);
    });
  });
}
