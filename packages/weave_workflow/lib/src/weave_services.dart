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

  /// Built-in plus custom agents; refreshed by [reloadAgents].
  AgentRegistry agents;

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

  /// Deletes a finished or stopped workflow and its history from Weave's
  /// storage. The repository it worked on is left untouched.
  ///
  /// Throws [StateError] while another Weave process (e.g. the CLI) runs it.
  Future<void> deleteWorkflow(String taskId) async {
    if (await locks.isHeldElsewhere(taskId)) {
      throw StateError('This workflow is running in another Weave window or the CLI. Stop it there first.');
    }
    await tasks.delete(taskId);
  }

  /// Re-reads `agents.json` after it was changed.
  Future<void> reloadAgents() async => agents = await loadAgentRegistry(paths, environment: environment);

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

/// The definitions in `agents.json`, without the built-in presets.
Future<List<AgentDefinition>> loadCustomAgents(WeaveStoragePaths paths) async {
  final File file = File(agentsFilePath(paths));
  return await file.exists() ? decodeAgentDefinitions(await file.readAsString()) : const <AgentDefinition>[];
}

/// Adds [definition] to `agents.json`, replacing one with the same ID.
Future<void> saveCustomAgent(WeaveStoragePaths paths, AgentDefinition definition) async {
  final List<AgentDefinition> agents = <AgentDefinition>[
    for (final AgentDefinition existing in await loadCustomAgents(paths))
      if (existing.id != definition.id) existing,
    definition,
  ];
  await writeFileAtomically(File(agentsFilePath(paths)), encodeAgentDefinitions(agents));
}

/// Removes the custom agent [id] from `agents.json`; a built-in it replaced
/// comes back.
Future<void> removeCustomAgent(WeaveStoragePaths paths, String id) async {
  await writeFileAtomically(
    File(agentsFilePath(paths)),
    encodeAgentDefinitions(<AgentDefinition>[
      for (final AgentDefinition existing in await loadCustomAgents(paths))
        if (existing.id != id) existing,
    ]),
  );
}

/// Built-in agents plus those in `agents.json`, which may replace a preset,
/// plus every account in `accounts.json` whose agent supports accounts.
Future<AgentRegistry> loadAgentRegistry(WeaveStoragePaths paths, {Map<String, String>? environment}) async {
  final File file = File(agentsFilePath(paths));
  final List<AgentDefinition> customDefinitions = await file.exists() ? decodeAgentDefinitions(await file.readAsString()) : const <AgentDefinition>[];
  final Map<String, AgentDefinition> definitions = <String, AgentDefinition>{
    for (final AgentDefinition definition in <AgentDefinition>[...AgentRegistry.builtInDefinitions, ...customDefinitions]) definition.id: definition,
  };
  return AgentRegistry.fromDefinitions(
    customDefinitions: <AgentDefinition>[
      ...customDefinitions,
      for (final AgentAccount account in await loadAgentAccounts(paths))
        // An account whose agent was removed, or that clashes with an agent ID, is skipped.
        if (definitions[account.agentId] case final AgentDefinition agent when agent.supportsAccounts && !definitions.containsKey(account.id)) agent.forAccount(account, directory: agentAccountDirectory(paths, account.id)),
    ],
    environment: environment,
  );
}

/// Location of the accounts Weave added for agents that support several.
String accountsFilePath(WeaveStoragePaths paths) => path.join(paths.rootDirectory, 'accounts.json');

/// The configuration folder of account [id]; the agent keeps that
/// account's sign-in there.
String agentAccountDirectory(WeaveStoragePaths paths, String id) => path.join(paths.rootDirectory, 'accounts', id);

/// The accounts in `accounts.json`.
Future<List<AgentAccount>> loadAgentAccounts(WeaveStoragePaths paths) async {
  final File file = File(accountsFilePath(paths));
  return await file.exists() ? decodeAgentAccounts(await file.readAsString()) : const <AgentAccount>[];
}

/// Adds an account named [name] for [agentId] to `accounts.json`, creates
/// its configuration folder, and returns it. Its ID is the agent ID plus the
/// name, made unique among [takenIds].
Future<AgentAccount> addAgentAccount(WeaveStoragePaths paths, {required String agentId, required String name, required Set<String> takenIds}) async {
  final List<AgentAccount> accounts = await loadAgentAccounts(paths);
  final String slug = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  final String base = slug.isEmpty ? '$agentId-account' : '$agentId-$slug';
  final Set<String> taken = <String>{...takenIds, for (final AgentAccount account in accounts) account.id};
  String id = base.length > 60 ? base.substring(0, 60) : base;
  for (int suffix = 2; taken.contains(id); suffix++) {
    id = '${base.length > 56 ? base.substring(0, 56) : base}-$suffix';
  }
  final AgentAccount account = AgentAccount(id: id, agentId: agentId, name: name);
  await Directory(agentAccountDirectory(paths, id)).create(recursive: true);
  await writeFileAtomically(File(accountsFilePath(paths)), encodeAgentAccounts(<AgentAccount>[...accounts, account]));
  return account;
}

/// Removes account [id] from `accounts.json` and deletes its configuration
/// folder, which signs that account out of the agent on this Mac.
Future<void> removeAgentAccount(WeaveStoragePaths paths, String id) async {
  await writeFileAtomically(
    File(accountsFilePath(paths)),
    encodeAgentAccounts(<AgentAccount>[
      for (final AgentAccount existing in await loadAgentAccounts(paths))
        if (existing.id != id) existing,
    ]),
  );
  final Directory directory = Directory(agentAccountDirectory(paths, id));
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
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
