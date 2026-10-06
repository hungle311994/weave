import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_storage/weave_storage.dart';

import 'verification.dart';

/// Which agent plays each role, which checks Weave runs, how much the
/// workflow may spend, and where it pauses for the user.
final class WorkflowSettings {
  WorkflowSettings({
    required this.assignments,
    List<VerificationCommand> verificationCommands = const <VerificationCommand>[],
    this.maxReviewCycles = 3,
    List<String> mcpServerIds = const <String>[],
    Map<AgentRole, String> modelOverrides = const <AgentRole, String>{},
    Map<AgentRole, List<String>> fallbackAgentIds = const <AgentRole, List<String>>{},
    this.requirePlanApproval = false,
    this.requireChangesApproval = false,
    this.reviewPlan = false,
    this.skipReviewWhenVerificationFails = true,
    this.maxTokens,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 10),
  }) : verificationCommands = List<VerificationCommand>.unmodifiable(verificationCommands),
       mcpServerIds = List<String>.unmodifiable(mcpServerIds.toSet()),
       modelOverrides = Map<AgentRole, String>.unmodifiable(<AgentRole, String>{
         for (final MapEntry<AgentRole, String>(:AgentRole key, :String value) in modelOverrides.entries)
           if (value.trim().isNotEmpty) key: value.trim(),
       }),
       fallbackAgentIds = Map<AgentRole, List<String>>.unmodifiable(<AgentRole, List<String>>{
         for (final MapEntry<AgentRole, List<String>>(:AgentRole key, :List<String> value) in fallbackAgentIds.entries)
           if (value.isNotEmpty) key: List<String>.unmodifiable(<String>{...value}.where((String id) => id != assignments.agentIdFor(key))),
       }) {
    if (maxReviewCycles < 1) {
      throw ArgumentError.value(maxReviewCycles, 'maxReviewCycles', 'must be at least 1');
    }
    if (maxTokens != null && maxTokens! < 1) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be positive');
    }
    if (maxRetries < 0) {
      throw ArgumentError.value(maxRetries, 'maxRetries', 'must not be negative');
    }
    if (retryDelay.isNegative) {
      throw ArgumentError.value(retryDelay, 'retryDelay', 'must not be negative');
    }
  }

  factory WorkflowSettings.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw FormatException('Unsupported workflow settings schema version: ${json['schemaVersion']}.');
    }
    final Object? assignments = json['assignments'];
    final Object commands = json['verificationCommands'] ?? const <Object?>[];
    final Object maxReviewCycles = json['maxReviewCycles'] ?? 3;
    final Object mcpServers = json['mcpServers'] ?? const <Object?>[];
    final Object models = json['models'] ?? const <String, Object?>{};
    final Object fallbacks = json['fallbacks'] ?? const <String, Object?>{};
    final Object? maxTokens = json['maxTokens'];
    final Object maxRetries = json['maxRetries'] ?? 3;
    final Object retryDelaySeconds = json['retryDelaySeconds'] ?? 10;
    if (assignments is! Map<String, Object?> || commands is! List<Object?> || maxReviewCycles is! int || mcpServers is! List<Object?> || mcpServers.any((Object? id) => id is! String) || models is! Map<String, Object?> || fallbacks is! Map<String, Object?> || (maxTokens != null && maxTokens is! int) || maxRetries is! int || retryDelaySeconds is! int) {
      throw const FormatException('Invalid workflow settings.');
    }

    String agentFor(AgentRole role) {
      final Object? id = assignments[role.name];
      if (id is! String) {
        throw FormatException('Missing ${role.name} agent.');
      }
      return id;
    }

    bool flag(String key, {bool fallback = false}) => switch (json[key]) {
      null => fallback,
      final bool value => value,
      _ => throw FormatException('$key must be true or false.'),
    };

    try {
      return WorkflowSettings(
        assignments: AgentAssignments(plannerAgentId: agentFor(AgentRole.planner), implementerAgentId: agentFor(AgentRole.implementer), reviewerAgentId: agentFor(AgentRole.reviewer)),
        verificationCommands: <VerificationCommand>[
          for (final Object? command in commands)
            if (command is Map<String, Object?>) VerificationCommand.fromJson(command) else throw const FormatException('Each verification command must be an object.'),
        ],
        maxReviewCycles: maxReviewCycles,
        mcpServerIds: mcpServers.cast<String>(),
        modelOverrides: <AgentRole, String>{
          for (final MapEntry<String, Object?>(:String key, :Object? value) in models.entries) AgentRole.values.byName(key): value is String ? value : throw FormatException('models.$key must be a string.'),
        },
        fallbackAgentIds: <AgentRole, List<String>>{
          for (final MapEntry<String, Object?>(:String key, :Object? value) in fallbacks.entries) AgentRole.values.byName(key): value is List<Object?> && value.every((Object? id) => id is String) ? value.cast<String>() : throw FormatException('fallbacks.$key must be a list of agent IDs.'),
        },
        requirePlanApproval: flag('requirePlanApproval'),
        requireChangesApproval: flag('requireChangesApproval'),
        reviewPlan: flag('reviewPlan'),
        skipReviewWhenVerificationFails: flag('skipReviewWhenVerificationFails', fallback: true),
        maxTokens: maxTokens as int?,
        maxRetries: maxRetries,
        retryDelay: Duration(seconds: retryDelaySeconds),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid workflow settings: ${error.message}');
    }
  }

  static const int schemaVersion = 1;

  final AgentAssignments assignments;
  final List<VerificationCommand> verificationCommands;

  /// Reviews allowed; the workflow fails when the last one still requests
  /// changes.
  final int maxReviewCycles;

  /// MCP servers every agent in the workflow may use.
  final List<String> mcpServerIds;

  /// A model per role for the assigned agent, e.g. a cheaper planner.
  final Map<AgentRole, String> modelOverrides;

  /// Agents tried in order when a role's agent hits a usage limit or loses
  /// its sign-in.
  final Map<AgentRole, List<String>> fallbackAgentIds;

  /// Pause after planning until the user approves or revises the plan.
  final bool requirePlanApproval;

  /// Pause after implementation until the user approves the changes.
  final bool requireChangesApproval;

  /// Let the reviewer critique the plan before any code changes.
  final bool reviewPlan;

  /// Send failing checks straight back to the implementer without spending a
  /// review.
  final bool skipReviewWhenVerificationFails;

  /// Stops the workflow once agents have used more tokens than this.
  final int? maxTokens;

  /// Retries per agent run after a network failure.
  final int maxRetries;

  /// Wait before the first retry; doubled for each further one.
  final Duration retryDelay;

  /// Every agent this workflow may use, primary and fallback.
  Set<String> get allAgentIds => <String>{
    for (final AgentRole role in AgentRole.values) ...<String>[assignments.agentIdFor(role), ...?fallbackAgentIds[role]],
  };

  WorkflowSettings copyWith({
    AgentAssignments? assignments,
    List<VerificationCommand>? verificationCommands,
    int? maxReviewCycles,
    List<String>? mcpServerIds,
    Map<AgentRole, String>? modelOverrides,
    Map<AgentRole, List<String>>? fallbackAgentIds,
    bool? requirePlanApproval,
    bool? requireChangesApproval,
    bool? reviewPlan,
    bool? skipReviewWhenVerificationFails,
    int? maxTokens,
    bool clearMaxTokens = false,
    int? maxRetries,
    Duration? retryDelay,
  }) => WorkflowSettings(
    assignments: assignments ?? this.assignments,
    verificationCommands: verificationCommands ?? this.verificationCommands,
    maxReviewCycles: maxReviewCycles ?? this.maxReviewCycles,
    mcpServerIds: mcpServerIds ?? this.mcpServerIds,
    modelOverrides: modelOverrides ?? this.modelOverrides,
    fallbackAgentIds: fallbackAgentIds ?? this.fallbackAgentIds,
    requirePlanApproval: requirePlanApproval ?? this.requirePlanApproval,
    requireChangesApproval: requireChangesApproval ?? this.requireChangesApproval,
    reviewPlan: reviewPlan ?? this.reviewPlan,
    skipReviewWhenVerificationFails: skipReviewWhenVerificationFails ?? this.skipReviewWhenVerificationFails,
    maxTokens: clearMaxTokens ? null : maxTokens ?? this.maxTokens,
    maxRetries: maxRetries ?? this.maxRetries,
    retryDelay: retryDelay ?? this.retryDelay,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'assignments': <String, String>{for (final AgentRole role in AgentRole.values) role.name: assignments.agentIdFor(role)},
    'verificationCommands': <Map<String, Object?>>[for (final VerificationCommand command in verificationCommands) command.toJson()],
    'maxReviewCycles': maxReviewCycles,
    'mcpServers': mcpServerIds,
    'models': <String, String>{for (final MapEntry<AgentRole, String>(:AgentRole key, :String value) in modelOverrides.entries) key.name: value},
    'fallbacks': <String, List<String>>{for (final MapEntry<AgentRole, List<String>>(:AgentRole key, :List<String> value) in fallbackAgentIds.entries) key.name: value},
    'requirePlanApproval': requirePlanApproval,
    'requireChangesApproval': requireChangesApproval,
    'reviewPlan': reviewPlan,
    'skipReviewWhenVerificationFails': skipReviewWhenVerificationFails,
    'maxTokens': maxTokens,
    'maxRetries': maxRetries,
    'retryDelaySeconds': retryDelay.inSeconds,
  };
}

/// Stores default settings per repository and a frozen copy per workflow,
/// both outside the repository.
final class FileWorkflowSettingsStore {
  FileWorkflowSettingsStore({required WeaveStoragePaths paths}) : _projectsDirectory = paths.projectsDirectory, _workflowsDirectory = paths.workflowsDirectory;

  final String _projectsDirectory;
  final String _workflowsDirectory;

  /// Default settings for the repository at [repositoryRoot], if saved.
  Future<WorkflowSettings?> loadProjectDefaults(String repositoryRoot) => _load(File(path.join(encodedDirectory(_projectsDirectory, repositoryRoot, name: 'repositoryRoot').path, 'settings.json')));

  Future<void> saveProjectDefaults(String repositoryRoot, WorkflowSettings settings) => _save(File(path.join(encodedDirectory(_projectsDirectory, repositoryRoot, name: 'repositoryRoot').path, 'settings.json')), settings);

  /// The settings a workflow ran with.
  Future<WorkflowSettings?> loadForTask(String taskId) => _load(File(path.join(workflowTaskDirectory(_workflowsDirectory, taskId).path, 'settings.json')));

  Future<void> saveForTask(String taskId, WorkflowSettings settings) => _save(File(path.join(workflowTaskDirectory(_workflowsDirectory, taskId).path, 'settings.json')), settings);

  static Future<WorkflowSettings?> _load(File file) async {
    if (!await file.exists()) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Workflow settings must be an object.');
      }
      return WorkflowSettings.fromJson(decoded);
    } on FormatException catch (error) {
      throw WorkflowStorageFormatException('Invalid settings in ${file.path}.', cause: error);
    }
  }

  static Future<void> _save(File file, WorkflowSettings settings) async {
    try {
      await writeFileAtomically(file, encodePrettyJson(settings.toJson()));
    } on Object catch (error, stackTrace) {
      throw WorkflowStorageException('Unable to save settings to ${file.path}.', cause: error, stackTrace: stackTrace);
    }
  }
}
