import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';
import 'package:weave/features/new_task/presentation/new_task_page.dart';
import 'package:weave/features/integrations/presentation/integrations_page.dart';
import 'package:weave_agents/testing.dart';
import 'package:weave_agents/weave_agents.dart';

import '../helpers/app_test_harness.dart';

void main() {
  late AppTestHarness harness;

  setUp(() async {
    harness = AppTestHarness();
    await harness.initialize();
  });
  tearDown(() => harness.dispose());

  testWidgets('shows every configured agent with its readiness and where custom agents live', (WidgetTester tester) async {
    await harness.launch(tester);

    await tapReal(tester, find.byKey(const Key('sidebar-agents')));
    await pumpUntil(tester, () => find.byKey(const ValueKey<String>('agent-card-solo')).evaluate().isNotEmpty);

    Finder inCard(String id, Finder finder) => find.descendant(of: find.byKey(ValueKey<String>('agent-card-$id')), matching: finder);
    await pumpUntil(tester, () => inCard('offline', find.text('Setup required')).evaluate().isNotEmpty || inCard('offline', find.text('Not installed')).evaluate().isNotEmpty);
    expect(inCard('solo', find.text('Solo Agent')), findsOneWidget);
    expect(inCard('solo', find.text('Ready')), findsOneWidget);
    expect(inCard('offline', find.textContaining('offline is not available.')), findsOneWidget);
    expect(find.textContaining('agents.json'), findsWidgets);
    expect(find.textContaining('Keychain'), findsNothing, reason: 'Weave stores no credentials');
    final Rect solo = tester.getRect(find.byKey(const ValueKey<String>('agent-card-solo')));
    final Rect offline = tester.getRect(find.byKey(const ValueKey<String>('agent-card-offline')));
    expect(offline.top, solo.top, reason: 'cards sit in a grid');
  });

  testWidgets('shows installation guidance for a missing command agent', (WidgetTester tester) async {
    final AgentDefinition definition = AgentDefinition.fromJson(<String, Object?>{
      'id': 'missing-test-agent',
      'displayName': 'Missing Test Agent',
      'executable': 'weave-missing-test-agent',
      'sandboxArguments': <String, Object?>{'readOnly': <String>[], 'workspaceWrite': <String>[]},
      'installOptions': <Map<String, Object?>>[
        <String, Object?>{
          'label': 'Homebrew',
          'command': <String>['brew', 'install', 'missing-test-agent'],
        },
        <String, Object?>{
          'label': 'npm',
          'command': <String>['npm', 'install', '-g', 'missing-test-agent'],
        },
      ],
    });
    harness.services = harness.servicesWith(<AgentAdapter>[
      harness.solo(),
      CommandAgentAdapter(definition, environment: const <String, String>{'PATH': '/nonexistent', 'HOME': '/nonexistent'}),
    ]);
    await harness.launch(tester);

    await tapReal(tester, find.byKey(const Key('sidebar-agents')));
    await pumpUntil(tester, () => find.byKey(const Key('copy-install-missing-test-agent')).evaluate().isNotEmpty);

    expect(find.text('Homebrew: brew install missing-test-agent'), findsOneWidget);
    expect(find.text('npm: npm install -g missing-test-agent'), findsOneWidget);
    expect(find.byKey(const Key('copy-install-missing-test-agent')), findsOneWidget);
    expect(find.byKey(const Key('copy-install-missing-test-agent-1')), findsOneWidget);
    expect(find.text('Copy install'), findsNothing);
    expect(find.byTooltip('Copy Homebrew command'), findsOneWidget);
    expect(find.byTooltip('Copy npm command'), findsOneWidget);
  });

  testWidgets('uses a fixed compact icon rail while command-B controls the plugin sub-sidebar', (WidgetTester tester) async {
    await harness.launch(tester, size: const Size(1100, 720));

    final Finder titleBar = find.byKey(const Key('window-title-bar'));
    final Finder sidebar = find.byKey(const Key('sidebar-shell'));
    expect(tester.getSize(titleBar).height, WeaveLayout.windowTitleBarHeight);
    expect(tester.getTopLeft(sidebar).dy, tester.getBottomLeft(titleBar).dy, reason: 'every app column starts below the native window controls');
    expect(tester.getTopLeft(find.byType(WeaveLogoMark)).dy, tester.getBottomLeft(titleBar).dy + WeaveLayout.windowContentTopPadding);
    expect(tester.getSize(find.byKey(const Key('sidebar-shell'))).width, WeaveLayout.sidebarCollapsed);
    expect(tester.widget<WeaveAccountButton>(find.byKey(const Key('sidebar-account'))).expanded, isFalse);
    expect(find.byKey(const Key('sidebar-resize-handle')), findsNothing);
    expect(find.byTooltip('Home'), findsOneWidget, reason: 'sidebars are shown, so rail items show tooltips');
    expect(find.byTooltip('Agents'), findsOneWidget);
    expect(find.byTooltip('Plugins'), findsOneWidget);

    await tapReal(tester, find.byKey(const Key('sidebar-plugins')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('plugin-sub-sidebar'))).width, WeaveLayout.contextualSidebarWidth);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('sidebar-shell'))).width, WeaveLayout.sidebarCollapsed);
    expect(find.byKey(const Key('sidebar-account')).hitTestable(), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('plugin-sub-sidebar'))).width, 0);
  });

  testWidgets('the icon rail has no expanded or draggable state', (WidgetTester tester) async {
    await harness.launch(tester, size: const Size(1100, 720));

    expect(find.byKey(const Key('sidebar-resize-handle')), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('sidebar-shell')), matching: find.byType(WeaveSidebarResizeHandle)), findsNothing);
    expect(find.text('Workspace'), findsNothing);
  });

  testWidgets('draws the ambient glow behind the top of the workspace, as in the design', (WidgetTester tester) async {
    await harness.launch(tester, size: WeaveLayout.defaultWindow);
    final Finder glow = find.byKey(const Key('ambient-glow'));
    final Finder shell = find.byKey(const Key('sidebar-shell'));

    expect(tester.getSize(glow), WeaveLayout.ambientGlowSize);
    expect(tester.getTopLeft(glow), Offset(tester.getRect(shell).right + WeaveLayout.ambientGlowOffset.dx, WeaveLayout.windowTitleBarHeight + WeaveLayout.ambientGlowOffset.dy));
    final DecoratedBox fill = tester.widget<DecoratedBox>(find.descendant(of: glow, matching: find.byType(DecoratedBox)));
    expect((fill.decoration as BoxDecoration).gradient, WeaveGradients.ambientGlow);
    expect(
      find.descendant(of: glow, matching: find.byType(IgnorePointer)),
      findsWidgets,
      reason: 'decorative: it never takes clicks from the page',
    );
    expect(find.text('What should Weave build?').hitTestable(), findsOneWidget, reason: 'the page is drawn above the glow');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(glow).dx, tester.getRect(shell).right + WeaveLayout.ambientGlowOffset.dx, reason: 'the fixed icon rail does not move');
  });

  testWidgets('guides first-time setup when no agent is ready', (WidgetTester tester) async {
    harness.services = harness.servicesWith(<AgentAdapter>[
      ScriptedAgentAdapter(id: 'claude-like', displayName: 'Signed-out Agent', isAvailable: false, signInCommand: 'agent auth login', handler: (AgentRunRequest request, ScriptedAgentSession session) => ''),
    ]);
    await harness.launch(tester);
    await pumpUntil(tester, () => find.byKey(const Key('setup-banner')).evaluate().isNotEmpty);

    await tester.tap(find.text('Open Agents'));
    await pumpUntil(tester, () => find.byKey(const Key('copy-sign-in-claude-like')).evaluate().isNotEmpty);
    expect(find.textContaining('Run `agent auth login` in Terminal'), findsOneWidget);
  });

  testWidgets('keeps only sidebar and Settings shortcuts', (WidgetTester tester) async {
    await harness.launch(tester);

    expect(find.text('⌘N'), findsNothing);
    expect(find.text('⇧⌘A'), findsNothing);
    expect(find.text('⇧⌘I'), findsNothing);
    expect(find.text('⌘,'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('Permissions & safety'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('sidebar-shell'))).width, WeaveLayout.sidebarCollapsed);
    await tester.tap(find.byKey(const Key('sidebar-account')));
    await tester.pumpAndSettle();
    expect(find.text('Local profile'), findsOneWidget);
    expect(find.text('⌘,'), findsOneWidget);
  });

  testWidgets('does not intercept command-A inside text fields', (WidgetTester tester) async {
    await harness.launch(tester);
    final Finder requestFinder = find.descendant(of: find.byKey(const Key('request')), matching: find.byType(TextField));
    await tester.enterText(requestFinder, 'Select this task');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(requestFinder, findsOneWidget);
    expect(find.text('What should Weave build?'), findsOneWidget, reason: 'the field consumes Select All instead of navigating to Agents');
  });

  testWidgets('title-bar Back and Forward walk the visited screens; ⌘[ and ⌘] do the same', (WidgetTester tester) async {
    await harness.launch(tester);
    WeaveIconButton control(String key) => tester.widget<WeaveIconButton>(find.byKey(Key(key)));
    expect(control('titlebar-back').onPressed, isNull, reason: 'nothing to go back to yet');
    expect(control('titlebar-forward').onPressed, isNull);
    final Rect bar = tester.getRect(find.byKey(const Key('window-title-bar')));
    expect(tester.getTopLeft(find.byKey(const Key('titlebar-back'))).dx - bar.left, WeaveLayout.windowControlsInset, reason: 'right of the traffic lights');
    expect(tester.getCenter(find.byKey(const Key('titlebar-back'))).dy - bar.top, bar.height / 2, reason: 'vertically centred, like the traffic lights');
    expect(tester.getSize(find.byKey(const Key('titlebar-back'))), const Size.square(WeaveLayout.windowControlSize));

    await tapReal(tester, find.byKey(const Key('sidebar-agents')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('titlebar-back')));
    await tester.pumpAndSettle();
    expect(find.text('What should Weave build?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('titlebar-forward')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-agent')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('What should Weave build?'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-agent')), findsOneWidget);
  });

  testWidgets('the title-bar toggle hides and shows a screen\'s contextual sidebar', (WidgetTester tester) async {
    await harness.launch(tester);
    WeaveIconButton toggle() => tester.widget<WeaveIconButton>(find.byKey(const Key('titlebar-toggle-sidebar')));
    await tapReal(tester, find.byKey(const Key('sidebar-plugins')));
    await tester.pumpAndSettle();
    expect(toggle().icon, WeaveIcons.panelClose);

    await tester.tap(find.byKey(const Key('titlebar-toggle-sidebar')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('plugin-sub-sidebar'))).width, 0);
    expect(toggle().icon, WeaveIcons.panelOpen);
    await tester.tap(find.byKey(const Key('titlebar-toggle-sidebar')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('plugin-sub-sidebar'))).width, WeaveLayout.contextualSidebarWidth);

    await tapReal(tester, find.byKey(const Key('sidebar-agents')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('titlebar-toggle-sidebar')), findsNothing, reason: 'Agents has no contextual sidebar, so no toggle');
  });

  testWidgets('Settings starts at the top like every other screen', (WidgetTester tester) async {
    await harness.launch(tester);
    final double agentsTop = await () async {
      await tapReal(tester, find.byKey(const Key('sidebar-agents')));
      await tester.pumpAndSettle();
      return tester.getTopLeft(find.text('Agents').last).dy;
    }();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Settings').last).dy, agentsTop, reason: 'a short page is not centred in the window');
  });

  testWidgets('the title bar is sized from where macOS draws the traffic lights, so every control is centred', (WidgetTester tester) async {
    harness.windowChrome.center = 16;
    await harness.launch(tester);

    final Rect bar = tester.getRect(find.byKey(const Key('window-title-bar')));
    expect(bar.height, 32);
    expect(tester.getCenter(find.byKey(const Key('titlebar-back'))).dy - bar.top, 16);
    expect(tester.getCenter(find.byKey(const Key('titlebar-toggle-sidebar'))).dy - bar.top, 16);
  });

  group('floating sidebar', () {
    Future<TestGesture> mouseAt(WidgetTester tester, Offset position) async {
      final TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: position);
      await tester.pump();
      return mouse;
    }

    testWidgets('while the sidebar is hidden, hovering Home floats it over the page until the pointer leaves', (WidgetTester tester) async {
      await harness.launch(tester);
      await tester.tap(find.byKey(const Key('titlebar-toggle-sidebar')));
      await tester.pumpAndSettle();
      final Finder peek = find.byKey(const Key('sidebar-peek'));
      expect(peek, findsNothing);
      final Offset heading = tester.getTopLeft(find.text('What should Weave build?'));

      final TestGesture mouse = await mouseAt(tester, tester.getCenter(find.byKey(const Key('sidebar-home'))));
      await tester.pump(WeaveMotion.peekIn ~/ 2);
      final double halfway = tester.widget<FadeTransition>(find.ancestor(of: peek, matching: find.byType(FadeTransition)).first).opacity.value;
      expect(halfway, allOf(greaterThan(0), lessThan(1)), reason: 'fades in instead of appearing at once');
      await tester.pumpAndSettle();
      expect(peek, findsOneWidget);
      expect(find.byTooltip('Home'), findsNothing, reason: 'an item with a sidebar shows it instead of a tooltip');
      expect(find.descendant(of: peek, matching: find.byType(HomeSidebarContent)), findsOneWidget);
      final Rect panel = tester.getRect(peek);
      expect(panel.left, tester.getRect(find.byKey(const Key('sidebar-shell'))).right + WeaveSpacing.s8, reason: 'floats beside the rail');
      expect(panel.width, WeaveLayout.contextualSidebarWidth);
      expect(tester.getTopLeft(find.text('What should Weave build?')), heading, reason: 'floats over the page, which does not move');

      // Moving into the panel keeps it open.
      await mouse.moveTo(panel.center);
      await tester.pump(WeaveMotion.peekHideDelay * 2);
      expect(peek, findsOneWidget);

      await mouse.moveTo(Offset(panel.right + 200, panel.center.dy));
      await tester.pump(WeaveMotion.peekHideDelay);
      await tester.pumpAndSettle();
      expect(peek, findsNothing);

      // Items without a sidebar still name themselves.
      await mouse.moveTo(tester.getCenter(find.byKey(const Key('sidebar-agents'))));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(peek, findsNothing);
      expect(find.byTooltip('Agents'), findsOneWidget);
    });

    testWidgets('while sidebars are shown, rail items show tooltips and nothing floats', (WidgetTester tester) async {
      await harness.launch(tester);
      final Finder peek = find.byKey(const Key('sidebar-peek'));
      final TestGesture mouse = await mouseAt(tester, tester.getCenter(find.byKey(const Key('sidebar-plugins'))));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(peek, findsNothing, reason: 'not even for another screen');
      expect(find.byTooltip('Plugins'), findsOneWidget);
      await mouse.moveTo(tester.getCenter(find.byKey(const Key('sidebar-home'))));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(peek, findsNothing);
    });

    testWidgets('a floating sidebar of another screen opens that screen at the chosen item', (WidgetTester tester) async {
      await harness.launch(tester);
      await tester.tap(find.byKey(const Key('titlebar-toggle-sidebar')));
      await tester.pumpAndSettle();
      final Finder peek = find.byKey(const Key('sidebar-peek'));
      final TestGesture mouse = await mouseAt(tester, tester.getCenter(find.byKey(const Key('sidebar-plugins'))));
      await tester.pumpAndSettle();
      expect(find.descendant(of: peek, matching: find.byType(PluginSidebarContent)), findsOneWidget);
      expect(find.byTooltip('Plugins'), findsNothing, reason: 'the floating sidebar replaces the tooltip');

      await mouse.moveTo(tester.getCenter(find.descendant(of: peek, matching: find.byKey(const Key('plugin-category-skills')))));
      await tester.pump();
      await tester.tap(find.descendant(of: peek, matching: find.byKey(const Key('plugin-category-skills'))));
      await tester.pumpAndSettle();
      expect(peek, findsNothing);
      expect(find.byKey(const Key('skills-empty')), findsOneWidget, reason: 'opens Plugins on the chosen section');
    });
  });
}
