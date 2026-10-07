import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_git/weave_git.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

import 'cli_console.dart';

/// Exit codes shared by every command.
abstract final class ExitCodes {
  static const int success = 0;
  static const int failure = 1;
  static const int usage = 64;
  static const int cancelled = 130;
}

/// Runs one `weave` invocation and returns its exit code.
Future<int> runWeaveCli(List<String> arguments, {required WeaveServices services, required CliConsole console, String? currentDirectory, VerificationRunner? verifier}) async {
  final _Context context = _Context(services: services, console: console, currentDirectory: currentDirectory ?? Directory.current.path, verifier: verifier);
  final CommandRunner<int> runner = CommandRunner<int>('weave', 'Coordinate AI coding agents: plan, implement, and review from one request.')
    ..addCommand(_DoctorCommand(context))
    ..addCommand(_AgentsCommand(context))
    ..addCommand(_ConfigCommand(context))
    ..addCommand(_RunCommand(context))
    ..addCommand(_ResumeCommand(context))
    ..addCommand(_ListCommand(context))
    ..addCommand(_ShowCommand(context))
    ..addCommand(_McpCommand(context))
    ..addCommand(_CommitCommand(context));

  try {
    return await runner.run(arguments) ?? ExitCodes.success;
  } on UsageException catch (error) {
    console.error
      ..writeln(error.message)
      ..writeln()
      ..writeln(error.usage);
    return ExitCodes.usage;
  } on _CliFailure catch (failure) {
    console.error.writeln(failure.message);
    return failure.exitCode;
  } on GitException catch (error) {
    console.error.writeln(error);
    return ExitCodes.failure;
  } on WorkflowStartException catch (error) {
    console.error.writeln(error.message);
    return ExitCodes.failure;
  } finally {
    await console.close();
  }
}

final class _Context {
  _Context({required this.services, required this.console, required this.currentDirectory, required this.verifier});

  final WeaveServices services;
  final CliConsole console;
  final String currentDirectory;
  final VerificationRunner? verifier;

  StringSink get out => console.out;

  Future<String> repositoryRoot(String? repository) {
    final String directory = repository ?? currentDirectory;
    return services.git.findRepositoryRoot(Directory(directory).absolute.path);
  }
}

final class _CliFailure implements Exception {
  const _CliFailure(this.message, {this.exitCode = ExitCodes.failure});

  final String message;
  final int exitCode;
}

/// Adds the agent, verification, MCP, model, fallback, checkpoint, and
/// budget options to [parser].
void _addSettingsOptions(ArgParser parser) {
  parser
    ..addOption('repo', abbr: 'r', help: 'Repository path (default: current directory).')
    ..addOption('agent', abbr: 'a', help: 'Agent ID for every role.')
    ..addOption('planner', help: 'Agent ID that plans.')
    ..addOption('implementer', help: 'Agent ID that edits the code.')
    ..addOption('reviewer', help: 'Agent ID that reviews.')
    ..addMultiOption('verify', help: 'Command Weave runs before each review, e.g. "fvm dart test". Repeatable; replaces saved commands.', splitCommas: false)
    ..addOption('max-reviews', help: 'Reviews allowed before the workflow fails.')
    ..addMultiOption('mcp', help: 'MCP server every agent may use, e.g. figma. Repeatable; replaces saved servers.')
    ..addMultiOption('model', help: 'Model for a role\'s agent as role=model, e.g. planner=haiku. Repeatable.', splitCommas: false)
    ..addMultiOption('fallback', help: 'Agent to switch to when a role\'s agent hits a usage limit, as role=agent. Repeatable; replaces saved fallbacks.', splitCommas: false)
    ..addFlag('approve-plan', help: 'Pause for your approval of the plan before any code changes.')
    ..addFlag('approve-changes', help: 'Pause for your approval of the changes before review.')
    ..addFlag('review-plan', help: 'Let the reviewer check the plan before implementation.')
    ..addOption('max-tokens', help: 'Stop the workflow after this many tokens (0 removes the limit).');
}

/// Parses repeatable `role=value` options.
Map<AgentRole, List<String>> _roleValues(ArgResults results, String option) {
  final Map<AgentRole, List<String>> values = <AgentRole, List<String>>{};
  for (final String pair in results.multiOption(option)) {
    final int separator = pair.indexOf('=');
    final AgentRole? role = separator <= 0 ? null : AgentRole.values.asNameMap()[pair.substring(0, separator).trim()];
    final String value = separator <= 0 ? '' : pair.substring(separator + 1).trim();
    if (role == null || value.isEmpty) {
      throw _CliFailure('--$option must look like planner=value, implementer=value, or reviewer=value.', exitCode: ExitCodes.usage);
    }
    values.putIfAbsent(role, () => <String>[]).add(value);
  }
  return values;
}

/// [base] with any settings options from [results] applied.
WorkflowSettings _applySettingsOptions(WorkflowSettings base, ArgResults results, WeaveServices services, {bool clearVerification = false, bool clearMcp = false}) {
  final AgentRegistry agents = services.agents;
  final List<String> mcp = results.multiOption('mcp');
  for (final String id in mcp) {
    if (services.mcp[id] == null) {
      throw _CliFailure('Unknown MCP server "$id". Available servers: ${services.mcp.ids.join(', ')}.', exitCode: ExitCodes.usage);
    }
  }

  String agentFor(AgentRole role) {
    final String id = results.option(role.name) ?? results.option('agent') ?? base.assignments.agentIdFor(role);
    if (agents[id] == null) {
      throw _CliFailure('Unknown agent "$id". Available agents: ${agents.ids.join(', ')}.', exitCode: ExitCodes.usage);
    }
    return id;
  }

  final List<String> verify = results.multiOption('verify');
  final String? maxReviews = results.option('max-reviews');
  final int? maxReviewCycles = maxReviews == null ? null : int.tryParse(maxReviews);
  if (maxReviews != null && (maxReviewCycles == null || maxReviewCycles < 1)) {
    throw const _CliFailure('--max-reviews must be a positive integer.', exitCode: ExitCodes.usage);
  }
  final String? maxTokensOption = results.option('max-tokens');
  final int? maxTokens = maxTokensOption == null ? null : int.tryParse(maxTokensOption);
  if (maxTokensOption != null && (maxTokens == null || maxTokens < 0)) {
    throw const _CliFailure('--max-tokens must be zero or a positive integer.', exitCode: ExitCodes.usage);
  }
  final Map<AgentRole, List<String>> fallbacks = _roleValues(results, 'fallback');
  for (final String id in fallbacks.values.expand((List<String> ids) => ids)) {
    if (agents[id] == null) {
      throw _CliFailure('Unknown fallback agent "$id". Available agents: ${agents.ids.join(', ')}.', exitCode: ExitCodes.usage);
    }
  }
  final Map<AgentRole, List<String>> models = _roleValues(results, 'model');
  bool? flag(String name) => results.wasParsed(name) ? results.flag(name) : null;

  try {
    return base.copyWith(
      assignments: AgentAssignments(plannerAgentId: agentFor(AgentRole.planner), implementerAgentId: agentFor(AgentRole.implementer), reviewerAgentId: agentFor(AgentRole.reviewer)),
      verificationCommands: clearVerification
          ? const <VerificationCommand>[]
          : verify.isEmpty
          ? null
          : <VerificationCommand>[for (final String command in verify) VerificationCommand.parse(command)],
      maxReviewCycles: maxReviewCycles,
      mcpServerIds: clearMcp
          ? const <String>[]
          : mcp.isEmpty
          ? null
          : mcp,
      modelOverrides: models.isEmpty ? null : <AgentRole, String>{...base.modelOverrides, for (final MapEntry<AgentRole, List<String>>(:AgentRole key, :List<String> value) in models.entries) key: value.last},
      fallbackAgentIds: fallbacks.isEmpty ? null : fallbacks,
      requirePlanApproval: flag('approve-plan'),
      requireChangesApproval: flag('approve-changes'),
      reviewPlan: flag('review-plan'),
      maxTokens: maxTokens == 0 ? null : maxTokens,
      clearMaxTokens: maxTokens == 0,
    );
  } on FormatException catch (error) {
    throw _CliFailure('Invalid --verify command: ${error.message}', exitCode: ExitCodes.usage);
  }
}

void _printSettings(StringSink out, WorkflowSettings settings, WeaveServices services) {
  final AgentRegistry agents = services.agents;
  for (final AgentRole role in AgentRole.values) {
    final String id = settings.assignments.agentIdFor(role);
    out.writeln('  ${role.name.padRight(11)} ${agents[id]?.displayName ?? id} ($id)');
  }
  out.writeln('  ${'reviews'.padRight(11)} up to ${settings.maxReviewCycles}');
  if (settings.verificationCommands.isEmpty) {
    out.writeln('  ${'verify'.padRight(11)} (none)');
  }
  for (final VerificationCommand command in settings.verificationCommands) {
    out.writeln('  ${'verify'.padRight(11)} ${command.label}');
  }
  out.writeln('  ${'mcp'.padRight(11)} ${settings.mcpServerIds.isEmpty ? '(none)' : settings.mcpServerIds.map((String id) => '${services.mcp[id]?.displayName ?? id} ($id)').join(', ')}');
  for (final MapEntry<AgentRole, String>(:AgentRole key, :String value) in settings.modelOverrides.entries) {
    out.writeln('  ${'model'.padRight(11)} ${key.name}: $value');
  }
  for (final MapEntry<AgentRole, List<String>>(:AgentRole key, :List<String> value) in settings.fallbackAgentIds.entries) {
    out.writeln('  ${'fallback'.padRight(11)} ${key.name}: ${value.join(' → ')}');
  }
  final List<String> pauses = <String>[if (settings.reviewPlan) 'reviewer checks the plan', if (settings.requirePlanApproval) 'you approve the plan', if (settings.requireChangesApproval) 'you approve the changes'];
  out
    ..writeln('  ${'checkpoints'.padRight(11)} ${pauses.isEmpty ? 'automatic' : pauses.join(', ')}')
    ..writeln('  ${'budget'.padRight(11)} ${settings.maxTokens == null ? 'no token limit' : '${settings.maxTokens} tokens'}');
}

final class _DoctorCommand extends Command<int> {
  _DoctorCommand(this.context);

  final _Context context;

  @override
  String get name => 'doctor';

  @override
  String get description => 'Check Git, storage, and every configured agent.';

  @override
  Future<int> run() async {
    final StringSink out = context.out;
    final GitCommandResult git = await ProcessGitCommandRunner(environment: context.services.environment).run(const <String>['--version'], workingDirectory: Directory.systemTemp.path);
    final bool gitOk = git.exitCode == 0;
    out
      ..writeln('Git:     ${gitOk ? git.stdout.trim() : 'not working (exit ${git.exitCode})'}')
      ..writeln('Storage: ${context.services.paths.rootDirectory}')
      ..writeln('Agents:  ${agentsFilePath(context.services.paths)}${File(agentsFilePath(context.services.paths)).existsSync() ? '' : ' (not created; built-in agents only)'}')
      ..writeln();

    int available = 0;
    for (final AgentAdapter adapter in context.services.agents.adapters) {
      final AgentAvailability availability = await adapter.checkAvailability();
      if (availability.isAvailable) {
        available++;
        out.writeln('  ok      ${adapter.id.padRight(14)} ${availability.version} (${availability.executablePath})');
      } else if (availability.needsSignIn) {
        out.writeln('  sign in ${adapter.id.padRight(14)} ${availability.reason}');
      } else {
        out.writeln('  missing ${adapter.id.padRight(14)} ${availability.reason}');
      }
    }
    if (available == 0) {
      out.writeln('\nNo agent is ready. Install one and sign in to it, or add one to agents.json.');
    }
    return gitOk && available > 0 ? ExitCodes.success : ExitCodes.failure;
  }
}

final class _AgentsCommand extends Command<int> {
  _AgentsCommand(this.context);

  final _Context context;

  @override
  String get name => 'agents';

  @override
  String get description => 'List the agents that can be assigned to roles.';

  @override
  Future<int> run() async {
    for (final AgentAdapter adapter in context.services.agents.adapters) {
      final String detail = adapter is CommandAgentAdapter ? '${adapter.definition.executable}, ${adapter.definition.outputFormat.jsonName}' : 'in-process';
      context.out.writeln('${adapter.id.padRight(16)} ${adapter.displayName} ($detail)');
    }
    context.out.writeln('\nAdd or override agents in ${agentsFilePath(context.services.paths)}.');
    return ExitCodes.success;
  }
}

final class _ConfigCommand extends Command<int> {
  _ConfigCommand(this.context) {
    _addSettingsOptions(argParser);
    argParser
      ..addFlag('clear-verify', negatable: false, help: 'Remove every saved verification command.')
      ..addFlag('clear-mcp', negatable: false, help: 'Remove every saved MCP server.');
  }

  final _Context context;

  @override
  String get name => 'config';

  @override
  String get description => 'Show or save the default workflow settings of a repository.';

  @override
  Future<int> run() async {
    final ArgResults results = argResults!;
    final String root = await context.repositoryRoot(results.option('repo'));
    final WorkflowSettings current = await context.services.settingsFor(root);
    final bool changes = results.options.any((String option) => option != 'repo' && results.wasParsed(option));
    final WorkflowSettings settings = _applySettingsOptions(current, results, context.services, clearVerification: results.flag('clear-verify'), clearMcp: results.flag('clear-mcp'));

    if (changes) {
      await context.services.settings.saveProjectDefaults(root, settings);
      context.out.writeln('Saved defaults for $root:');
    } else {
      context.out.writeln('Defaults for $root:');
    }
    _printSettings(context.out, settings, context.services);
    return ExitCodes.success;
  }
}

final class _RunCommand extends Command<int> {
  _RunCommand(this.context) {
    _addSettingsOptions(argParser);
    argParser
      ..addFlag('no-mcp-prompt', negatable: false, help: 'Do not offer MCP servers for links in the request.')
      ..addMultiOption('also', help: 'Another repository the agents may read; after planning you choose which repositories may be edited. Repeatable.', splitCommas: false, valueHelp: 'path');
  }

  final _Context context;

  @override
  String get name => 'run';

  @override
  String get description => 'Plan, implement, and review one request.';

  @override
  String get invocation => 'weave run [options] <request>';

  @override
  Future<int> run() async {
    final ArgResults results = argResults!;
    final String request = results.rest.join(' ').trim();
    if (request.isEmpty) {
      usageException('Describe the change to make.');
    }

    final String root = await context.repositoryRoot(results.option('repo'));
    final WorkflowSettings base;
    try {
      base = await context.services.settingsFor(root);
    } on StateError catch (error) {
      throw _CliFailure(error.message);
    }
    WorkflowSettings settings = _applySettingsOptions(base, results, context.services);
    if (!results.flag('no-mcp-prompt')) {
      settings = await _offerMcpServers(request, settings);
    }
    final List<String> also = <String>[for (final String path in results.multiOption('also')) await context.repositoryRoot(path)];
    final WorkflowRun run = await context.services.createOrchestrator(verifier: context.verifier).start(request: request, repositoryPath: root, additionalRepositoryPaths: also, settings: settings);

    context.out
      ..writeln('Workflow ${run.task.id} in $root')
      ..writeln();
    _printSettings(context.out, settings, context.services);
    context.out.writeln();
    return _follow(context, run);
  }
}

/// Prints a run until it finishes, answering prompts from stdin; Ctrl+C
/// cancels it. Returns the exit code for its final status.
Future<int> _follow(_Context context, WorkflowRun run) async {
  final StringSink out = context.out;
  final StreamSubscription<void> interrupts = context.console.interrupts.listen((void _) {
    out.writeln('\nCancelling...');
    unawaited(run.cancel());
  });
  // Copy the history and subscribe in one synchronous step, so no event is
  // missed or repeated while a prompt waits for input.
  final StreamController<WorkflowEvent> queue = StreamController<WorkflowEvent>();
  run.history.forEach(queue.add);
  final StreamSubscription<WorkflowEvent> forwarding = run.events.listen(queue.add, onDone: queue.close);
  final _EventPrinter printer = _EventPrinter(context.console);
  await for (final WorkflowEvent event in queue.stream) {
    await printer.print(event, run);
  }

  final WorkflowTask task = await run.result;
  await forwarding.cancel();
  await interrupts.cancel();

  out
    ..writeln('Usage: ${run.usage}')
    ..writeln('\nDetails: weave show ${task.id}');
  return switch (task.status) {
    WorkflowStatus.completed => ExitCodes.success,
    WorkflowStatus.cancelled => ExitCodes.cancelled,
    _ => ExitCodes.failure,
  };
}

final class _ResumeCommand extends Command<int> {
  _ResumeCommand(this.context);

  final _Context context;

  @override
  String get name => 'resume';

  @override
  String get description => 'Continue a workflow that stopped before finishing, e.g. after a network drop or closing Weave.';

  @override
  String get invocation => 'weave resume <workflow-id>';

  @override
  Future<int> run() async {
    final List<String> rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Pass exactly one workflow ID.');
    }
    final WorkflowRun run = await context.services.createOrchestrator(verifier: context.verifier).resume(rest.single);
    context.out.writeln('Resuming workflow ${run.task.id} (${run.task.status.name})\n');
    return _follow(context, run);
  }
}

extension on _RunCommand {
  /// Asks whether to enable an MCP server for links in [request] that no
  /// enabled server handles, e.g. a Figma design link.
  Future<WorkflowSettings> _offerMcpServers(String request, WorkflowSettings settings) async {
    final List<McpServerDefinition> suggestions = context.services.mcp.suggestionsFor(request, enabledIds: settings.mcpServerIds);
    if (suggestions.isEmpty) {
      return settings;
    }
    final StringSink out = context.out..writeln('The request links to a service an MCP server can open:');
    for (int index = 0; index < suggestions.length; index++) {
      final McpServerDefinition server = suggestions[index];
      out.writeln('  ${index + 1}) ${server.displayName} (${server.id})${server.setupHint == null ? '' : ' — ${server.setupHint}'}');
    }
    out.write('Enable one for this workflow? [1-${suggestions.length}, Enter to skip] ');
    final String answer = (await context.console.readLine())?.trim() ?? '';
    final int? choice = int.tryParse(answer);
    if (choice == null || choice < 1 || choice > suggestions.length) {
      out.writeln('Continuing without MCP.');
      return settings;
    }
    final McpServerDefinition chosen = suggestions[choice - 1];
    out.writeln('Enabled ${chosen.displayName}. Save it for this repository with: weave config --mcp ${chosen.id}');
    return settings.copyWith(mcpServerIds: <String>[...settings.mcpServerIds, chosen.id]);
  }
}

/// Renders workflow events and answers approval requests from stdin.
final class _EventPrinter {
  _EventPrinter(this.console);

  final CliConsole console;

  Future<void> _answerCheckpoint(WorkflowCheckpoint checkpoint, WorkflowRun run) async {
    final StringSink out = console.out
      ..writeln()
      ..writeln('== ${checkpoint.title}')
      ..writeln(checkpoint.details.trimRight())
      ..writeln();
    // Ask until the answer is valid, then stop: the run clears the
    // checkpoint asynchronously, so re-checking it here would read the next
    // checkpoint's answer.
    while (run.pendingCheckpoint?.id == checkpoint.id) {
      if (checkpoint.kind == WorkflowCheckpointKind.repositories) {
        out.writeln('Approve allows edits to the repositories the plan changes; the others stay read-only.');
      }
      out.write(checkpoint.allowsRevision ? '[a]pprove, [r]evise, or [c]ancel? ' : '[r]etry or [c]ancel? ');
      final String answer = ((await console.readLine()) ?? 'c').trim().toLowerCase();
      if (run.pendingCheckpoint?.id != checkpoint.id) {
        return;
      }
      if (answer.startsWith('c')) {
        run.resolveCheckpoint(checkpoint.id, CheckpointDecision.cancel);
        return;
      }
      if (checkpoint.allowsRevision && answer.startsWith('r')) {
        out.write('What should change? ');
        final String feedback = (await console.readLine() ?? '').trim();
        if (run.pendingCheckpoint?.id == checkpoint.id) {
          run.resolveCheckpoint(checkpoint.id, CheckpointDecision.revise, feedback: feedback);
        }
        return;
      }
      if (answer.startsWith(checkpoint.allowsRevision ? 'a' : 'r')) {
        run.resolveCheckpoint(checkpoint.id, CheckpointDecision.approve);
        return;
      }
    }
  }

  Future<void> print(WorkflowEvent event, WorkflowRun run) async {
    final StringSink out = console.out;
    switch (event) {
      case WorkflowStatusChanged(:final WorkflowTask task):
        out.writeln('== ${task.status.name}${task.reviewCycle > 0 ? ' (review round ${task.reviewCycle})' : ''}');
      case WorkflowAgentStarted(:final AgentRole role, :final String agentId, :final String phase):
        out.writeln('[${role.name}] $agentId: $phase');
      case WorkflowAgentOutput(:final AgentRole role, :final String text, :final AgentOutputChannel channel):
        final StringSink sink = channel == AgentOutputChannel.stderr ? console.error : out;
        for (final String line in text.split('\n')) {
          if (line.isNotEmpty) {
            sink.writeln('[${role.name}] $line');
          }
        }
      case WorkflowApprovalRequested(:final AgentRole role, :final String approvalId, :final String action, :final String details):
        out
          ..writeln('[${role.name}] approval needed: $action')
          ..writeln(details)
          ..write('Approve? [y/N] ');
        final String? answer = await console.readLine();
        final ApprovalDecision decision = answer != null && <String>{'y', 'yes'}.contains(answer.trim().toLowerCase()) ? ApprovalDecision.approve : ApprovalDecision.deny;
        if (run.pendingApprovals.contains(approvalId)) {
          await run.resolveApproval(approvalId, decision);
        }
      case WorkflowApprovalResolved(:final String approvalId, :final ApprovalDecision decision):
        out.writeln('Approval $approvalId: ${decision.name}');
      case WorkflowVerificationFinished(:final List<VerificationResult> results):
        for (final VerificationResult result in results) {
          out.writeln('[verify] ${result.passed ? 'PASS' : 'FAIL'} ${result.command.label}');
        }
      case WorkflowArtifactSaved():
        break;
      case WorkflowAgentFinished(:final AgentRole role, :final String agentId, :final String phase, :final AgentUsage? usage):
        if (usage != null) {
          out.writeln('[${role.name}] $agentId finished $phase — $usage');
        }
      case WorkflowRetryScheduled(:final AgentRole role, :final String agentId, :final int attempt, :final int maxAttempts, :final Duration delay, :final String reason):
        out.writeln('[${role.name}] $agentId lost its connection ($reason); retrying in ${delay.inSeconds}s, attempt $attempt of $maxAttempts');
      case WorkflowAgentSwitched(:final AgentRole role, :final String fromAgentId, :final String toAgentId, :final String reason):
        out.writeln('[${role.name}] switched from $fromAgentId to $toAgentId: $reason');
      case WorkflowChecklistUpdated(:final WorkflowChecklist checklist):
        out.writeln('[checklist] ${event.message.replaceFirst('Checklist: ', '')}');
        for (final ChecklistItem item in checklist.needingChanges) {
          out.writeln('  ${item.id} needs changes: ${item.note ?? item.title}');
        }
      case WorkflowCheckpointRequested(:final WorkflowCheckpoint checkpoint):
        await _answerCheckpoint(checkpoint, run);
      case WorkflowCheckpointResolved():
        break;
      case WorkflowFinished(:final WorkflowTask task, :final String? reason):
        out.writeln('\nFinished: ${task.status.name}${reason == null ? '' : ' — $reason'}');
    }
  }
}

final class _ListCommand extends Command<int> {
  _ListCommand(this.context);

  final _Context context;

  @override
  String get name => 'list';

  @override
  String get description => 'List workflows, most recently updated first.';

  @override
  Future<int> run() async {
    final List<WorkflowTask> tasks = await context.services.tasks.list();
    if (tasks.isEmpty) {
      context.out.writeln('No workflows yet. Start one with: weave run "<request>"');
    }
    final WorkflowOrchestrator orchestrator = context.services.createOrchestrator();
    bool anyInterrupted = false;
    for (final WorkflowTask task in tasks) {
      final String request = task.request.split('\n').first;
      final bool interrupted = await orchestrator.isInterrupted(task);
      anyInterrupted |= interrupted;
      final String status = interrupted ? '${task.status.name} (interrupted)' : task.status.name;
      context.out.writeln('${task.id}  ${status.padRight(36)} ${task.updatedAt.toLocal().toString().substring(0, 16)}  ${request.length > 60 ? '${request.substring(0, 57)}...' : request}');
    }
    if (anyInterrupted) {
      context.out.writeln('\nContinue an interrupted workflow with: weave resume <workflow-id>');
    }
    return ExitCodes.success;
  }
}

final class _ShowCommand extends Command<int> {
  _ShowCommand(this.context) {
    argParser.addFlag('log', negatable: false, help: 'Also print the event log.');
  }

  final _Context context;

  @override
  String get name => 'show';

  @override
  String get description => 'Show a workflow with its plan, reviews, and verification.';

  @override
  String get invocation => 'weave show [--log] <workflow-id>';

  @override
  Future<int> run() async {
    final List<String> rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Pass exactly one workflow ID.');
    }
    final WorkflowTask? task = await context.services.tasks.load(rest.single);
    if (task == null) {
      throw _CliFailure('No workflow with ID ${rest.single}.');
    }

    final StringSink out = context.out
      ..writeln('Workflow:   ${task.id}')
      ..writeln('Status:     ${task.status.name}')
      ..writeln('Repository: ${task.repositoryPath}')
      ..writeln('Created:    ${task.createdAt.toLocal()}')
      ..writeln('Updated:    ${task.updatedAt.toLocal()}')
      ..writeln('Rounds:     ${task.reviewCycle}')
      ..writeln()
      ..writeln('Request:')
      ..writeln(task.request);

    final WorkflowSettings? settings = await context.services.settings.loadForTask(task.id);
    if (settings != null) {
      out
        ..writeln()
        ..writeln('Settings:');
      _printSettings(out, settings, context.services);
    }

    final WorkflowRunState? state = await context.services.runStates.load(task.id);
    if (state != null) {
      out
        ..writeln()
        ..writeln('Usage:      ${state.totalUsage}');
      for (final MapEntry<AgentRole, AgentUsage>(:AgentRole key, :AgentUsage value) in state.usage.entries) {
        out.writeln('  ${key.name.padRight(11)} ${state.activeAgents[key] ?? settings?.assignments.agentIdFor(key) ?? '?'}: $value');
      }
      if (!state.checklist.isEmpty) {
        out
          ..writeln()
          ..writeln('Checklist:');
        for (final ChecklistItem item in state.checklist.items) {
          final String agents = <String>[if (item.implementedBy case final String implementer) 'by $implementer', if (item.reviewedBy case final String reviewer) 'reviewed by $reviewer'].join(', ');
          out.writeln('  ${item.id.padRight(5)} ${item.status.name.padRight(12)} ${item.title}${agents.isEmpty ? '' : ' ($agents)'}${item.note == null ? '' : ' — ${item.note}'}');
        }
      }
    }

    for (final WorkflowArtifact artifact in await context.services.artifacts.readArtifacts(task.id)) {
      out
        ..writeln()
        ..writeln('## ${artifact.kind.name} (round ${artifact.cycle})')
        ..writeln(artifact.content.trimRight());
    }

    if (argResults!.flag('log')) {
      out
        ..writeln()
        ..writeln('## log');
      for (final WorkflowLogEntry entry in await context.services.artifacts.readLog(task.id)) {
        out.writeln('${entry.timestamp.toLocal().toString().substring(11, 19)} [${entry.source}] ${entry.message.trimRight()}');
      }
    }
    return ExitCodes.success;
  }
}

final class _McpCommand extends Command<int> {
  _McpCommand(_Context context) {
    addSubcommand(_McpListCommand(context));
    addSubcommand(_McpAddCommand(context));
    addSubcommand(_McpRemoveCommand(context));
  }

  @override
  String get name => 'mcp';

  @override
  String get description => 'List, add, or remove MCP servers (Figma and others) that agents may use.';
}

final class _McpListCommand extends Command<int> {
  _McpListCommand(this.context);

  final _Context context;

  @override
  String get name => 'list';

  @override
  String get description => 'List built-in and custom MCP servers.';

  @override
  Future<int> run() async {
    for (final McpServerDefinition server in context.services.mcp.servers) {
      final String transport = switch (server.transport) {
        McpHttpTransport(:final String url) => url,
        McpStdioTransport(:final String command, :final List<String> arguments) => <String>[command, ...arguments].join(' '),
      };
      context.out.writeln('${server.id.padRight(16)} ${server.displayName} — $transport');
      if (server.setupHint case final String hint) {
        context.out.writeln('${''.padRight(16)} $hint');
      }
    }
    context.out
      ..writeln()
      ..writeln('Enable one per run with --mcp <id>, or by default with: weave config --mcp <id>')
      ..writeln('Custom servers are stored in ${mcpFilePath(context.services.paths)}.');
    return ExitCodes.success;
  }
}

final class _McpAddCommand extends Command<int> {
  _McpAddCommand(this.context) {
    argParser
      ..addOption('name', help: 'Display name (default: the ID).')
      ..addOption('url', help: 'Streamable HTTP endpoint, e.g. https://mcp.example.com/mcp.')
      ..addOption('command', help: 'Executable that starts a local (stdio) server, e.g. npx.')
      ..addMultiOption('arg', help: 'Argument for --command. Repeatable.', splitCommas: false)
      ..addMultiOption('env', help: r'NAME=value for --command; use ${VAR} to read a secret from the environment. Repeatable.', splitCommas: false)
      ..addMultiOption('header', help: r'Name=value for --url; use ${VAR} for tokens. Repeatable.', splitCommas: false)
      ..addMultiOption('link', help: 'Regular expression for links this server opens; Weave offers it when a request contains one. Repeatable.', splitCommas: false)
      ..addOption('hint', help: 'Setup instructions shown when the server is offered.');
  }

  final _Context context;

  @override
  String get name => 'add';

  @override
  String get description => 'Add or replace a custom MCP server.';

  @override
  String get invocation => 'weave mcp add <id> (--url <url> | --command <executable> [--arg <value>]...) [options]';

  @override
  Future<int> run() async {
    final ArgResults results = argResults!;
    if (results.rest.length != 1) {
      usageException('Pass exactly one server ID.');
    }
    final String? url = results.option('url');
    final String? command = results.option('command');
    if ((url == null) == (command == null)) {
      usageException('Pass either --url or --command.');
    }

    Map<String, String> pairs(String option) {
      final Map<String, String> values = <String, String>{};
      for (final String pair in results.multiOption(option)) {
        final int separator = pair.indexOf('=');
        if (separator <= 0) {
          throw _CliFailure('--$option must look like NAME=value.', exitCode: ExitCodes.usage);
        }
        values[pair.substring(0, separator)] = pair.substring(separator + 1);
      }
      return values;
    }

    final McpServerDefinition server;
    try {
      server = McpServerDefinition(
        id: results.rest.single,
        displayName: results.option('name') ?? results.rest.single,
        transport: url != null ? McpHttpTransport(url: url, headers: pairs('header')) : McpStdioTransport(command: command!, arguments: results.multiOption('arg'), environment: pairs('env')),
        linkPatterns: results.multiOption('link'),
        setupHint: results.option('hint'),
      );
    } on ArgumentError catch (error) {
      throw _CliFailure('Invalid MCP server: ${error.message}', exitCode: ExitCodes.usage);
    }

    final List<McpServerDefinition> custom = await loadCustomMcpServers(context.services.paths);
    await saveCustomMcpServers(context.services.paths, <McpServerDefinition>[
      for (final McpServerDefinition existing in custom)
        if (existing.id != server.id) existing,
      server,
    ]);
    context.out.writeln('Saved MCP server ${server.id} to ${mcpFilePath(context.services.paths)}.');
    return ExitCodes.success;
  }
}

final class _McpRemoveCommand extends Command<int> {
  _McpRemoveCommand(this.context);

  final _Context context;

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove a custom MCP server.';

  @override
  String get invocation => 'weave mcp remove <id>';

  @override
  Future<int> run() async {
    final List<String> rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Pass exactly one server ID.');
    }
    final List<McpServerDefinition> custom = await loadCustomMcpServers(context.services.paths);
    if (!custom.any((McpServerDefinition server) => server.id == rest.single)) {
      throw _CliFailure('${rest.single} is not a custom MCP server; built-in presets can be overridden with "weave mcp add" but not removed.');
    }
    await saveCustomMcpServers(context.services.paths, <McpServerDefinition>[
      for (final McpServerDefinition server in custom)
        if (server.id != rest.single) server,
    ]);
    context.out.writeln('Removed MCP server ${rest.single}.');
    return ExitCodes.success;
  }
}

final class _CommitCommand extends Command<int> {
  _CommitCommand(this.context) {
    argParser.addOption('message', abbr: 'm', help: 'Commit message (default: the first line of the request).');
  }

  final _Context context;

  @override
  String get name => 'commit';

  @override
  String get description => 'Commit the changes of a completed workflow after you approve them.';

  @override
  String get invocation => 'weave commit [-m <message>] <workflow-id>';

  @override
  Future<int> run() async {
    final List<String> rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Pass exactly one workflow ID.');
    }
    final WorkflowTask? task = await context.services.tasks.load(rest.single);
    if (task == null) {
      throw _CliFailure('No workflow with ID ${rest.single}.');
    }
    if (task.status != WorkflowStatus.completed) {
      throw _CliFailure('Only completed workflows can be committed; ${task.id} is ${task.status.name}.');
    }

    final String message = argResults!.option('message') ?? defaultCommitMessage(task);
    final StringSink out = context.out;
    try {
      final GitCommitResult result = await context.services.gitWriter.commitAll(
        task.repositoryPath,
        message: message,
        approve: (GitWriteRequest request) async {
          out
            ..writeln('${request.summary} in ${request.repositoryRoot}:')
            ..writeln(<String>[for (final String path in request.paths.take(20)) '  $path', if (request.paths.length > 20) '  ... and ${request.paths.length - 20} more'].join('\n'))
            ..writeln()
            ..writeln('Message:')
            ..writeln(message)
            ..write('Commit? [y/N] ');
          final String? answer = await context.console.readLine();
          return answer != null && <String>{'y', 'yes'}.contains(answer.trim().toLowerCase());
        },
      );
      out.writeln('Committed ${result.commitSha.substring(0, 12)} on ${result.branch ?? 'detached HEAD'}.');
      return ExitCodes.success;
    } on GitApprovalDeniedException {
      out.writeln('Commit cancelled; nothing was changed.');
      return ExitCodes.failure;
    } on GitNothingToCommitException {
      throw const _CliFailure('There are no changes to commit.');
    } on GitCommandException catch (error) {
      throw _CliFailure('${error.message}. Check your Git identity (user.name, user.email) and commit hooks.');
    }
  }
}
