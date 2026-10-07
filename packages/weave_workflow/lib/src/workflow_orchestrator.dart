import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_git/weave_git.dart';
import 'package:weave_storage/weave_storage.dart';

import 'repository_fingerprint.dart';
import 'verification.dart';
import 'workflow_checklist.dart';
import 'workflow_events.dart';
import 'workflow_prompts.dart';
import 'workflow_repositories.dart';
import 'workflow_run_lock.dart';
import 'workflow_run_state.dart';
import 'workflow_settings.dart';

/// Raised before a workflow starts or resumes when it cannot run at all.
final class WorkflowStartException implements Exception {
  const WorkflowStartException(this.message);

  final String message;

  @override
  String toString() => 'WorkflowStartException: $message';
}

/// Runs the plan → implement → self-review → verify → review loop with any
/// agents from an [AgentRegistry], and resumes runs that were interrupted.
final class WorkflowOrchestrator {
  WorkflowOrchestrator({
    required this._agents,
    required this._tasks,
    required this._artifacts,
    this._settingsStore,
    this._runStates,
    this._locks,
    GitRepositoryService? git,
    VerificationRunner? verifier,
    this.prompts = const DefaultWorkflowPrompts(),
    this.maxDiffCharacters = 200 * 1024,
    this._clock = DateTime.now,
    this._createTaskId,
    McpRegistry? mcpServers,
    Map<String, String>? environment,
  }) : _git = git ?? GitRepositoryService(),
       _verifier = verifier ?? ProcessVerificationRunner(),
       _mcpServers = mcpServers ?? McpRegistry.withBuiltIns(),
       _environment = environment ?? Platform.environment;

  final AgentRegistry _agents;
  final WorkflowTaskStore _tasks;
  final WorkflowArtifactStore _artifacts;
  final FileWorkflowSettingsStore? _settingsStore;
  final FileWorkflowRunStateStore? _runStates;
  final WorkflowRunLock? _locks;
  final GitRepositoryService _git;
  final VerificationRunner _verifier;
  final DateTime Function() _clock;
  final String Function()? _createTaskId;
  final McpRegistry _mcpServers;

  /// Source of `${NAME}` values in MCP server definitions.
  final Map<String, String> _environment;
  final WorkflowPrompts prompts;
  final int maxDiffCharacters;

  /// Validates the repository and agents, saves a new task, and starts it.
  ///
  /// The returned run is already executing; listen to [WorkflowRun.events]
  /// or read [WorkflowRun.history] for progress.
  ///
  /// [additionalRepositoryPaths] adds further repositories: every agent may
  /// read them, and after planning the user chooses which ones the
  /// implementer may edit. Settings and verification belong to
  /// [repositoryPath].
  Future<WorkflowRun> start({required String request, required String repositoryPath, List<String> additionalRepositoryPaths = const <String>[], required WorkflowSettings settings}) async {
    if (request.trim().isEmpty) {
      throw const WorkflowStartException('The request must not be empty.');
    }
    final String repositoryRoot = await _git.findRepositoryRoot(repositoryPath);
    final List<String> additionalRoots = <String>[for (final String path in additionalRepositoryPaths) await _git.findRepositoryRoot(path)];
    final List<McpServerDefinition> mcpServers = await _prepare(settings);

    final WorkflowTask task = WorkflowTask.create(id: _createTaskId?.call() ?? _defaultTaskId(), request: request, repositoryPath: repositoryRoot, additionalRepositoryPaths: additionalRoots, createdAt: _clock());
    await _tasks.save(task);
    await _settingsStore?.saveForTask(task.id, settings);
    return _launch(task, settings, mcpServers, WorkflowRunState());
  }

  /// Continues a workflow that stopped before finishing, e.g. because Weave
  /// was closed or the machine went offline.
  Future<WorkflowRun> resume(String taskId) async {
    final WorkflowTask? task = await _tasks.load(taskId);
    if (task == null) {
      throw WorkflowStartException('No workflow with ID $taskId.');
    }
    if (task.isTerminal) {
      throw WorkflowStartException('Workflow $taskId already ${task.status.name}.');
    }
    if (await _locks?.isHeldElsewhere(taskId) ?? false) {
      throw WorkflowStartException('Workflow $taskId is still running in another Weave window or terminal.');
    }
    final WorkflowSettings? settings = await _settingsStore?.loadForTask(taskId);
    if (settings == null) {
      throw WorkflowStartException('The settings of workflow $taskId were not found, so it cannot resume.');
    }
    for (final String repository in task.repositoryPaths) {
      await _git.findRepositoryRoot(repository);
    }
    final List<McpServerDefinition> mcpServers = await _prepare(settings);
    return _launch(task, settings, mcpServers, await _runStates?.load(taskId) ?? WorkflowRunState());
  }

  /// Whether [task] stopped mid-run and can be resumed.
  Future<bool> isInterrupted(WorkflowTask task) async => !task.isTerminal && !(await _locks?.isHeldElsewhere(task.id) ?? false);

  Future<WorkflowRun> _launch(WorkflowTask task, WorkflowSettings settings, List<McpServerDefinition> mcpServers, WorkflowRunState state) async {
    if (!(await _locks?.acquire(task.id) ?? true)) {
      throw WorkflowStartException('Workflow ${task.id} is already running.');
    }
    final WorkflowRun run = WorkflowRun._(orchestrator: this, task: task, settings: settings, mcpServers: mcpServers, state: state);
    unawaited(run._execute());
    return run;
  }

  /// Resolves MCP servers and checks every assigned agent.
  Future<List<McpServerDefinition>> _prepare(WorkflowSettings settings) async {
    final List<McpServerDefinition> mcpServers;
    try {
      mcpServers = <McpServerDefinition>[for (final String id in settings.mcpServerIds) _mcpServers.require(id).resolve(_environment)];
    } on StateError catch (error) {
      throw WorkflowStartException(error.message);
    }

    final Set<String> primaryIds = <String>{for (final AgentRole role in AgentRole.values) settings.assignments.agentIdFor(role)};
    for (final String agentId in settings.allAgentIds) {
      final AgentAdapter? adapter = _agents[agentId];
      if (adapter == null) {
        throw WorkflowStartException('Unknown agent "$agentId". Available agents: ${_agents.ids.join(', ')}.');
      }
      if (mcpServers.isNotEmpty && !adapter.supportsMcp) {
        throw WorkflowStartException('${adapter.displayName} cannot use MCP servers; disable ${settings.mcpServerIds.join(', ')} or assign another agent.');
      }
      // Fallbacks are checked when they are needed.
      if (primaryIds.contains(agentId)) {
        final AgentAvailability availability = await adapter.checkAvailability();
        if (!availability.isAvailable) {
          throw WorkflowStartException('${adapter.displayName} is not available: ${availability.reason}');
        }
      }
    }
    return mcpServers;
  }

  String _defaultTaskId() {
    final DateTime now = _clock().toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    final Random random = Random.secure();
    final String suffix = List<String>.generate(6, (int _) => random.nextInt(16).toRadixString(16)).join();
    return 'wf-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}-$suffix';
  }
}

/// The user's answer to a checkpoint.
typedef _CheckpointAnswer = ({CheckpointDecision decision, String? feedback, Set<String>? repositories});

/// A workflow in progress.
final class WorkflowRun {
  WorkflowRun._({required this._orchestrator, required this._task, required this.settings, required this._mcpServers, required this._state});

  final WorkflowOrchestrator _orchestrator;
  final WorkflowSettings settings;
  final List<McpServerDefinition> _mcpServers;
  final WorkflowRunState _state;
  final StreamController<WorkflowEvent> _events = StreamController<WorkflowEvent>.broadcast();
  final List<WorkflowEvent> _history = <WorkflowEvent>[];
  final Completer<WorkflowTask> _result = Completer<WorkflowTask>();
  final Completer<void> _cancelSignal = Completer<void>();
  final Set<String> _pendingApprovals = <String>{};
  final List<Future<void>> _pendingLogs = <Future<void>>[];
  WorkflowTask _task;
  AgentExecution? _execution;
  bool _cancelRequested = false;
  WorkflowCheckpoint? _checkpoint;
  Completer<_CheckpointAnswer>? _checkpointAnswer;
  int _checkpointCount = 0;

  WorkflowTask get task => _task;

  /// Every event so far, so late listeners can render the full history.
  List<WorkflowEvent> get history => List<WorkflowEvent>.unmodifiable(_history);

  /// Events from now on; the stream closes after [WorkflowFinished].
  Stream<WorkflowEvent> get events => _events.stream;

  /// Completes with the terminal task once the workflow ends.
  Future<WorkflowTask> get result => _result.future;

  bool get isFinished => _result.isCompleted;

  /// Approval IDs the current agent is waiting on.
  Set<String> get pendingApprovals => Set<String>.unmodifiable(_pendingApprovals);

  /// The pause waiting for the user, if any.
  WorkflowCheckpoint? get pendingCheckpoint => _checkpoint;

  WorkflowChecklist get checklist => _state.checklist;

  /// Tokens (and cost, where reported) used by every agent so far.
  AgentUsage get usage => _state.totalUsage;

  Map<AgentRole, AgentUsage> get usageByRole => Map<AgentRole, AgentUsage>.unmodifiable(_state.usage);

  /// The agent currently playing [role], after any fallback switch.
  String agentFor(AgentRole role) => _state.activeAgents[role] ?? settings.assignments.agentIdFor(role);

  /// Stops the current agent and ends the workflow as cancelled.
  Future<void> cancel() async {
    if (isFinished || _cancelRequested) {
      return;
    }
    _cancelRequested = true;
    if (!_cancelSignal.isCompleted) {
      _cancelSignal.complete();
    }
    final Completer<_CheckpointAnswer>? answer = _checkpointAnswer;
    if (answer != null && !answer.isCompleted) {
      answer.complete((decision: CheckpointDecision.cancel, feedback: null, repositories: null));
    }
    await _execution?.cancel();
  }

  Future<void> resolveApproval(String approvalId, ApprovalDecision decision) async {
    final AgentExecution? execution = _execution;
    if (execution == null || !_pendingApprovals.remove(approvalId)) {
      throw StateError('No pending approval with ID $approvalId.');
    }
    await execution.resolveApproval(approvalId: approvalId, decision: decision);
    _emit(WorkflowApprovalResolved(approvalId: approvalId, decision: decision, timestamp: _now()));
  }

  /// Answers the pending checkpoint; [feedback] explains a revision.
  ///
  /// For a [WorkflowCheckpointKind.repositories] checkpoint,
  /// [editableRepositories] are the repositories the implementer may edit;
  /// when omitted, the ones the plan proposed.
  void resolveCheckpoint(String checkpointId, CheckpointDecision decision, {String? feedback, Set<String>? editableRepositories}) {
    final WorkflowCheckpoint? checkpoint = _checkpoint;
    final Completer<_CheckpointAnswer>? answer = _checkpointAnswer;
    if (checkpoint == null || checkpoint.id != checkpointId || answer == null || answer.isCompleted) {
      throw StateError('No pending checkpoint with ID $checkpointId.');
    }
    if (decision == CheckpointDecision.revise && !checkpoint.allowsRevision) {
      throw ArgumentError.value(decision, 'decision', 'is not allowed for ${checkpoint.kind.name}');
    }
    Set<String>? repositories;
    if (checkpoint.kind == WorkflowCheckpointKind.repositories && decision == CheckpointDecision.approve) {
      repositories =
          editableRepositories ??
          <String>{
            for (final WorkflowRepositoryChoice choice in checkpoint.repositories)
              if (choice.proposed) choice.path,
          };
      final Set<String> known = <String>{for (final WorkflowRepositoryChoice choice in checkpoint.repositories) choice.path};
      if (repositories.isEmpty || !known.containsAll(repositories)) {
        throw ArgumentError.value(editableRepositories, 'editableRepositories', 'must name at least one repository of this workflow');
      }
    }
    final String? trimmed = feedback?.trim();
    answer.complete((decision: decision, feedback: trimmed == null || trimmed.isEmpty ? null : trimmed, repositories: repositories));
  }

  DateTime _now() => _orchestrator._clock();

  Future<void> _execute() async {
    String? reason;
    try {
      await _runPhases();
    } on _WorkflowCancelled {
      reason = 'Cancelled by user.';
      await _end(WorkflowStatus.cancelled);
    } on _WorkflowFailure catch (failure) {
      reason = failure.message;
      await _end(WorkflowStatus.failed);
    } on Object catch (error) {
      reason = 'Unexpected error: $error';
      await _end(WorkflowStatus.failed);
    }

    _emit(WorkflowFinished(_task, reason: reason, timestamp: _now()));
    await Future.wait(<Future<void>>[..._pendingLogs, _saveState().catchError((Object _) {})]);
    await _orchestrator._locks?.release(_task.id).catchError((Object _) {});
    await _events.close();
    _result.complete(_task);
  }

  Future<void> _runPhases() async {
    if (!_state.hasBaseline) {
      final GitHead head = (await _orchestrator._git.readSnapshot(_task.repositoryPath)).head;
      _state
        ..baselineBranch = head.branch
        ..baselineCommit = head.commitSha;
      await _saveState();
    }
    for (final String repository in _task.additionalRepositoryPaths) {
      if (!_state.repositoryBaselines.containsKey(repository)) {
        final GitHead head = (await _orchestrator._git.readSnapshot(repository)).head;
        _state.repositoryBaselines[repository] = WorkflowRepositoryHead(branch: head.branch, commit: head.commitSha);
        await _saveState();
      }
    }
    if (_task.status == WorkflowStatus.pending || _task.status == WorkflowStatus.planning || _state.plan == null) {
      await _plan();
    }
    if (_state.checklist.items.isNotEmpty) {
      _emit(WorkflowChecklistUpdated(_state.checklist, timestamp: _now()));
    }

    // A run resumed during review goes straight back to review once.
    bool reviewNext = _task.status == WorkflowStatus.readyForReview || _task.status == WorkflowStatus.reviewing;
    while (true) {
      if (!reviewNext) {
        await _implement();
      }
      reviewNext = false;
      if (await _review()) {
        return;
      }
    }
  }

  Future<void> _plan() async {
    if (_task.status == WorkflowStatus.pending) {
      await _transition(WorkflowStatus.planning);
    }
    final WorkflowPrompts prompts = _orchestrator.prompts;
    String? planFeedback;
    int planReviews = 0;
    while (true) {
      final Map<String, String> before = await _fingerprints();
      final AgentCompletedEvent plan = await _runAgent(AgentRole.planner, planFeedback == null ? 'plan' : 'revise plan', prompts.planner(_context(planFeedback: planFeedback)));
      await _requireUnchanged(before, AgentRole.planner);
      _state
        ..plan = plan.summary
        ..checklist = WorkflowChecklist.fromPlan(plan.summary);
      await _saveArtifact(WorkflowArtifactKind.plan, plan.summary);
      _emit(WorkflowChecklistUpdated(_state.checklist, timestamp: _now()));
      await _saveState();
      planFeedback = null;

      if (settings.reviewPlan && planReviews < 2) {
        planReviews++;
        final Map<String, String> beforeReview = await _fingerprints();
        final AgentCompletedEvent critique = await _runAgent(AgentRole.reviewer, 'review plan', prompts.planReview(_context()));
        await _requireUnchanged(beforeReview, AgentRole.reviewer);
        await _saveArtifact(WorkflowArtifactKind.planReview, critique.summary);
        if (parseReviewVerdict(critique.summary) != ReviewVerdict.approved) {
          planFeedback = critique.summary;
          continue;
        }
      }

      if (settings.requirePlanApproval) {
        final _CheckpointAnswer answer = await _askUser(WorkflowCheckpointKind.plan, 'Approve the plan', _state.plan!);
        if (answer.decision == CheckpointDecision.revise) {
          planFeedback = answer.feedback ?? 'Revise the plan.';
          continue;
        }
      }

      if (_task.hasMultipleRepositories) {
        final _CheckpointAnswer answer = await _askRepositories();
        if (answer.decision == CheckpointDecision.revise) {
          planFeedback = answer.feedback ?? 'Revise which repositories the plan changes.';
          continue;
        }
        _state.editableRepositories = <String>[
          for (final String repository in _task.repositoryPaths)
            if (answer.repositories!.contains(repository)) repository,
        ];
        await _saveState();
      }
      break;
    }
    await _transition(WorkflowStatus.readyForImplementation);
  }

  Future<void> _implement() async {
    if (_task.status != WorkflowStatus.implementing) {
      await _transition(WorkflowStatus.implementing);
    }
    final WorkflowPrompts prompts = _orchestrator.prompts;
    while (true) {
      final Map<String, String> locked = await _fingerprints(<String>[
        for (final String repository in _task.repositoryPaths)
          if (!_editableRepositories.contains(repository)) repository,
      ]);
      _updateChecklist(_state.checklist.start(agentFor(AgentRole.implementer)));
      final AgentCompletedEvent implementation = await _runAgent(AgentRole.implementer, 'implement', prompts.implementer(_implementContext()), resumeSessionId: _state.implementerSession);
      _state.implementerSession = implementation.sessionId ?? _state.implementerSession;
      await _saveArtifact(WorkflowArtifactKind.implementation, implementation.summary);
      _updateChecklist(_state.checklist.applyImplementerReport(implementation.summary, agentFor(AgentRole.implementer)));
      await _saveState();

      final AgentCompletedEvent selfReview = await _runAgent(AgentRole.implementer, 'self-review', prompts.selfReview(_implementContext()), resumeSessionId: _state.implementerSession);
      _state.implementerSession = selfReview.sessionId ?? _state.implementerSession;
      await _saveArtifact(WorkflowArtifactKind.selfReview, selfReview.summary);
      _updateChecklist(_state.checklist.applyImplementerReport(selfReview.summary, agentFor(AgentRole.implementer)));
      await _saveState();
      await _requireSameHead();
      await _requireUnchanged(locked, AgentRole.implementer);

      if (settings.requireChangesApproval) {
        final String files = await _changedFiles();
        final _CheckpointAnswer answer = await _askUser(WorkflowCheckpointKind.changes, 'Approve the changes before review', '${selfReview.summary.trim()}\n\nChanged files:\n$files');
        if (answer.decision == CheckpointDecision.revise) {
          _state.feedback = 'The user asked for changes before review:\n${answer.feedback ?? 'Improve the changes.'}';
          await _saveState();
          continue;
        }
      }
      break;
    }
    await _transition(WorkflowStatus.readyForReview);
  }

  /// Verifies and reviews; returns whether the workflow completed.
  Future<bool> _review() async {
    if (_task.status != WorkflowStatus.reviewing) {
      await _transition(WorkflowStatus.reviewing);
    }
    final List<VerificationResult> verification = await _verify();
    final String verificationReport = formatVerificationReport(verification);
    await _saveArtifact(WorkflowArtifactKind.verification, verificationReport);
    final bool verificationPassed = verification.every((VerificationResult result) => result.passed);

    String? reviewSummary;
    ReviewVerdict verdict = ReviewVerdict.changesRequested;
    if (verificationPassed || !settings.skipReviewWhenVerificationFails) {
      final Map<String, String> before = await _fingerprints();
      final ({String patch, bool isTruncated}) diff = await _diff();
      final AgentCompletedEvent review = await _runAgent(
        AgentRole.reviewer,
        'review',
        _orchestrator.prompts.reviewer(
          _context(checklist: _state.checklist.describe(), implementationSummary: await _latestImplementationSummary(), verificationReport: verificationReport, diff: diff.patch, isDiffTruncated: diff.isTruncated),
        ),
      );
      await _requireUnchanged(before, AgentRole.reviewer);
      await _saveArtifact(WorkflowArtifactKind.review, review.summary);
      _updateChecklist(_state.checklist.applyReviewerReport(review.summary, agentFor(AgentRole.reviewer)));
      reviewSummary = review.summary;
      verdict = parseReviewVerdict(review.summary);
    }

    final List<ChecklistItem> needingChanges = _state.checklist.needingChanges;
    if (verdict == ReviewVerdict.approved && verificationPassed && needingChanges.isEmpty) {
      await _saveState();
      await _transition(WorkflowStatus.completed);
      return true;
    }

    await _transition(WorkflowStatus.changesRequested);
    _state
      ..feedback = <String>[
        if (reviewSummary == null) 'The review was skipped because verification failed.',
        if (verdict == ReviewVerdict.missing) 'The reviewer did not give a verdict. Treat the review below as requested changes.',
        ?reviewSummary,
        if (!verificationPassed) 'Verification failed; every failing command must pass.',
        if (needingChanges.isNotEmpty) 'Checklist items that still need changes:\n${needingChanges.map((ChecklistItem item) => '- ${item.id}: ${item.title}${item.note == null ? '' : ' — ${item.note}'}').join('\n')}',
      ].join('\n\n')
      ..previousVerification = verificationReport;
    await _saveState();
    if (_task.reviewCycle >= settings.maxReviewCycles) {
      throw _WorkflowFailure('No approval after ${settings.maxReviewCycles} review round(s).');
    }
    return false;
  }

  WorkflowPromptContext _implementContext() => _context(checklist: _state.checklist.describe(), reviewFeedback: _state.feedback, verificationReport: _state.previousVerification);

  WorkflowPromptContext _context({String? planFeedback, String? checklist, String? implementationSummary, String? reviewFeedback, String? verificationReport, String? diff, bool isDiffTruncated = false}) => WorkflowPromptContext(
    request: _task.request,
    repositoryRoot: _task.repositoryPath,
    reviewCycle: _task.reviewCycle,
    plan: _state.plan,
    planFeedback: planFeedback,
    checklist: checklist,
    implementationSummary: implementationSummary,
    reviewFeedback: reviewFeedback,
    verificationReport: verificationReport,
    diff: diff,
    isDiffTruncated: isDiffTruncated,
    repositories: _promptRepositories(),
  );

  /// Repositories the implementer may edit: the user's choice in a
  /// multi-repository workflow, otherwise the only repository.
  List<String> get _editableRepositories => _task.hasMultipleRepositories ? _state.editableRepositories ?? <String>[_task.repositoryPath] : <String>[_task.repositoryPath];

  List<WorkflowPromptRepository> _promptRepositories() {
    if (!_task.hasMultipleRepositories) {
      return const <WorkflowPromptRepository>[];
    }
    final Map<String, String> names = repositoryNames(_task.repositoryPaths);
    final List<String>? editable = _state.editableRepositories;
    return <WorkflowPromptRepository>[
      for (final String repository in _task.repositoryPaths) WorkflowPromptRepository(name: names[repository]!, path: repository, editable: editable?.contains(repository)),
    ];
  }

  /// Asks which repositories the implementer may edit, proposing those the
  /// plan names and those the request mentions (or the working directory
  /// when neither names any).
  Future<_CheckpointAnswer> _askRepositories() {
    final Map<String, String> names = repositoryNames(_task.repositoryPaths);
    final Map<String, String?> planned = plannedRepositories(_state.plan ?? '', _task.repositoryPaths);
    final Set<String> mentioned = mentionedRepositories(_task.request, _task.repositoryPaths);
    final Set<String> named = <String>{...planned.keys, ...mentioned};
    final Set<String> proposed = named.isEmpty ? <String>{_task.repositoryPath} : named;
    final List<WorkflowRepositoryChoice> choices = <WorkflowRepositoryChoice>[
      for (final String repository in _task.repositoryPaths) WorkflowRepositoryChoice(path: repository, name: names[repository]!, proposed: proposed.contains(repository), reason: planned[repository] ?? (mentioned.contains(repository) ? 'Mentioned in your request' : null)),
    ];
    final String details = <String>[
      for (final WorkflowRepositoryChoice choice in choices) '- ${choice.name} (${choice.path}): ${choice.proposed ? 'the plan changes it${choice.reason == null ? '' : ' — ${choice.reason}'}' : 'read only'}',
    ].join('\n');
    return _askUser(WorkflowCheckpointKind.repositories, 'Allow edits to these repositories?', details, repositories: choices);
  }

  /// The self-review of the current round, also after a resume.
  Future<String?> _latestImplementationSummary() async {
    final List<WorkflowArtifact> artifacts = await _orchestrator._artifacts.readArtifacts(_task.id);
    for (final WorkflowArtifact artifact in artifacts.reversed) {
      if (artifact.kind == WorkflowArtifactKind.selfReview || artifact.kind == WorkflowArtifactKind.implementation) {
        return artifact.content;
      }
    }
    return null;
  }

  /// Runs [role]'s agent, retrying network failures with backoff, moving to
  /// fallback agents on usage limits or lost sign-ins, and asking the user
  /// when no agent can continue.
  Future<AgentCompletedEvent> _runAgent(AgentRole role, String phase, String instructions, {String? resumeSessionId}) async {
    String? session = resumeSessionId;
    int attempt = 1;
    final Set<String> exhausted = <String>{};
    while (true) {
      _throwIfCancelled();
      final String agentId = agentFor(role);
      final AgentAdapter adapter = _orchestrator._agents.require(agentId);
      final AgentEvent outcome = await _runOnce(adapter, role, phase, instructions, session);
      if (outcome is AgentCompletedEvent) {
        _recordUsage(role, agentId, outcome.usage);
        _emit(WorkflowAgentFinished(role: role, agentId: agentId, phase: phase, usage: outcome.usage, totalUsage: _state.totalUsage, timestamp: _now()));
        _enforceBudget();
        return outcome;
      }

      final AgentFailedEvent failure = outcome as AgentFailedEvent;
      _recordUsage(role, agentId, failure.usage);
      _throwIfCancelled();
      _enforceBudget();
      switch (failure.kind) {
        case AgentFailureKind.network when attempt <= settings.maxRetries:
          final Duration delay = settings.retryDelay * (1 << (attempt - 1));
          attempt++;
          session = failure.sessionId ?? session;
          _emit(WorkflowRetryScheduled(role: role, agentId: agentId, attempt: attempt, maxAttempts: settings.maxRetries + 1, delay: delay, reason: failure.message, timestamp: _now()));
          await _wait(delay);
        case AgentFailureKind.rateLimit || AgentFailureKind.authentication:
          exhausted.add(agentId);
          final String? fallback = await _nextFallback(role, exhausted);
          if (fallback != null) {
            _state.activeAgents[role] = fallback;
            if (role == AgentRole.implementer) {
              _state.implementerSession = null;
            }
            session = null;
            attempt = 1;
            await _saveState();
            _emit(WorkflowAgentSwitched(role: role, fromAgentId: agentId, toAgentId: fallback, reason: failure.message, timestamp: _now()));
            continue;
          }
          final String? signIn = failure.kind == AgentFailureKind.authentication ? (await adapter.checkAvailability()).signInCommand : null;
          await _askUser(
            WorkflowCheckpointKind.agentUnavailable,
            failure.kind == AgentFailureKind.rateLimit ? '${adapter.displayName} reached a usage limit' : '${adapter.displayName} needs you to sign in',
            '${failure.message}\n\n${signIn == null ? 'Retry when the limit resets, add a fallback agent or another account for the ${role.name}, or cancel.' : 'Run `$signIn` in Terminal, then retry.'}',
            role: role,
          );
          exhausted.clear();
          attempt = 1;
        default:
          throw _WorkflowFailure('${adapter.displayName} failed during $phase: ${failure.message}');
      }
    }
  }

  /// One agent execution; returns its terminal event.
  Future<AgentEvent> _runOnce(AgentAdapter adapter, AgentRole role, String phase, String instructions, String? session) async {
    final AgentExecution execution;
    try {
      execution = await adapter.start(
        AgentRunRequest(
          task: _task,
          role: role,
          instructions: instructions,
          workingDirectory: _task.repositoryPath,
          resumeSessionId: session,
          mcpServers: _mcpServers,
          model: adapter.id == settings.assignments.agentIdFor(role) ? settings.modelOverrides[role] : null,
          additionalDirectories: <AgentDirectoryAccess>[
            for (final String repository in _task.additionalRepositoryPaths) AgentDirectoryAccess(path: repository, writable: role == AgentRole.implementer && _editableRepositories.contains(repository)),
          ],
        ),
      );
    } on AgentStartException catch (error) {
      return AgentFailedEvent(timestamp: _now(), message: '${adapter.displayName} could not start: ${error.message}');
    }

    _execution = execution;
    _emit(WorkflowAgentStarted(role: role, agentId: adapter.id, phase: phase, timestamp: _now()));
    if (_cancelRequested) {
      await execution.cancel();
    }

    AgentEvent? terminal;
    try {
      await for (final AgentEvent event in execution.events) {
        switch (event) {
          case AgentOutputEvent(:final String text, :final AgentOutputChannel channel):
            _emit(WorkflowAgentOutput(role: role, text: text, channel: channel, timestamp: event.timestamp));
          case AgentApprovalRequestedEvent(:final String approvalId, :final String action, :final String details):
            _pendingApprovals.add(approvalId);
            _emit(WorkflowApprovalRequested(role: role, approvalId: approvalId, action: action, details: details, timestamp: event.timestamp));
          case AgentCompletedEvent() || AgentFailedEvent():
            terminal = event;
        }
      }
    } finally {
      _execution = null;
      _pendingApprovals.clear();
    }
    _throwIfCancelled();
    return terminal ?? AgentFailedEvent(timestamp: _now(), message: '${adapter.displayName} ended without a result.');
  }

  /// The next available fallback for [role] not in [exhausted]: the
  /// configured fallbacks first, then other accounts of the same agent.
  Future<String?> _nextFallback(AgentRole role, Set<String> exhausted) async {
    String agentOf(AgentAdapter adapter) => adapter.account?.agentId ?? adapter.id;
    final AgentAdapter? current = _orchestrator._agents[agentFor(role)];
    final List<String> candidates = <String>[
      ...settings.fallbackAgentIds[role] ?? const <String>[],
      if (current != null)
        for (final AgentAdapter adapter in _orchestrator._agents.adapters)
          if (adapter.id != current.id && agentOf(adapter) == agentOf(current)) adapter.id,
    ];
    for (final String id in candidates) {
      final AgentAdapter? adapter = _orchestrator._agents[id];
      if (adapter == null || exhausted.contains(id) || (_mcpServers.isNotEmpty && !adapter.supportsMcp)) {
        continue;
      }
      if ((await adapter.checkAvailability()).isAvailable) {
        return id;
      }
      exhausted.add(id);
    }
    return null;
  }

  void _recordUsage(AgentRole role, String agentId, AgentUsage? usage) {
    if (usage != null) {
      _state.usage[role] = (_state.usage[role] ?? AgentUsage.zero) + usage;
      _state.agentUsageRecords.add(WorkflowAgentUsageRecord(agentId: agentId, usage: usage, timestamp: _now()));
    }
  }

  void _enforceBudget() {
    final int? maxTokens = settings.maxTokens;
    final int used = _state.totalUsage.totalTokens;
    if (maxTokens != null && used > maxTokens) {
      throw _WorkflowFailure('Token budget exceeded: $used of $maxTokens tokens used.');
    }
  }

  /// Pauses until the user answers; a cancel ends the workflow.
  Future<_CheckpointAnswer> _askUser(WorkflowCheckpointKind kind, String title, String details, {AgentRole? role, List<WorkflowRepositoryChoice> repositories = const <WorkflowRepositoryChoice>[]}) async {
    _throwIfCancelled();
    final WorkflowCheckpoint checkpoint = WorkflowCheckpoint(id: 'checkpoint-${++_checkpointCount}', kind: kind, title: title, details: details, role: role, repositories: repositories);
    final Completer<_CheckpointAnswer> answer = Completer<_CheckpointAnswer>();
    _checkpoint = checkpoint;
    _checkpointAnswer = answer;
    _emit(WorkflowCheckpointRequested(checkpoint, timestamp: _now()));
    final _CheckpointAnswer result = await answer.future;
    _checkpoint = null;
    _checkpointAnswer = null;
    _emit(WorkflowCheckpointResolved(checkpointId: checkpoint.id, decision: result.decision, feedback: result.feedback, timestamp: _now()));
    if (result.decision == CheckpointDecision.cancel) {
      throw const _WorkflowCancelled();
    }
    return result;
  }

  /// Waits [delay] unless the workflow is cancelled first.
  Future<void> _wait(Duration delay) async {
    if (delay > Duration.zero) {
      await Future.any(<Future<void>>[Future<void>.delayed(delay), _cancelSignal.future]);
    }
    _throwIfCancelled();
  }

  void _updateChecklist(WorkflowChecklist checklist) {
    _state.checklist = checklist;
    if (checklist.items.isNotEmpty) {
      _emit(WorkflowChecklistUpdated(checklist, timestamp: _now()));
    }
  }

  Future<List<VerificationResult>> _verify() async {
    final List<VerificationResult> results = <VerificationResult>[];
    for (final VerificationCommand command in settings.verificationCommands) {
      _throwIfCancelled();
      results.add(await _orchestrator._verifier.run(command, workingDirectory: _task.repositoryPath));
    }
    _emit(WorkflowVerificationFinished(List<VerificationResult>.unmodifiable(results), timestamp: _now()));
    return results;
  }

  /// Fingerprints of [repositories] (default: all of the workflow's), by path.
  Future<Map<String, String>> _fingerprints([List<String>? repositories]) async => <String, String>{
    for (final String repository in repositories ?? _task.repositoryPaths) repository: await fingerprintRepository(await _orchestrator._git.readSnapshot(repository)),
  };

  /// Fails when a repository in [before] changed: a read-only role must
  /// change none, and the implementer none it was not allowed to edit.
  Future<void> _requireUnchanged(Map<String, String> before, AgentRole role) async {
    final Map<String, String> after = await _fingerprints(before.keys.toList());
    for (final MapEntry<String, String>(:String key, :String value) in before.entries) {
      if (after[key] != value) {
        final String repository = _task.hasMultipleRepositories ? repositoryNames(_task.repositoryPaths)[key]! : 'the repository';
        throw _WorkflowFailure(
          role == AgentRole.implementer ? 'The implementer changed $repository, which you did not allow it to edit.' : 'The ${role.name} changed $repository although its role is read-only.',
        );
      }
    }
  }

  /// No repository's `HEAD` or branch may move; only uncommitted edits are allowed.
  Future<void> _requireSameHead() async {
    final GitHead head = (await _orchestrator._git.readSnapshot(_task.repositoryPath)).head;
    bool moved = head.branch != _state.baselineBranch || head.commitSha != _state.baselineCommit;
    for (final MapEntry<String, WorkflowRepositoryHead>(:String key, :WorkflowRepositoryHead value) in _state.repositoryBaselines.entries) {
      final GitHead other = (await _orchestrator._git.readSnapshot(key)).head;
      moved = moved || other.branch != value.branch || other.commitSha != value.commit;
    }
    if (moved) {
      throw const _WorkflowFailure('The implementer moved HEAD (commit, checkout, or reset); only uncommitted edits are allowed.');
    }
  }

  /// Changed files of every repository, grouped by repository when there are several.
  Future<String> _changedFiles() async {
    final Map<String, String> names = repositoryNames(_task.repositoryPaths);
    final List<String> sections = <String>[];
    for (final String repository in _task.repositoryPaths) {
      final GitRepositorySnapshot snapshot = await _orchestrator._git.readSnapshot(repository);
      if (snapshot.entries.isEmpty) {
        continue;
      }
      final String files = snapshot.entries.map((GitStatusEntry entry) => '- ${entry.path}').join('\n');
      sections.add(_task.hasMultipleRepositories ? '${names[repository]}:\n$files' : files);
    }
    return sections.isEmpty ? 'No files changed.' : sections.join('\n\n');
  }

  /// The uncommitted diff of every repository for the reviewer, each under
  /// its own heading when there are several; the size limit is shared.
  Future<({String patch, bool isTruncated})> _diff() async {
    if (!_task.hasMultipleRepositories) {
      final GitDiff diff = await _orchestrator._git.readDiff(_task.repositoryPath, maxCharacters: _orchestrator.maxDiffCharacters);
      return (patch: diff.patch, isTruncated: diff.isTruncated);
    }
    final Map<String, String> names = repositoryNames(_task.repositoryPaths);
    final int share = _orchestrator.maxDiffCharacters ~/ _task.repositoryPaths.length;
    final List<String> sections = <String>[];
    bool truncated = false;
    for (final String repository in _task.repositoryPaths) {
      final GitDiff diff = await _orchestrator._git.readDiff(repository, maxCharacters: share);
      truncated = truncated || diff.isTruncated;
      if (!diff.isEmpty) {
        sections.add('### Repository ${names[repository]} ($repository)\n${diff.patch}');
      }
    }
    return (patch: sections.join('\n\n'), isTruncated: truncated);
  }

  Future<void> _saveArtifact(WorkflowArtifactKind kind, String content) async {
    final WorkflowArtifact artifact = WorkflowArtifact(kind: kind, cycle: _task.reviewCycle, content: content, createdAt: _now());
    await _orchestrator._artifacts.writeArtifact(_task.id, artifact);
    _emit(WorkflowArtifactSaved(artifact, timestamp: artifact.createdAt));
  }

  Future<void> _saveState() async => _orchestrator._runStates?.save(_task.id, _state);

  Future<void> _transition(WorkflowStatus status) async {
    final DateTime now = _now();
    _task = _task.transitionTo(status, at: now.isBefore(_task.updatedAt) ? _task.updatedAt : now);
    await _orchestrator._tasks.save(_task);
    _emit(WorkflowStatusChanged(_task, timestamp: _task.updatedAt));
  }

  /// Moves to [status], or to cancelled when [status] is not reachable from
  /// the current state, so a run always ends in a terminal state.
  Future<void> _end(WorkflowStatus status) async {
    if (_task.isTerminal) {
      return;
    }
    const WorkflowStateMachine stateMachine = WorkflowStateMachine();
    final WorkflowStatus target = stateMachine.canTransition(from: _task.status, to: status) ? status : WorkflowStatus.cancelled;
    try {
      await _transition(target);
    } on Object {
      // The task file may be unwritable; the in-memory task still ends.
      _task = _task.transitionTo(target, at: _task.updatedAt);
    }
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const _WorkflowCancelled();
    }
  }

  void _emit(WorkflowEvent event) {
    _history.add(event);
    if (!_events.isClosed) {
      _events.add(event);
    }
    _pendingLogs.add(
      _orchestrator._artifacts.appendLog(_task.id, WorkflowLogEntry(timestamp: event.timestamp, source: event.source, message: event.message)).catchError((Object _) {
        // Logs are best effort; task and artifact writes are not.
      }),
    );
  }
}

final class _WorkflowFailure implements Exception {
  const _WorkflowFailure(this.message);

  final String message;
}

final class _WorkflowCancelled implements Exception {
  const _WorkflowCancelled();
}
