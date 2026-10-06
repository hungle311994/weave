import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_security/weave_security.dart';

AgentRunRequest _request({List<McpServerDefinition> mcpServers = const <McpServerDefinition>[], String workingDirectory = '/repo', AgentRole role = AgentRole.planner}) => AgentRunRequest(
  task: WorkflowTask.create(id: 'task-1', request: 'Build it', repositoryPath: workingDirectory, createdAt: DateTime.utc(2026)),
  role: role,
  instructions: 'Do the work',
  workingDirectory: workingDirectory,
  mcpServers: mcpServers,
);

McpServerDefinition _stdioServer() => McpServerDefinition(
  id: 'tracker',
  displayName: 'Issue tracker',
  transport: McpStdioTransport(command: 'npx', arguments: <String>['-y', 'tracker-mcp'], environment: <String, String>{'TRACKER_TOKEN': r'${TRACKER_TOKEN}'}),
  linkPatterns: <String>[r'https://tracker\.example\.com/issues/\d+'],
);

void main() {
  group('McpServerDefinition', () {
    test('Figma presets recognize Figma links', () {
      final McpServerDefinition figma = McpServerDefinition.figma();

      expect(figma.matchesLinkIn('Build https://www.figma.com/design/AbC123/Login?node-id=1-2 please'), isTrue);
      expect(figma.matchesLinkIn('see https://figma.com/file/XYZ9/Old'), isTrue);
      expect(figma.matchesLinkIn('https://example.com/figma.com/design/x'), isFalse);
      expect(figma.matchesLinkIn('no link here'), isFalse);
      expect((figma.transport as McpHttpTransport).url, 'https://mcp.figma.com/mcp');
      expect((McpServerDefinition.figmaDesktop().transport as McpHttpTransport).url, 'http://127.0.0.1:3845/mcp');
    });

    test('resolves environment variables only when asked', () {
      final McpServerDefinition server = _stdioServer();

      final McpServerDefinition resolved = server.resolve(<String, String>{'TRACKER_TOKEN': 'secret-token-123'});

      expect((server.transport as McpStdioTransport).environment['TRACKER_TOKEN'], r'${TRACKER_TOKEN}');
      expect((resolved.transport as McpStdioTransport).environment['TRACKER_TOKEN'], 'secret-token-123');
      expect(resolved.transport.secretValues, contains('secret-token-123'));
      expect(() => server.resolve(const <String, String>{}), throwsA(isA<StateError>().having((StateError error) => error.message, 'message', contains('TRACKER_TOKEN'))));
    });

    test('round-trips through mcp.json', () {
      final List<McpServerDefinition> servers = <McpServerDefinition>[_stdioServer(), McpServerDefinition.figma()];

      final List<McpServerDefinition> restored = decodeMcpServers(encodeMcpServers(servers));

      expect(restored.map((McpServerDefinition server) => server.toJson()), servers.map((McpServerDefinition server) => server.toJson()));
    });

    test('rejects invalid servers', () {
      expect(
        () => McpServerDefinition(
          id: 'Bad Id',
          displayName: 'x',
          transport: McpHttpTransport(url: 'https://x.dev'),
        ),
        throwsArgumentError,
      );
      expect(() => McpHttpTransport(url: 'ftp://x.dev'), throwsArgumentError);
      expect(
        () => McpServerDefinition(
          id: 'x',
          displayName: 'x',
          transport: McpHttpTransport(url: 'https://x.dev'),
          linkPatterns: <String>['('],
        ),
        throwsArgumentError,
      );
      expect(() => decodeMcpServers('{"schemaVersion": 1, "servers": [{"id": "x", "displayName": "x", "transport": {"type": "ws"}}]}'), throwsFormatException);
      expect(() => decodeMcpServers(encodeMcpServers(<McpServerDefinition>[_stdioServer(), _stdioServer()])), throwsFormatException);
      expect(() => decodeMcpServers('{"schemaVersion": 2, "servers": []}'), throwsFormatException);
    });
  });

  group('McpRegistry', () {
    test('suggests servers for links that are not covered yet', () {
      final McpRegistry registry = McpRegistry.withBuiltIns(customServers: <McpServerDefinition>[_stdioServer()]);
      const String request = 'Implement https://www.figma.com/design/AbC123/Login and https://tracker.example.com/issues/42';

      expect(registry.ids, containsAll(<String>['figma', 'figma-desktop', 'tracker']));
      expect(registry.suggestionsFor(request).map((McpServerDefinition server) => server.id), <String>['figma', 'figma-desktop', 'tracker']);
      expect(registry.suggestionsFor(request, enabledIds: <String>['figma-desktop']).map((McpServerDefinition server) => server.id), <String>['tracker']);
      expect(registry.suggestionsFor('Plain request'), isEmpty);
      expect(registry.suggestionsFor('https://www.figma.com/design/AbC123/Login', enabledIds: <String>['figma']), isEmpty);
      expect(McpServerDefinition.figma().linksIn('a https://figma.com/file/A1/x b https://figma.com/file/A1/x'), <String>{'https://figma.com/file/A1'});
      expect(() => registry.require('missing'), throwsStateError);
    });
  });

  group('agent arguments', () {
    final List<McpServerDefinition> servers = <McpServerDefinition>[
      McpServerDefinition.figma(),
      _stdioServer().resolve(<String, String>{'TRACKER_TOKEN': 'abc'}),
    ];

    test('Claude Code receives a config file and allowed MCP tools', () {
      final List<String> arguments = AgentDefinition.claudeCode().buildArguments(_request(mcpServers: servers), mcpConfigFile: '/tmp/weave-mcp-1/mcp.json');

      expect(arguments, containsAllInOrder(<String>['--strict-mcp-config', '--mcp-config', '/tmp/weave-mcp-1/mcp.json', '--allowedTools', 'mcp__figma,mcp__tracker']));
      expect(() => AgentDefinition.claudeCode().buildArguments(_request(mcpServers: servers)), throwsArgumentError);
      expect(AgentDefinition.claudeCode().buildArguments(_request()), isNot(contains('--mcp-config')));
    });

    test('Codex receives TOML config overrides', () {
      final List<String> arguments = AgentDefinition.codex().buildArguments(_request(mcpServers: servers));

      expect(arguments, containsAllInOrder(<String>['-c', 'mcp_servers.figma.url="https://mcp.figma.com/mcp"', '-c', 'mcp_servers.tracker.command="npx"', '-c', 'mcp_servers.tracker.args=["-y","tracker-mcp"]', '-c', 'mcp_servers.tracker.env={"TRACKER_TOKEN" = "abc"}']));
      expect(arguments.last, '-');
    });

    test('agents without MCP support refuse MCP servers', () {
      final AgentDefinition plain = AgentDefinition(
        id: 'plain',
        displayName: 'Plain',
        executable: 'plain',
        sandboxArguments: const <SandboxMode, List<String>>{SandboxMode.readOnly: <String>[], SandboxMode.workspaceWrite: <String>[]},
      );

      expect(plain.supportsMcp, isFalse);
      expect(() => plain.buildArguments(_request(mcpServers: servers)), throwsUnsupportedError);
    });

    test('writes the Claude-style config file format', () {
      final Object? decoded = jsonDecode(encodeMcpConfigFile(servers));

      expect(decoded, <String, Object?>{
        'mcpServers': <String, Object?>{
          'figma': <String, Object?>{'type': 'http', 'url': 'https://mcp.figma.com/mcp', 'headers': <String, Object?>{}},
          'tracker': <String, Object?>{
            'type': 'stdio',
            'command': 'npx',
            'args': <Object?>['-y', 'tracker-mcp'],
            'env': <String, Object?>{'TRACKER_TOKEN': 'abc'},
          },
        },
      });
    });
  });

  test('passes a private MCP file to the agent, redacts its secrets, and removes it', () async {
    final Directory temporaryDirectory = await Directory.systemTemp.createTemp('weave-mcp-agent-test-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final File executable = File(path.join(temporaryDirectory.path, 'mcp-agent'));
    await executable.writeAsString(
      '#!/bin/sh\n'
      'while [ \$# -gt 0 ]; do\n'
      '  if [ "\$1" = "--config" ]; then echo "config: \$2"; cat "\$2"; echo; fi\n'
      '  shift\n'
      'done\n',
    );
    await Process.run('chmod', <String>['755', executable.path]);
    final CommandAgentAdapter adapter = CommandAgentAdapter(
      AgentDefinition(
        id: 'mcp-agent',
        displayName: 'MCP Agent',
        executable: executable.path,
        sandboxArguments: const <SandboxMode, List<String>>{SandboxMode.readOnly: <String>[], SandboxMode.workspaceWrite: <String>[]},
        mcpFormat: AgentMcpFormat.jsonConfigFile,
        mcpArguments: const <String>['--config', '{mcpConfigFile}'],
      ),
      environment: <String, String>{'PATH': '/usr/bin:/bin', 'HOME': temporaryDirectory.path},
    );
    final McpServerDefinition server = McpServerDefinition(
      id: 'private',
      displayName: 'Private',
      transport: McpHttpTransport(url: 'https://mcp.example.com', headers: <String, String>{'Authorization': 'token-value-987654'}),
    );

    final AgentExecution execution = await adapter.start(_request(mcpServers: <McpServerDefinition>[server], workingDirectory: temporaryDirectory.path));
    final List<AgentEvent> events = await execution.events.toList();
    final String output = events.whereType<AgentOutputEvent>().map((AgentOutputEvent event) => event.text).join();

    final String configPath = RegExp(r'config: (\S+)').firstMatch(output)!.group(1)!;
    expect(configPath, isNot(startsWith(temporaryDirectory.path)));
    expect(output, allOf(contains('https://mcp.example.com'), contains(SecretRedactor.placeholder), isNot(contains('token-value-987654'))));
    expect(File(configPath).existsSync(), isFalse);
    expect(adapter.supportsMcp, isTrue);
  });
}
