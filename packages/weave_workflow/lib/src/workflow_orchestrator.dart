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
  Future<WorkflowRun> start({required String request, required String repositoryPath, required WorkflowSettings settings}) async {
    if (request.trim().isEmpty) {
      throw const WorkflowStartException('The request must not be empty.');
    }
    final String repositoryRoot = await _git.findRepositoryRoot(repositoryPath);
    final List<McpServerDefinition> mcpServers = await _prepare(settings);

    final WorkflowTask task = WorkflowTask.create(id: _createTaskId?.call() ?? _defaultTaskId(), request: request, repositoryPath: repositoryRoot, createdAt: _clock());
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
    await _git.findRepositoryRoot(task.repositoryPath);
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
typedef _CheckpointAnswer = ({CheckpointDecision decision, String? feedback});

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
      answer.complete((decision: CheckpointDecision.cancel, feedback: null));
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
  void resolveCheckpoint(String checkpointId, CheckpointDecision decision, {String? feedback}) {
    final WorkflowCheckpoint? checkpoint = _checkpoint;
    final Completer<_CheckpointAnswer>? answer = _checkpointAnswer;
    if (checkpoint == null || checkpoint.id != checkpointId || answer == null || answer.isCompleted) {
      throw StateError('No pending checkpoint with ID $checkpointId.');
    }
    if (decision == CheckpointDecision.revise && !checkpoint.allowsRevision) {
      throw ArgumentError.value(decision, 'decision', 'is not allowed for ${checkpoint.kind.name}');
    }
    final String? trimmed = feedback?.trim();
    answer.complete((decision: decision, feedback: trimmed == null || trimmed.isEmpty ? null : trimmed));
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
      final String before = await _fingerprint();
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
        final String beforeReview = await _fingerprint();
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

      if (settings.requireChangesApproval) {
        final GitRepositorySnapshot snapshot = await _orchestrator._git.readSnapshot(_task.repositoryPath);
        final String files = snapshot.entries.isEmpty ? 'No files changed.' : snapshot.entries.map((GitStatusEntry entry) => '- ${entry.path}').join('\n');
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
      final GitDiff diff = await _orchestrator._git.readDiff(_task.repositoryPath, maxCharacters: _orchestrator.maxDiffCharacters);
      final String before = await fingerprintRepository(diff.snapshot);
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
  );

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
        _recordUsage(role, outcome.usage);
        _emit(WorkflowAgentFinished(role: role, agentId: agentId, phase: phase, usage: outcome.usage, totalUsage: _state.totalUsage, timestamp: _now()));
        _enforceBudget();
        return outcome;
      }

      final AgentFailedEvent failure = outcome as AgentFailedEvent;
      _recordUsage(role, failure.usage);
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
            '${failure.message}\n\n${signIn == null ? 'Retry when the limit resets, add a fallback agent for the ${role.name}, or cancel.' : 'Run `$signIn` in Terminal, then retry.'}',
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

  /// The next available fallback for [role] not in [exhausted].
  Future<String?> _nextFallback(AgentRole role, Set<String> exhausted) async {
    for (final String id in settings.fallbackAgentIds[role] ?? const <String>[]) {
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

  void _recordUsage(AgentRole role, AgentUsage? usage) {
    if (usage != null) {
      _state.usage[role] = (_state.usage[role] ?? AgentUsage.zero) + usage;
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
  Future<_CheckpointAnswer> _askUser(WorkflowCheckpointKind kind, String title, String details, {AgentRole? role}) async {
    _throwIfCancelled();
    final WorkflowCheckpoint checkpoint = WorkflowCheckpoint(id: 'checkpoint-${++_checkpointCount}', kind: kind, title: title, details: details, role: role);
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

  Future<String> _fingerprint() async => fingerprintRepository(await _orchestrator._git.readSnapshot(_task.repositoryPath));

  Future<void> _requireUnchanged(String before, AgentRole role) async {
    if (await _fingerprint() != before) {
      throw _WorkflowFailure('The ${role.name} changed the repository although its role is read-only.');
    }
  }

  Future<void> _requireSameHead() async {
    final GitHead head = (await _orchestrator._git.readSnapshot(_task.repositoryPath)).head;
    if (head.branch != _state.baselineBranch || head.commitSha != _state.baselineCommit) {
      throw const _WorkflowFailure('The implementer moved HEAD (commit, checkout, or reset); only uncommitted edits are allowed.');
    }
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
