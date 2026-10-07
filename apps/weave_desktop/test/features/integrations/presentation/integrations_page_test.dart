import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../../../helpers/app_test_harness.dart';

/// A variable no test machine sets, so a server that needs it is never ready.
const String _unsetVariable = 'WEAVE_TEST_UNSET_MCP_TOKEN';

void main() {
  late AppTestHarness harness;

  setUp(() async {
    harness = AppTestHarness();
    await harness.initialize();
  });
  tearDown(() => harness.dispose());

  Future<void> openIntegrations(WidgetTester tester) async {
    await harness.launch(tester);
    await tester.tap(find.byKey(const Key('sidebar-plugins')));
    await tester.pumpAndSettle();
  }

  String statusOf(WidgetTester tester, String id) => tester.widget<WeaveStatusPill>(find.byKey(Key('mcp-status-$id'))).label;

  testWidgets('shows a draggable contextual sidebar and command-B hides only that sidebar', (WidgetTester tester) async {
    await openIntegrations(tester);

    expect(find.text('Customize'), findsOneWidget);
    expect(find.byKey(const Key('plugin-category-plugins')), findsOneWidget);
    expect(find.byKey(const Key('plugin-category-skills')), findsOneWidget);
    expect(find.text('INSTALLED'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Customize')).dy, WeaveLayout.windowTitleBarHeight + WeaveLayout.windowContentTopPadding);
    expect(tester.getSize(find.byKey(const Key('plugin-sub-sidebar'))).width, WeaveLayout.contextualSidebarWidth);
    expect(tester.getSize(find.byKey(const Key('sidebar-shell'))).width, WeaveLayout.sidebarCollapsed);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('plugin-sub-sidebar'))).width, 0);
    expect(tester.getSize(find.byKey(const Key('sidebar-shell'))).width, WeaveLayout.sidebarCollapsed);

    await tester.drag(find.byKey(const Key('plugin-sub-sidebar-handle')), const Offset(180, 0));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('plugin-sub-sidebar'))).width, WeaveLayout.contextualSidebarWidth);
  });

  testWidgets('switches between plugin and skill views from the contextual sidebar', (WidgetTester tester) async {
    await openIntegrations(tester);

    await tapReal(tester, find.byKey(const Key('plugin-category-skills')));
    expect(find.byKey(const Key('skills-empty')), findsOneWidget);
    expect(find.byKey(const Key('add-mcp')), findsNothing);

    await tapReal(tester, find.byKey(const Key('plugin-category-plugins')));
    expect(find.byKey(const Key('plugin-catalog')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('mcp-card-figma')), findsNothing, reason: 'installed plugins are listed in the sidebar, not here');
    expect(find.byKey(const Key('add-mcp')), findsOneWidget);
  });

  testWidgets('groups Figma into one sidebar item while retaining both server cards', (WidgetTester tester) async {
    await openIntegrations(tester);

    expect(find.byKey(const ValueKey<String>('installed-plugin-figma')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('plugin-categories')), matching: find.text('Figma')), findsOneWidget);

    await tapReal(tester, find.byKey(const ValueKey<String>('installed-plugin-figma')));

    expect(find.byKey(const ValueKey<String>('mcp-card-figma')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('mcp-card-figma-desktop')), findsOneWidget);
  });

  testWidgets('built-in servers show their brand, description and a Built-in badge in a two-column grid', (WidgetTester tester) async {
    await openIntegrations(tester);
    await tapReal(tester, find.byKey(const ValueKey<String>('installed-plugin-figma')));

    expect(find.text('Figma'), findsWidgets);
    expect(find.text('Design context from figma.com links'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('mcp-card-figma')), matching: find.byType(BrandIcon)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('mcp-card-figma')), matching: find.text('Built-in')), findsOneWidget);
    expect(find.byKey(const Key('remove-mcp-figma')), findsNothing, reason: 'built-in servers cannot be removed');
    expect(find.byKey(const Key('edit-mcp-figma')), findsNothing);

    final Rect hosted = tester.getRect(find.byKey(const ValueKey<String>('mcp-card-figma')));
    final Rect desktop = tester.getRect(find.byKey(const ValueKey<String>('mcp-card-figma-desktop')));
    expect(desktop.top, hosted.top, reason: 'two cards share a row');
    expect(desktop.height, hosted.height, reason: 'cards in a row share its height');
    expect(desktop.left - hosted.right, WeaveSpacing.s24);
    expect(find.byKey(const Key('mcp-readiness')), findsOneWidget);
    expect(find.byKey(const Key('check-mcp')), findsNothing, reason: 'readiness is re-checked automatically');
    expect(find.text('ACCESS POLICY'), findsOneWidget);
    expect(find.textContaining('Keychain'), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('adds, configures and removes a custom HTTP server; problems show as toasts', (WidgetTester tester) async {
    await openIntegrations(tester);

    await tester.tap(find.byKey(const Key('add-mcp')));
    await tester.pumpAndSettle();
    final Finder transport = find.byKey(const Key('mcp-transport'));
    expect(find.descendant(of: transport, matching: find.byWidgetPredicate((Widget widget) => widget is WeaveIcon && widget.icon == WeaveIcons.atSign)), findsOneWidget);
    expect(find.descendant(of: transport, matching: find.byWidgetPredicate((Widget widget) => widget is WeaveIcon && widget.icon == WeaveIcons.terminal)), findsOneWidget);
    final Size cancel = tester.getSize(find.widgetWithText(WeaveButton, 'Cancel'));
    final Size save = tester.getSize(find.byKey(const Key('save-mcp')));
    expect(cancel.height, WeaveLayout.controlHeight);
    expect(save.height, WeaveLayout.controlHeight);
    expect(tester.getCenter(find.widgetWithText(WeaveButton, 'Cancel')).dy, tester.getCenter(find.byKey(const Key('save-mcp'))).dy);
    expect(cancel.width, greaterThanOrEqualTo(WeaveLayout.buttonMinWidth));
    expect(save.width, greaterThanOrEqualTo(WeaveLayout.buttonMinWidth));
    final Finder dialogFields = find.descendant(of: find.byType(WeaveDialog), matching: find.byType(EditableText));
    expect(dialogFields, findsNWidgets(6));
    expect(<double>{for (final Element field in dialogFields.evaluate()) (field.renderObject! as RenderBox).size.height}, hasLength(1), reason: 'every empty field, single or multi-line, has the same height');

    await tester.tap(find.descendant(of: transport, matching: find.text('Command (stdio)')));
    await tester.pump();
    expect(find.text('Command'), findsOneWidget);
    await tester.tap(find.descendant(of: transport, matching: find.text('HTTP')));
    await tester.pump();
    expect(find.text('URL'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('mcp-name')), 'Tracker');
    await tester.enterText(find.byKey(const Key('mcp-id')), 'figma');
    await tester.enterText(find.byKey(const Key('mcp-endpoint')), 'https://tracker.example.com/mcp');
    await tester.tap(find.byKey(const Key('save-mcp')));
    await tester.pump();
    expect(find.byType(WeaveToast), findsOneWidget);
    expect(find.textContaining('"figma" already exists'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 10));

    await tester.enterText(find.byKey(const Key('mcp-id')), 'tracker');
    await tester.enterText(find.byKey(const Key('mcp-endpoint')), 'ftp://wrong');
    await tester.tap(find.byKey(const Key('save-mcp')));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(WeaveToast), matching: find.textContaining('http or https')),
      findsOneWidget,
      reason: 'errors are toasts, not inline text',
    );
    await tester.pumpAndSettle(const Duration(seconds: 10));

    await tester.enterText(find.byKey(const Key('mcp-endpoint')), 'https://tracker.example.com/mcp');
    await tester.enterText(find.byKey(const Key('mcp-description')), 'Issues and project context');
    await tester.enterText(find.descendant(of: find.byType(WeaveDialog), matching: find.byType(EditableText)).at(4), 'Authorization=Bearer \${$_unsetVariable}');
    await tapReal(tester, find.byKey(const Key('save-mcp')));
    // The saved plugin opens in its installed view.
    await pumpUntil(tester, () => find.byKey(const Key('mcp-status-tracker')).evaluate().isNotEmpty && statusOf(tester, 'tracker') != 'Checking…');
    expect(File(mcpFilePath(harness.paths)).readAsStringSync(), allOf(contains('https://tracker.example.com/mcp'), contains('\${$_unsetVariable}')));
    expect(find.text('Issues and project context'), findsOneWidget);
    expect(statusOf(tester, 'tracker'), 'Needs setup');
    expect(find.text('Set \$$_unsetVariable in the environment Weave starts from, then reopen Weave.'), findsWidgets);

    await tester.tap(find.byKey(const Key('edit-mcp-tracker')));
    await tester.pumpAndSettle();
    expect(find.text('Configure Tracker'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('mcp-id')), matching: find.byType(EditableText))).readOnly || !tester.widget<TextField>(find.descendant(of: find.byKey(const Key('mcp-id')), matching: find.byType(TextField))).enabled!,
      isTrue,
      reason: 'the ID cannot change',
    );
    await tester.enterText(find.byKey(const Key('mcp-description')), 'Linear issues');
    await tester.enterText(find.descendant(of: find.byType(WeaveDialog), matching: find.byType(EditableText)).at(4), '');
    await tapReal(tester, find.byKey(const Key('save-mcp')));
    await pumpUntil(tester, () => find.text('Linear issues').evaluate().isNotEmpty && statusOf(tester, 'tracker') == 'Ready');
    expect(harness.services.mcp['tracker']?.description, 'Linear issues');

    await tapReal(tester, find.byKey(const Key('remove-mcp-tracker')));
    await tester.pumpAndSettle();
    expect(find.text('Remove MCP server?'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('mcp-card-tracker')), findsOneWidget, reason: 'the server remains until removal is confirmed');
    await tapReal(tester, find.byKey(const Key('confirm-remove-mcp')));
    await pumpUntil(tester, () => find.byKey(const ValueKey<String>('mcp-card-tracker')).evaluate().isEmpty);
    expect(harness.services.mcp['tracker'], isNull);
    expect(find.byKey(const Key('plugin-catalog')), findsOneWidget, reason: 'with nothing left to show, the catalog comes back');
  });

  testWidgets('a local server whose command is not installed needs setup', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await saveCustomMcpServers(harness.paths, <McpServerDefinition>[
        McpServerDefinition(
          id: 'local',
          displayName: 'Local tools',
          transport: McpStdioTransport(command: 'weave-test-missing-mcp-command', arguments: const <String>['--stdio']),
        ),
      ]);
      await harness.services.reloadMcp();
    });
    await openIntegrations(tester);
    await tapReal(tester, find.byKey(const ValueKey<String>('installed-plugin-local')));
    await pumpUntil(tester, () => statusOf(tester, 'local') != 'Checking…');

    expect(statusOf(tester, 'local'), 'Needs setup');
    expect(find.text('weave-test-missing-mcp-command was not found on this Mac.'), findsWidgets);
    expect(find.text('weave-test-missing-mcp-command --stdio'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey<String>('mcp-card-local')), matching: find.byWidgetPredicate((Widget widget) => widget is WeaveIcon && widget.icon == WeaveIcons.terminal)), findsOneWidget);
  });

  testWidgets('re-checks readiness when the user comes back to Weave', (WidgetTester tester) async {
    final String command = path.join(harness.temporaryDirectory.path, 'local-mcp-server');
    await tester.runAsync(() async {
      await saveCustomMcpServers(harness.paths, <McpServerDefinition>[
        McpServerDefinition(
          id: 'local',
          displayName: 'Local tools',
          transport: McpStdioTransport(command: command),
        ),
      ]);
      await harness.services.reloadMcp();
    });
    await openIntegrations(tester);
    await tapReal(tester, find.byKey(const ValueKey<String>('installed-plugin-local')));
    await pumpUntil(tester, () => statusOf(tester, 'local') == 'Needs setup');

    // The user installs the command elsewhere, then returns to Weave.
    await tester.runAsync(() async {
      await File(command).writeAsString('#!/bin/sh\n');
      await Process.run('chmod', <String>['755', command]);
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpUntil(tester, () => statusOf(tester, 'local') == 'Ready');
  });

  testWidgets('lists catalog plugins by category; + adds one to mcp.json as an installed plugin', (WidgetTester tester) async {
    await openIntegrations(tester);
    final Finder list = find.ancestor(of: find.byKey(const Key('plugin-search')), matching: find.byType(Scrollable)).first;
    final Finder github = find.byKey(const ValueKey<String>('catalog-github'));
    await tester.scrollUntilVisible(github, 200, scrollable: list);

    expect(find.descendant(of: find.byKey(const Key('catalog-popular')), matching: find.text('Popular')), findsOneWidget);
    expect(find.descendant(of: github, matching: find.byType(BrandIcon)), findsOneWidget);
    expect(find.descendant(of: github, matching: find.text('Issues, pull requests, code search and Actions')), findsOneWidget);
    expect(find.byKey(const Key('add-mcp')), findsOneWidget, reason: 'Add plugin stays for servers outside the catalog');

    await tester.ensureVisible(find.byKey(const Key('catalog-add-github')));
    await tester.pumpAndSettle();
    await tapReal(tester, find.byKey(const Key('catalog-add-github')));
    await pumpUntil(tester, () => find.byKey(const Key('catalog-added-github')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('catalog-add-github')), findsNothing);
    expect(File(mcpFilePath(harness.paths)).readAsStringSync(), allOf(contains('https://api.githubcopilot.com/mcp/'), contains(r'Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}')), reason: 'the token stays an environment reference');
    expect(harness.services.mcp['github'], isNotNull);
    expect(find.byKey(const ValueKey<String>('installed-plugin-github')), findsOneWidget, reason: 'listed under Installed in the sidebar');
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('search filters the suggested plugins and searches the MCP Registry after a pause', (WidgetTester tester) async {
    await openIntegrations(tester);

    await tester.enterText(find.byKey(const Key('plugin-search')), 'play');
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('catalog-playwright')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('catalog-github')), findsNothing);
    expect(find.byKey(const Key('catalog-popular')), findsNothing, reason: 'a category with no match is hidden');
    expect(find.byKey(const Key('registry-searching')), findsOneWidget);
    expect(harness.registryRequests, isEmpty, reason: 'nothing is sent while the user is still typing');

    await tester.enterText(find.byKey(const Key('plugin-search')), 'no such plugin');
    await tester.pump(WeaveMotion.searchDebounce);
    await tester.pump();
    expect(find.byKey(const Key('catalog-no-match')), findsOneWidget);
    expect(harness.registryRequests.map((Uri uri) => uri.queryParameters['search']), <String>['no such plugin'], reason: 'one request, for the final text only');
    final Finder empty = find.byKey(const Key('registry-empty'));
    await tester.scrollUntilVisible(
      empty,
      200,
      scrollable: find.ancestor(of: find.byKey(const Key('plugin-search')), matching: find.byType(Scrollable)).first,
    );
    expect(empty, findsOneWidget);
  });

  testWidgets('MCP Registry results are labelled Community; + adds a supported one, others say why not', (WidgetTester tester) async {
    harness.registryResponse = '''
{"servers": [
  {"server": {"name": "io.github.getsentry/sentry-mcp", "description": "Sentry issues", "version": "0.42.0",
    "packages": [{"registryType": "npm", "identifier": "@sentry/mcp-server", "version": "0.42.0", "transport": {"type": "stdio"},
      "environmentVariables": [{"name": "SENTRY_ACCESS_TOKEN", "isRequired": true, "isSecret": true}]}]},
   "_meta": {"io.modelcontextprotocol.registry/official": {"status": "active", "isLatest": true}}},
  {"server": {"name": "example/docker-only", "description": "Runs in Docker", "version": "1",
    "packages": [{"registryType": "oci", "identifier": "ghcr.io/x/y", "transport": {"type": "stdio"}}]},
   "_meta": {"io.modelcontextprotocol.registry/official": {"status": "active", "isLatest": true}}}
]}''';
    await openIntegrations(tester);
    await tester.enterText(find.byKey(const Key('plugin-search')), 'sentry');
    await tester.pump(WeaveMotion.searchDebounce);
    await tester.pump();
    final Finder list = find.ancestor(of: find.byKey(const Key('plugin-search')), matching: find.byType(Scrollable)).first;
    const String name = 'io.github.getsentry/sentry-mcp';
    await tester.scrollUntilVisible(find.byKey(const ValueKey<String>('registry-$name')), 200, scrollable: list);

    expect(find.descendant(of: find.byKey(const Key('catalog-registry')), matching: find.text('Community')), findsOneWidget);
    expect(find.byKey(const Key('registry-unsupported-example/docker-only')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('registry-add-$name')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tapReal(tester, find.byKey(const Key('registry-add-$name')));
    await pumpUntil(tester, () => find.byKey(const Key('registry-added-$name')).evaluate().isNotEmpty);

    final String file = File(mcpFilePath(harness.paths)).readAsStringSync();
    expect(file, allOf(contains('@sentry/mcp-server@0.42.0'), contains(r'${SENTRY_ACCESS_TOKEN}')));
    expect(harness.services.mcp['sentry-mcp']?.setupHint, contains('community'));
    expect(find.byKey(const ValueKey<String>('installed-plugin-sentry-mcp')), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('an unreachable MCP Registry shows why, without breaking the suggested plugins', (WidgetTester tester) async {
    harness.registryFailure = const SocketException('offline');
    await openIntegrations(tester);
    await tester.enterText(find.byKey(const Key('plugin-search')), 'linear');
    await tester.pump(WeaveMotion.searchDebounce);
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('catalog-linear')), findsOneWidget);
    final Finder error = find.byKey(const Key('registry-error'));
    await tester.scrollUntilVisible(
      error,
      200,
      scrollable: find.ancestor(of: find.byKey(const Key('plugin-search')), matching: find.byType(Scrollable)).first,
    );
    expect(tester.widget<Text>(error).data, contains('could not be reached'));
  });
}
