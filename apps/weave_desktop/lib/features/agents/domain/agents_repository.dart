import 'package:weave_agents/weave_agents.dart';

/// Agent data needed by the desktop application.
abstract interface class AgentsRepository {
  List<AgentAdapter> get agents;

  String get configurationPath;

  Future<List<AgentAvailability>> checkAvailability();

  /// The plan limits [agentId]'s own CLI reports, read without running a model.
  /// Throws [AgentPlanUsageException] when they cannot be read.
  Future<AgentPlanUsage> readPlanUsage(String agentId);

  /// IDs of the agents defined in `agents.json` (which may replace a preset).
  Future<Set<String>> customAgentIds();

  /// Adds or replaces [definition] in `agents.json` and reloads the agents.
  Future<void> saveAgent(AgentDefinition definition);

  /// Removes [agentId] from `agents.json` and reloads the agents.
  Future<void> removeAgent(String agentId);

  /// Adds an account named [name] of [agentId], with its own configuration
  /// folder, and reloads the agents; the new account is not signed in yet.
  Future<AgentAccount> addAccount(String agentId, String name);

  /// Removes account [accountId] and its configuration folder, then reloads
  /// the agents.
  Future<void> removeAccount(String accountId);

  /// Who [agentId] is signed in as, or `null` when unknown.
  Future<AgentAccountInfo?> readAccount(String agentId);

  /// Whether [executable] is found on this Mac (`PATH` or an absolute path).
  Future<bool> isInstalled(String executable);

  /// Opens [command] (an agent's sign-in) in Terminal.
  Future<void> openInTerminal(String command, {required String name});
}
