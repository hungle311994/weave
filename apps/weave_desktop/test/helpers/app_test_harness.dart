import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';
import 'package:path/path.dart' as path;
import 'package:weave/app/weave_app.dart';
import 'package:weave/app/weave_app_scope.dart';
import 'package:weave/app/window/window_chrome.dart';
import 'package:weave/features/agents/domain/terminal_launcher.dart';
import 'package:weave/features/onboarding/data/file_onboarding_repository.dart';
import 'package:weave/features/new_task/domain/repository_picker_platform.dart';
import 'package:weave_agents/testing.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_storage/weave_storage.dart';
import 'package:weave_workflow/weave_workflow.dart';

/// Lets real file and process I/O finish, then rebuilds, until [condition].
Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {Duration timeout = const Duration(seconds: 15)}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      final List<String> texts = <String>[for (final Element element in find.byType(Text).evaluate()) (element.widget as Text).data ?? ''];
      fail('Timed out waiting for the UI to update. Visible text: $texts');
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Taps [finder] in the real zone so file and process I/O can finish.
Future<void> tapReal(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() => tester.tap(finder));
  await tester.pump();
}

/// Controllable directory picker and drop source for widget tests.
final class FakeRepositoryPickerPlatform implements RepositoryPickerPlatform {
  final StreamController<String> _drops = StreamController<String>.broadcast();
  final StreamController<bool> _hovering = StreamController<bool>.broadcast();

  /// What the fake Finder panel returns next; null means the user cancelled.
  String? nextDirectory;

  @override
  Stream<String> get droppedDirectories => _drops.stream;

  @override
  Stream<bool> get dragHovering => _hovering.stream;

  void hover(bool hovering) => _hovering.add(hovering);

  @override
  Future<String?> chooseDirectory() async => nextDirectory;

  void drop(String directory) => _drops.add(directory);

  @override
  void dispose() {
    _drops.close();
    _hovering.close();
  }
}

/// Reports a fixed traffic-light position, like the macOS runner would.
final class FakeWindowChrome implements WindowChrome {
  double? center;

  @override
  Future<double?> trafficLightCenter() async => center;
}

/// Records what would open in Terminal instead of opening it.
final class FakeTerminalLauncher implements TerminalLauncher {
  final List<String> commands = <String>[];

  @override
  Future<void> run(String command, {required String name}) async => commands.add(command);
}

/// Isolated services, repository, and UI launcher shared by desktop tests.
final class AppTestHarness {
  late Directory temporaryDirectory;
  late Directory repository;
  late WeaveStoragePaths paths;
  late WeaveServices services;

  /// Stands in for Finder; tests set [FakeRepositoryPickerPlatform.nextDirectory].
  final FakeRepositoryPickerPlatform picker = FakeRepositoryPickerPlatform();

  /// Stands in for Terminal; sign-in commands land in [FakeTerminalLauncher.commands].
  final FakeTerminalLauncher terminal = FakeTerminalLauncher();

  /// Stands in for the macOS window; set [FakeWindowChrome.center] to size the title bar.
  final FakeWindowChrome windowChrome = FakeWindowChrome();

  /// What the stand-in MCP Registry answers; tests never reach the network.
  String registryResponse = '{"servers": []}';

  /// Set to make the stand-in MCP Registry fail.
  Object? registryFailure;

  /// Every MCP Registry request a test made.
  final List<Uri> registryRequests = <Uri>[];

  late final McpRegistryClient registry = McpRegistryClient(
    fetch: (Uri uri) async {
      registryRequests.add(uri);
      if (registryFailure case final Object failure) {
        throw failure;
      }
      return registryResponse;
    },
  );

  String writeNotes(AgentRunRequest request, ScriptedAgentSession session) {
    File(path.join(request.workingDirectory, 'notes.txt')).writeAsStringSync('notes\n');
    session.write('wrote notes.txt\n');
    return 'Added notes.txt';
  }

  ScriptedAgentAdapter solo({ScriptedAgentHandler? implement}) => ScriptedAgentAdapter(
    id: 'solo',
    displayName: 'Solo Agent',
    handler: (AgentRunRequest request, ScriptedAgentSession session) async => switch (request.role) {
      AgentRole.planner => 'Plan: add notes.txt',
      AgentRole.implementer => await (implement ?? writeNotes)(request, session),
      AgentRole.reviewer => 'VERDICT: APPROVED',
    },
  );

  WeaveServices servicesWith(List<AgentAdapter> agents) => WeaveServices(paths: paths, agents: AgentRegistry(agents), environment: Platform.environment);

  Future<void> initialize() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('weave-desktop-test-');
    repository = await Directory(path.join(temporaryDirectory.path, 'repo')).create();
    await Process.run('git', <String>['init', '--quiet', '--initial-branch=main'], workingDirectory: repository.path);
    paths = WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: <String, String>{'WEAVE_HOME': path.join(temporaryDirectory.path, 'home')});
    services = servicesWith(<AgentAdapter>[
      solo(),
      ScriptedAgentAdapter(id: 'offline', displayName: 'Offline Agent', isAvailable: false, handler: (AgentRunRequest request, ScriptedAgentSession session) => ''),
    ]);
  }

  Future<void> dispose() async {
    picker.dispose();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  }

  Future<void> launch(WidgetTester tester, {Size size = const Size(1400, 1000), bool onboardingComplete = true, RepositoryPickerPlatform? repositoryPicker}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (onboardingComplete) {
      await tester.runAsync(() => FileOnboardingRepository(paths.rootDirectory).markCompleted());
    }
    await tester.pumpWidget(
      WeaveApp(
        createScope: () async => WeaveAppScope.create(services, repositoryPicker: repositoryPicker ?? picker, terminal: terminal, mcpRegistry: registry, windowChrome: windowChrome),
      ),
    );
    await pumpUntil(tester, () => (onboardingComplete ? find.text('Start workflow') : find.text('Welcome to Weave')).evaluate().isNotEmpty);
  }

  /// Adds [directory] to the task through the repository picker and the
  /// (fake) Finder panel.
  Future<void> chooseRepository(WidgetTester tester, String directory) async {
    await tester.ensureVisible(find.byKey(const Key('repository-add')));
    await tapReal(tester, find.byKey(const Key('repository-add')));
    await tester.pumpAndSettle();
    picker.nextDirectory = directory;
    await tapReal(tester, find.byKey(const Key('repository-browse')));
    await pumpUntil(tester, () => find.byType(WeaveDialog).evaluate().isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Picks [agentId] for every role through the agent picker; New Task never
  /// chooses agents on its own.
  Future<void> chooseAgents(WidgetTester tester, {String agentId = 'solo'}) async {
    for (final String role in const <String>['planner', 'implementer', 'reviewer']) {
      await tester.ensureVisible(find.byKey(Key('agent-$role')));
      await tapReal(tester, find.byKey(Key('agent-$role')));
      await pumpUntil(tester, () => find.byKey(Key('pick-agent-$agentId')).evaluate().isNotEmpty);
      await tester.tap(find.byKey(Key('pick-agent-$agentId')));
      await tester.pump();
      await tapReal(tester, find.byKey(const Key('agent-select')));
      await pumpUntil(tester, () => find.byType(WeaveDialog).evaluate().isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// Loads the test repository and starts [request] from the form.
  Future<void> startFromForm(WidgetTester tester, String request) async {
    await chooseRepository(tester, repository.path);
    await chooseAgents(tester);
    await tester.enterText(find.byKey(const Key('request')), request);
    await tapReal(tester, find.byKey(const Key('start')));
    await pumpUntil(tester, () => find.byKey(const Key('advanced-save')).evaluate().isNotEmpty);
    await tapReal(tester, find.byKey(const Key('advanced-save')));
  }
}
