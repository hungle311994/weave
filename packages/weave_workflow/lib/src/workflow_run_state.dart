import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_storage/weave_storage.dart';

import 'workflow_checklist.dart';
import 'workflow_repositories.dart';

/// Everything a workflow needs to continue after Weave was closed or the
/// network dropped, kept outside the repository in `run.json`.
final class WorkflowRunState {
  WorkflowRunState({
    this.baselineBranch,
    this.baselineCommit,
    this.plan,
    this.implementerSession,
    this.feedback,
    this.previousVerification,
    WorkflowChecklist? checklist,
    Map<AgentRole, AgentUsage> usage = const <AgentRole, AgentUsage>{},
    List<WorkflowAgentUsageRecord> agentUsageRecords = const <WorkflowAgentUsageRecord>[],
    Map<AgentRole, String> activeAgents = const <AgentRole, String>{},
    Map<String, WorkflowRepositoryHead> repositoryBaselines = const <String, WorkflowRepositoryHead>{},
    this.editableRepositories,
  }) : repositoryBaselines = Map<String, WorkflowRepositoryHead>.of(repositoryBaselines),
       checklist = checklist ?? WorkflowChecklist(const <ChecklistItem>[]),
       usage = Map<AgentRole, AgentUsage>.of(usage),
       agentUsageRecords = List<WorkflowAgentUsageRecord>.of(agentUsageRecords),
       activeAgents = Map<AgentRole, String>.of(activeAgents);

  factory WorkflowRunState.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw FormatException('Unsupported run state schema version: ${json['schemaVersion']}.');
    }
    try {
      return WorkflowRunState(
        baselineBranch: json['baselineBranch'] as String?,
        baselineCommit: json['baselineCommit'] as String?,
        plan: json['plan'] as String?,
        implementerSession: json['implementerSession'] as String?,
        feedback: json['feedback'] as String?,
        previousVerification: json['previousVerification'] as String?,
        checklist: WorkflowChecklist.fromJson(json['checklist'] as List<Object?>? ?? const <Object?>[]),
        usage: <AgentRole, AgentUsage>{
          for (final MapEntry<String, Object?>(:String key, :Object? value) in (json['usage'] as Map<String, Object?>? ?? const <String, Object?>{}).entries) AgentRole.values.byName(key): AgentUsage.fromJson(value! as Map<String, Object?>),
        },
        agentUsageRecords: <WorkflowAgentUsageRecord>[
          for (final Object? record in json['agentUsageRecords'] as List<Object?>? ?? const <Object?>[])
            if (record is Map<String, Object?>) WorkflowAgentUsageRecord.fromJson(record) else throw const FormatException('Each agent usage record must be an object.'),
        ],
        activeAgents: <AgentRole, String>{
          for (final MapEntry<String, Object?>(:String key, :Object? value) in (json['activeAgents'] as Map<String, Object?>? ?? const <String, Object?>{}).entries) AgentRole.values.byName(key): value! as String,
        },
        repositoryBaselines: <String, WorkflowRepositoryHead>{
          for (final MapEntry<String, Object?>(:String key, :Object? value) in (json['repositoryBaselines'] as Map<String, Object?>? ?? const <String, Object?>{}).entries) key: WorkflowRepositoryHead.fromJson(value! as Map<String, Object?>),
        },
        editableRepositories: (json['editableRepositories'] as List<Object?>?)?.cast<String>(),
      );
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('Invalid run state: $error');
    }
  }

  static const int schemaVersion = 1;

  /// `HEAD` when the workflow started; the implementer may not move it.
  String? baselineBranch;
  String? baselineCommit;

  /// Whether the baseline was recorded; an unborn branch has no commit.
  bool get hasBaseline => baselineBranch != null || baselineCommit != null;

  String? plan;
  String? implementerSession;

  /// What the implementer must address next, from the reviewer or the user.
  String? feedback;
  String? previousVerification;
  WorkflowChecklist checklist;

  /// Tokens used per role so far.
  final Map<AgentRole, AgentUsage> usage;

  /// Usage samples attributed to the agent that actually produced them.
  /// Older run files may have no records because role-only usage predates this
  /// field.
  final List<WorkflowAgentUsageRecord> agentUsageRecords;

  /// Roles that switched to a fallback agent.
  final Map<AgentRole, String> activeAgents;

  /// `HEAD` of every additional repository when the workflow started, by
  /// path; the implementer may not move them either.
  final Map<String, WorkflowRepositoryHead> repositoryBaselines;

  /// Repositories the user allowed the implementer to edit, decided after
  /// planning in a multi-repository workflow; `null` until then.
  List<String>? editableRepositories;

  AgentUsage get totalUsage => usage.values.fold(AgentUsage.zero, (AgentUsage total, AgentUsage next) => total + next);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'baselineBranch': baselineBranch,
    'baselineCommit': baselineCommit,
    'plan': plan,
    'implementerSession': implementerSession,
    'feedback': feedback,
    'previousVerification': previousVerification,
    'checklist': checklist.toJson(),
    'usage': <String, Object?>{for (final MapEntry<AgentRole, AgentUsage>(:AgentRole key, :AgentUsage value) in usage.entries) key.name: value.toJson()},
    'agentUsageRecords': <Map<String, Object?>>[for (final WorkflowAgentUsageRecord record in agentUsageRecords) record.toJson()],
    'activeAgents': <String, String>{for (final MapEntry<AgentRole, String>(:AgentRole key, :String value) in activeAgents.entries) key.name: value},
    if (repositoryBaselines.isNotEmpty) 'repositoryBaselines': <String, Object?>{for (final MapEntry<String, WorkflowRepositoryHead>(:String key, :WorkflowRepositoryHead value) in repositoryBaselines.entries) key: value.toJson()},
    if (editableRepositories != null) 'editableRepositories': editableRepositories,
  };
}

/// One agent-reported usage sample captured by Weave.
final class WorkflowAgentUsageRecord {
  WorkflowAgentUsageRecord({required String agentId, required this.usage, required DateTime timestamp}) : agentId = _requireAgentId(agentId), timestamp = timestamp.toUtc();

  factory WorkflowAgentUsageRecord.fromJson(Map<String, Object?> json) {
    final Object? agentId = json['agentId'];
    final Object? usage = json['usage'];
    final Object? timestamp = json['timestamp'];
    if (agentId is! String || usage is! Map<String, Object?> || timestamp is! String) {
      throw const FormatException('Invalid agent usage record.');
    }
    final DateTime? parsedTimestamp = DateTime.tryParse(timestamp);
    if (parsedTimestamp == null) {
      throw const FormatException('Invalid agent usage timestamp.');
    }
    return WorkflowAgentUsageRecord(agentId: agentId, usage: AgentUsage.fromJson(usage), timestamp: parsedTimestamp);
  }

  final String agentId;
  final AgentUsage usage;
  final DateTime timestamp;

  Map<String, Object?> toJson() => <String, Object?>{'agentId': agentId, 'usage': usage.toJson(), 'timestamp': timestamp.toIso8601String()};

  static String _requireAgentId(String value) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'agentId', 'must not be empty');
    }
    return normalized;
  }
}

/// Saves and loads [WorkflowRunState] next to each task.
final class FileWorkflowRunStateStore {
  FileWorkflowRunStateStore({required this._workflowsDirectory});

  final String _workflowsDirectory;

  File _file(String taskId) => File(path.join(workflowTaskDirectory(_workflowsDirectory, taskId).path, 'run.json'));

  Future<WorkflowRunState?> load(String taskId) async {
    final File file = _file(taskId);
    if (!await file.exists()) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Run state must be an object.');
      }
      return WorkflowRunState.fromJson(decoded);
    } on FormatException catch (error) {
      throw WorkflowStorageFormatException('Invalid run state for workflow $taskId.', cause: error);
    }
  }

  Future<void> save(String taskId, WorkflowRunState state) async {
    try {
      await writeFileAtomically(_file(taskId), encodePrettyJson(state.toJson()));
    } on Object catch (error, stackTrace) {
      throw WorkflowStorageException('Unable to save the run state of workflow $taskId.', cause: error, stackTrace: stackTrace);
    }
  }
}
