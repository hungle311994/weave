import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';
import 'package:weave/features/new_task/domain/loaded_repository.dart';
import 'package:weave/features/new_task/domain/repository_picker_platform.dart';
import 'package:weave/features/new_task/presentation/dialogs/repository_picker_dialog.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../../../helpers/design_system_harness.dart';

final class _PickerPlatform implements RepositoryPickerPlatform {
  final StreamController<String> _drops = StreamController<String>.broadcast();
  final StreamController<bool> _hovering = StreamController<bool>.broadcast();
  String? directory;
  bool unavailable = false;
  int opened = 0;

  @override
  Stream<String> get droppedDirectories => _drops.stream;

  @override
  Stream<bool> get dragHovering => _hovering.stream;

  @override
  Future<String?> chooseDirectory() async {
    opened++;
    if (unavailable) {
      throw const DirectoryPickerUnavailableException('not registered');
    }
    return directory;
  }

  void drop(String value) => _drops.add(value);

  void hover(bool value) => _hovering.add(value);

  @override
  void dispose() {
    _drops.close();
    _hovering.close();
  }
}

final WorkflowSettings _settings = WorkflowSettings(
  assignments: AgentAssignments(plannerAgentId: 'agent', implementerAgentId: 'agent', reviewerAgentId: 'agent'),
);

Future<void> _open(
  WidgetTester tester, {
  required RepositoryPickerPlatform platform,
  required Future<LoadedRepository> Function(String directory) loadRepository,
  required Future<LoadedRepository> Function(String url, String parentDirectory) cloneRepository,
}) async {
  await pumpComponent(
    tester,
    Builder(
      builder: (BuildContext context) => WeaveButton(
        label: 'Open',
        onPressed: () => showRepositoryPickerDialog(
          context: context,
          recentRepositories: const <String>[],
          initialPath: '',
          platform: platform,
          loadRepository: loadRepository,
          cloneRepository: cloneRepository,
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<LoadedRepository> _loaded(String directory) async => LoadedRepository(root: directory, branch: 'main', settings: _settings);

void main() {
  testWidgets('one box opens Finder and uses the chosen folder right away', (WidgetTester tester) async {
    final _PickerPlatform platform = _PickerPlatform()..directory = '/projects/weave';
    addTearDown(platform.dispose);
    String? loadedDirectory;
    await _open(
      tester,
      platform: platform,
      loadRepository: (String directory) {
        loadedDirectory = directory;
        return _loaded(directory);
      },
      cloneRepository: (String url, String parentDirectory) => throw UnimplementedError(),
    );

    expect(
      find.descendant(of: find.byType(WeaveDialog), matching: find.byType(TextField)),
      findsNothing,
      reason: 'no path field to type into',
    );
    expect(find.byKey(const Key('repository-clone')), findsNothing, reason: 'nothing to confirm for a local folder');
    await tester.tap(find.byKey(const Key('repository-browse')));
    await tester.pumpAndSettle();

    expect(platform.opened, 1);
    expect(loadedDirectory, '/projects/weave');
    expect(find.byType(WeaveDialog), findsNothing);
  });

  testWidgets('cancelling Finder keeps the dialog open without an error', (WidgetTester tester) async {
    final _PickerPlatform platform = _PickerPlatform();
    addTearDown(platform.dispose);
    await _open(tester, platform: platform, loadRepository: _loaded, cloneRepository: (String url, String parentDirectory) => throw UnimplementedError());

    await tester.tap(find.byKey(const Key('repository-browse')));
    await tester.pumpAndSettle();

    expect(find.byType(WeaveDialog), findsOneWidget);
    expect(find.byKey(const Key('repository-error')), findsNothing);
  });

  testWidgets('keeps a folder that is not a repository in the dialog with the reason', (WidgetTester tester) async {
    final _PickerPlatform platform = _PickerPlatform()..directory = '/not-a-repository';
    addTearDown(platform.dispose);
    await _open(
      tester,
      platform: platform,
      loadRepository: (String directory) => throw StateError('Directory is not inside a Git repository'),
      cloneRepository: (String url, String parentDirectory) => throw UnimplementedError(),
    );

    await tester.tap(find.byKey(const Key('repository-browse')));
    await tester.pumpAndSettle();

    expect(find.byType(WeaveDialog), findsOneWidget);
    expect(find.textContaining('not inside a Git repository'), findsOneWidget);
  });

  testWidgets('explains when Finder cannot open instead of throwing', (WidgetTester tester) async {
    final _PickerPlatform platform = _PickerPlatform()..unavailable = true;
    addTearDown(platform.dispose);
    await _open(tester, platform: platform, loadRepository: _loaded, cloneRepository: (String url, String parentDirectory) => throw UnimplementedError());

    await tester.tap(find.byKey(const Key('repository-browse')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no unhandled MissingPluginException');
    expect(find.byType(WeaveDialog), findsOneWidget);
    expect(find.textContaining('Finder could not open'), findsOneWidget);
  });

  testWidgets('highlights the box while a folder is dragged over the window', (WidgetTester tester) async {
    final _PickerPlatform platform = _PickerPlatform();
    addTearDown(platform.dispose);
    await _open(tester, platform: platform, loadRepository: _loaded, cloneRepository: (String url, String parentDirectory) => throw UnimplementedError());
    WeaveSurface surface() => tester.widget<WeaveCard>(find.byKey(const Key('repository-browse'))).surface;

    expect(surface(), WeaveSurface.sunken);
    platform.hover(true);
    await tester.pumpAndSettle();
    expect(surface(), WeaveSurface.selected);
    expect(find.text('Drop the folder to use it'), findsOneWidget);
    platform.hover(false);
    await tester.pumpAndSettle();
    expect(surface(), WeaveSurface.sunken);
  });

  testWidgets('a recently used repository is used with one click', (WidgetTester tester) async {
    final _PickerPlatform platform = _PickerPlatform();
    addTearDown(platform.dispose);
    String? loadedDirectory;
    await pumpComponent(
      tester,
      Builder(
        builder: (BuildContext context) => WeaveButton(
          label: 'Open',
          onPressed: () => showRepositoryPickerDialog(
            context: context,
            recentRepositories: const <String>['/projects/recent'],
            initialPath: '',
            platform: platform,
            loadRepository: (String directory) {
              loadedDirectory = directory;
              return _loaded(directory);
            },
            cloneRepository: (String url, String parentDirectory) => throw UnimplementedError(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('repository-recent-/projects/recent')));
    await tester.pumpAndSettle();

    expect(loadedDirectory, '/projects/recent');
    expect(find.byType(WeaveDialog), findsNothing);
  });

  testWidgets('loads and closes when a repository folder is dropped', (WidgetTester tester) async {
    final _PickerPlatform platform = _PickerPlatform();
    addTearDown(platform.dispose);
    String? loadedDirectory;
    await _open(
      tester,
      platform: platform,
      loadRepository: (String directory) {
        loadedDirectory = directory;
        return _loaded(directory);
      },
      cloneRepository: (String url, String parentDirectory) => throw UnimplementedError(),
    );

    platform.drop('/projects/weave');
    await tester.pumpAndSettle();

    expect(loadedDirectory, '/projects/weave');
    expect(find.byType(WeaveDialog), findsNothing);
  });

  testWidgets('clones from a URL into a folder chosen in Finder', (WidgetTester tester) async {
    final _PickerPlatform platform = _PickerPlatform()..directory = '/projects';
    addTearDown(platform.dispose);
    String? clonedUrl;
    String? cloneParent;
    await _open(
      tester,
      platform: platform,
      loadRepository: (String directory) => throw UnimplementedError(),
      cloneRepository: (String url, String parentDirectory) async {
        clonedUrl = url;
        cloneParent = parentDirectory;
        return LoadedRepository(root: '/projects/weave', branch: 'main', settings: _settings);
      },
    );

    await tester.tap(find.text('Clone from URL'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No folder chosen'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('repository-url')), 'https://github.com/example/weave.git');
    await tester.tap(find.byKey(const Key('repository-clone')));
    await tester.pumpAndSettle();

    expect(platform.opened, 1, reason: 'Finder opens for the destination when none was chosen');
    expect(clonedUrl, 'https://github.com/example/weave.git');
    expect(cloneParent, '/projects');
    expect(find.byType(WeaveDialog), findsNothing);
  });

  testWidgets('offers SSH clone guidance and passes the SSH URL through unchanged', (WidgetTester tester) async {
    final _PickerPlatform platform = _PickerPlatform()..directory = '/projects';
    addTearDown(platform.dispose);
    String? clonedUrl;
    await _open(
      tester,
      platform: platform,
      loadRepository: (String directory) => throw UnimplementedError(),
      cloneRepository: (String url, String parentDirectory) async {
        clonedUrl = url;
        return LoadedRepository(root: '/projects/weave', branch: 'main', settings: _settings);
      },
    );

    await tester.tap(find.text('Clone from URL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSH'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssh-setup')), findsOneWidget);
    expect(find.textContaining('never stores the private key'), findsOneWidget);
    expect(find.byKey(const Key('copy-ssh-setup')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('repository-url')), 'git@github.com:example/weave.git');
    await tester.tap(find.byKey(const Key('repository-clone')));
    await tester.pumpAndSettle();

    expect(clonedUrl, 'git@github.com:example/weave.git');
  });
}
