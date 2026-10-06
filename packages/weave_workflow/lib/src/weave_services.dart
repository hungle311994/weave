import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_git/weave_git.dart';
import 'package:weave_security/weave_security.dart';
import 'package:weave_storage/weave_storage.dart';

import 'verification.dart';
import 'workflow_orchestrator.dart';
import 'workflow_run_lock.dart';
import 'workflow_run_state.dart';
import 'workflow_settings.dart';

/// Everything a Weave front end needs, wired to one storage root.
final class WeaveServices {
  WeaveServices({required this.paths, required this.agents, required this.environment, McpRegistry? mcp, GitRepositoryService? git})
    : mcp = mcp ?? McpRegistry.withBuiltIns(),
      git = git ?? GitRepositoryService(runner: ProcessGitCommandRunner(environment: environment)),
      gitWriter = GitWriteService(
        runner: ProcessGitCommandRunner(environment: environment),
        reader: git,
      ),
      tasks = FileWorkflowTaskStore(workflowsDirectory: paths.workflowsDirectory),
      artifacts = FileWorkflowArtifactStore(workflowsDirectory: paths.workflowsDirectory, redactor: SecretRedactor.fromEnvironment(environment)),
      settings = FileWorkflowSettingsStore(paths: paths),
      runStates = FileWorkflowRunStateStore(workflowsDirectory: paths.workflowsDirectory),
      locks = WorkflowRunLock(workflowsDirectory: paths.workflowsDirectory);

  /// Resolves the storage root and loads built-in plus custom agents.
  static Future<WeaveServices> open({WeaveStoragePaths? paths, Map<String, String>? environment}) async {
    final Map<String, String> resolvedEnvironment = environment ?? Platform.environment;
    final WeaveStoragePaths resolvedPaths = paths ?? WeaveStoragePaths.current(environment: resolvedEnvironment);
    return WeaveServices(
      paths: resolvedPaths,
      agents: await loadAgentRegistry(resolvedPaths, environment: resolvedEnvironment),
      mcp: await loadMcpRegistry(resolvedPaths),
      environment: resolvedEnvironment,
    );
  }

  final WeaveStoragePaths paths;
  final AgentRegistry agents;

  /// Built-in plus custom MCP servers; refreshed by [reloadMcp].
  McpRegistry mcp;
  final Map<String, String> environment;
  final GitRepositoryService git;

  /// Commits, always behind an approval gate.
  final GitWriteService gitWriter;
  final FileWorkflowTaskStore tasks;
  final FileWorkflowArtifactStore artifacts;
  final FileWorkflowSettingsStore settings;
  final FileWorkflowRunStateStore runStates;
  final WorkflowRunLock locks;

  /// Re-reads `mcp.json` after it was changed.
  Future<void> reloadMcp() async => mcp = await loadMcpRegistry(paths);

  WorkflowOrchestrator createOrchestrator({VerificationRunner? verifier}) => WorkflowOrchestrator(
    agents: agents,
    tasks: tasks,
    artifacts: artifacts,
    settingsStore: settings,
    runStates: runStates,
    locks: locks,
    git: git,
    mcpServers: mcp,
    environment: environment,
    verifier: verifier ?? ProcessVerificationRunner(environment: environment),
  );

  /// Saved defaults for [repositoryRoot], or every role assigned to the
  /// first available agent.
  Future<WorkflowSettings> settingsFor(String repositoryRoot) async => await settings.loadProjectDefaults(repositoryRoot) ?? WorkflowSettings(assignments: await firstAvailableAssignments(agents));
}

/// Location of the optional custom agent definitions.
String agentsFilePath(WeaveStoragePaths paths) => path.join(paths.rootDirectory, 'agents.json');

/// Built-in agents plus those in `agents.json`, which may replace a preset.
Future<AgentRegistry> loadAgentRegistry(WeaveStoragePaths paths, {Map<String, String>? environment}) async {
  final File file = File(agentsFilePath(paths));
  final List<AgentDefinition> customDefinitions = await file.exists() ? decodeAgentDefinitions(await file.readAsString()) : const <AgentDefinition>[];
  return AgentRegistry.fromDefinitions(customDefinitions: customDefinitions, environment: environment);
}

/// Assigns every role to the first available agent in registry order.
Future<AgentAssignments> firstAvailableAssignments(AgentRegistry agents) async {
  for (final AgentAdapter adapter in agents.adapters) {
    if ((await adapter.checkAvailability()).isAvailable) {
      return AgentAssignments(plannerAgentId: adapter.id, implementerAgentId: adapter.id, reviewerAgentId: adapter.id);
    }
  }
  throw StateError('No coding agent is available. Install one (${agents.ids.join(', ')}) or add it to agents.json.');
}

/// Location of the optional custom MCP server definitions.
String mcpFilePath(WeaveStoragePaths paths) => path.join(paths.rootDirectory, 'mcp.json');

/// Custom MCP servers from `mcp.json`, without the built-in presets.
Future<List<McpServerDefinition>> loadCustomMcpServers(WeaveStoragePaths paths) async {
  final File file = File(mcpFilePath(paths));
  return await file.exists() ? decodeMcpServers(await file.readAsString()) : const <McpServerDefinition>[];
}

/// Built-in MCP presets plus `mcp.json`, which may replace a preset.
Future<McpRegistry> loadMcpRegistry(WeaveStoragePaths paths) async => McpRegistry.withBuiltIns(customServers: await loadCustomMcpServers(paths));

/// Replaces `mcp.json` with [servers].
Future<void> saveCustomMcpServers(WeaveStoragePaths paths, Iterable<McpServerDefinition> servers) => writeFileAtomically(File(mcpFilePath(paths)), encodeMcpServers(servers));

/// The request's first line, shortened for a subject, plus a reference to
/// the workflow.
String defaultCommitMessage(WorkflowTask task) {
  final String firstLine = task.request.trim().split('\n').first.trim();
  final String subject = firstLine.length > 72 ? '${firstLine.substring(0, 69)}...' : firstLine;
  return '$subject\n\nCreated by Weave workflow ${task.id}.';
}
