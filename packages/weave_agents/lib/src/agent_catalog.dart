import 'package:weave_security/weave_security.dart';

import 'agent_definition.dart';

/// A well-known command-line agent the user can add with one click, beside
/// the built-in presets. Like the presets, these are data: each CLI's own
/// flags, published by its maker, filled into an [AgentDefinition].
final class AgentCatalogEntry {
  const AgentCatalogEntry({required this.definition, required this.summary});

  final AgentDefinition definition;

  /// One line on what it is, e.g. "Google's coding agent".
  final String summary;
}

/// Agents to offer in Add agent. The prompt always goes on stdin, which also
/// makes each CLI run without its interactive interface.
List<AgentCatalogEntry> get agentCatalog => <AgentCatalogEntry>[
  AgentCatalogEntry(
    summary: 'Google\'s coding agent, with a Google account or a Gemini API key',
    definition: AgentDefinition(
      id: 'gemini',
      displayName: 'Gemini CLI',
      executable: 'gemini',
      vendor: 'Google',
      brand: 'gemini',
      arguments: const <String>['--output-format', 'text'],
      // `plan` is Gemini CLI's read-only mode; `auto_edit` approves file edits only.
      sandboxArguments: const <SandboxMode, List<String>>{
        SandboxMode.readOnly: <String>['--approval-mode', 'plan'],
        SandboxMode.workspaceWrite: <String>['--approval-mode', 'auto_edit'],
      },
      readableDirectoryArguments: const <String>['--include-directories', '{directory}'],
      writableDirectoryArguments: const <String>['--include-directories', '{directory}'],
      installOptions: const <AgentInstallOption>[
        AgentInstallOption(label: 'Homebrew', command: <String>['brew', 'install', 'gemini-cli']),
        AgentInstallOption(label: 'npm', command: <String>['npm', 'install', '-g', '@google/gemini-cli']),
      ],
      // Starting it interactively offers "Login with Google".
      signInCommand: const <String>['gemini'],
    ),
  ),
  AgentCatalogEntry(
    summary: 'GitHub\'s coding agent, with a Copilot subscription',
    definition: AgentDefinition(
      id: 'copilot',
      displayName: 'GitHub Copilot CLI',
      executable: 'copilot',
      vendor: 'GitHub',
      brand: 'github',
      arguments: const <String>['-s', '--no-ask-user'],
      // Weave runs verification itself, so no role gets the shell tool.
      sandboxArguments: const <SandboxMode, List<String>>{
        SandboxMode.readOnly: <String>['--deny-tool=write', '--deny-tool=shell'],
        SandboxMode.workspaceWrite: <String>['--allow-tool=write', '--deny-tool=shell'],
      },
      readableDirectoryArguments: const <String>['--add-dir', '{directory}'],
      writableDirectoryArguments: const <String>['--add-dir', '{directory}'],
      installOptions: const <AgentInstallOption>[
        AgentInstallOption(label: 'Homebrew', command: <String>['brew', 'install', 'copilot-cli']),
        AgentInstallOption(label: 'npm', command: <String>['npm', 'install', '-g', '@github/copilot']),
      ],
      // Starting it interactively offers the /login command.
      signInCommand: const <String>['copilot'],
    ),
  ),
];
