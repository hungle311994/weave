import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

void main() {
  final WorkflowSettings settings = WorkflowSettings(
    assignments: AgentAssignments(plannerAgentId: 'codex', implementerAgentId: 'claude-code', reviewerAgentId: 'codex'),
    verificationCommands: <VerificationCommand>[VerificationCommand.parse('fvm dart analyze')],
    maxReviewCycles: 2,
    mcpServerIds: <String>['figma', 'figma'],
  );

  group('WorkflowSettings', () {
    test('round-trips through JSON', () {
      final WorkflowSettings restored = WorkflowSettings.fromJson(settings.toJson());

      expect(restored.toJson(), settings.toJson());
      expect(restored.assignments.agentIdFor(AgentRole.implementer), 'claude-code');
      expect(restored.mcpServerIds, <String>['figma']);
    });

    test('rejects invalid settings', () {
      final Map<String, Object?> valid = settings.toJson();
      for (final Map<String, Object?> invalid in <Map<String, Object?>>[
        <String, Object?>{...valid, 'schemaVersion': 2},
        <String, Object?>{
          ...valid,
          'assignments': <String, Object?>{'planner': 'codex'},
        },
        <String, Object?>{...valid, 'maxReviewCycles': 0},
        <String, Object?>{
          ...valid,
          'verificationCommands': <Object?>['fvm dart test'],
        },
      ]) {
        expect(() => WorkflowSettings.fromJson(invalid), throwsFormatException, reason: '$invalid');
      }
    });
  });

  group('FileWorkflowSettingsStore', () {
    late Directory temporaryDirectory;
    late FileWorkflowSettingsStore store;
    late WeaveStoragePaths paths;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('weave-settings-test-');
      paths = WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: <String, String>{'WEAVE_HOME': temporaryDirectory.path});
      store = FileWorkflowSettingsStore(paths: paths);
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('stores project defaults and per-task copies outside the repository', () async {
      const String repositoryRoot = '/Users/someone/my project';

      expect(await store.loadProjectDefaults(repositoryRoot), isNull);
      await store.saveProjectDefaults(repositoryRoot, settings);
      await store.saveForTask('task-1', settings);

      expect((await store.loadProjectDefaults(repositoryRoot))!.toJson(), settings.toJson());
      expect((await store.loadForTask('task-1'))!.maxReviewCycles, 2);
      expect(Directory(paths.projectsDirectory).listSync().single.path, isNot(contains('my project')));
    });

    test('reports corrupt settings', () async {
      await store.saveForTask('task-1', settings);
      final File file = Directory(paths.workflowsDirectory).listSync(recursive: true).whereType<File>().single;
      file.writeAsStringSync('[]');

      await expectLater(store.loadForTask('task-1'), throwsA(isA<WorkflowStorageFormatException>()));
      expect(path.basename(file.path), 'settings.json');
    });
  });

  group('parseReviewVerdict', () {
    test('reads the last verdict line', () {
      expect(parseReviewVerdict('Looks good.\nVERDICT: APPROVED'), ReviewVerdict.approved);
      expect(parseReviewVerdict('**Verdict:** changes_requested'), ReviewVerdict.changesRequested);
      expect(parseReviewVerdict('VERDICT: APPROVED\nOn second thought:\nVERDICT: CHANGES_REQUESTED\n'), ReviewVerdict.changesRequested);
      expect(parseReviewVerdict('I would say approved overall.'), ReviewVerdict.missing);
      expect(parseReviewVerdict('The previous VERDICT: APPROVED was wrong'), ReviewVerdict.missing);
    });
  });

  test('default prompts carry the context and the read-only rules', () {
    const DefaultWorkflowPrompts prompts = DefaultWorkflowPrompts();
    const WorkflowPromptContext context = WorkflowPromptContext(request: 'Add login', repositoryRoot: '/repo', reviewCycle: 1, plan: 'Step 1', reviewFeedback: 'Fix the null check', diff: '+line', isDiffTruncated: true);

    expect(prompts.planner(context), allOf(contains('Add login'), contains('read-only'), contains('/repo')));
    expect(prompts.implementer(context), allOf(contains('Step 1'), contains('Fix the null check'), contains('Never commit')));
    expect(prompts.selfReview(context), contains('Step 1'));
    expect(prompts.reviewer(context), allOf(contains('```diff\n+line\n```'), contains('truncated'), contains('VERDICT: APPROVED')));
  });
}
