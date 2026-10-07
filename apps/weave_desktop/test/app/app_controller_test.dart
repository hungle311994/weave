import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:weave/app/app_controller.dart';
import 'package:weave/app/preferences/sidebar_preference_store.dart';

void main() {
  test('defaults to expanded at every width and remembers an explicit choice', () async {
    final _MemorySidebarPreferenceStore preferences = _MemorySidebarPreferenceStore();
    final AppController controller = AppController(preferences, userName: 'alex');
    await controller.initialize();

    expect(controller.sidebarExpanded, isTrue);

    await controller.toggleSidebar();
    expect(controller.sidebarExpanded, isFalse);
    expect(preferences.expanded, isFalse);

    final AppController restored = AppController(preferences, userName: 'alex');
    await restored.initialize();
    expect(restored.sidebarExpanded, isFalse);
  });

  group('history', () {
    test('goes back and forward like a browser, and a new page clears forward', () {
      final AppController app = AppController(_MemorySidebarPreferenceStore(), userName: 'alex');
      expect((app.canGoBack, app.canGoForward), (false, false));

      app.select(const AgentsDestination());
      app.select(const AgentsDestination());
      app.select(const WorkflowDestination('wf-1'));
      app.goBack();
      expect(app.destination, isA<AgentsDestination>());
      app.goBack();
      expect(app.destination, isA<NewTaskDestination>(), reason: 'selecting the page already shown adds no history');
      expect(app.canGoBack, isFalse);

      app.goForward();
      app.goForward();
      expect(app.destination, const WorkflowDestination('wf-1'));
      app.goBack();
      app.select(const SettingsDestination());
      expect(app.canGoForward, isFalse);
    });

    test('a deleted workflow leaves the history and the screen', () {
      final AppController app = AppController(_MemorySidebarPreferenceStore(), userName: 'alex');
      app.select(const AgentsDestination());
      app.select(const WorkflowDestination('wf-1'));
      app.select(const AgentsDestination());
      app.select(const WorkflowDestination('wf-1'));

      app.forgetWorkflow('wf-1');
      expect(app.destination, isA<AgentsDestination>());
      app.goBack();
      expect(app.destination, isA<NewTaskDestination>(), reason: 'neither the workflow nor a repeated Agents page is left');
      expect(app.canGoBack, isFalse);
    });
  });

  test('file store tolerates invalid data and restores a saved choice', () async {
    final Directory directory = await Directory.systemTemp.createTemp('weave-sidebar-test-');
    addTearDown(() => directory.delete(recursive: true));
    final FileSidebarPreferenceStore store = FileSidebarPreferenceStore(directory.path);

    expect(await store.readExpanded(), isNull);
    await store.writeExpanded(true);
    expect(await store.readExpanded(), isTrue);

    await File('${directory.path}/ui-preferences.json').writeAsString('{invalid');
    expect(await store.readExpanded(), isNull);
  });
}

final class _MemorySidebarPreferenceStore implements SidebarPreferenceStore {
  bool? expanded;

  @override
  Future<bool?> readExpanded() async => expanded;

  @override
  Future<void> writeExpanded(bool value) async {
    expanded = value;
  }
}
