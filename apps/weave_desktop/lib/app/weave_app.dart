import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_system/design_system.dart';
import '../features/agents/presentation/agents_page.dart';
import '../features/integrations/presentation/integrations_page.dart';
import '../features/new_task/presentation/new_task_page.dart';
import '../features/onboarding/presentation/onboarding_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/workflow_run/presentation/workflow_run_page.dart';
import 'app_controller.dart';
import 'navigation/sidebar.dart';
import 'weave_app_scope.dart';

/// Root widget; [createScope] is injectable for tests.
class WeaveApp extends StatefulWidget {
  const WeaveApp({required this.createScope, super.key});

  final Future<WeaveAppScope> Function() createScope;

  @override
  State<WeaveApp> createState() => _WeaveAppState();
}

class _WeaveAppState extends State<WeaveApp> {
  late final Future<WeaveAppScope> _scope = () async {
    final WeaveAppScope scope = await widget.createScope();
    await scope.initialize();
    return scope;
  }();

  @override
  void dispose() {
    _scope.then((WeaveAppScope scope) => scope.dispose(), onError: (Object _) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weave',
      debugShowCheckedModeBanner: false,
      theme: WeaveTheme.dark(),
      themeMode: ThemeMode.dark,
      scrollBehavior: const WeaveScrollBehavior(),
      home: FutureBuilder<WeaveAppScope>(
        future: _scope,
        builder: (BuildContext context, AsyncSnapshot<WeaveAppScope> snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: SelectableText('Weave could not start:\n\n${snapshot.error}', textAlign: TextAlign.center),
                ),
              ),
            );
          }
          final WeaveAppScope? scope = snapshot.data;
          if (scope == null) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return ListenableBuilder(
            listenable: scope.onboarding,
            builder: (BuildContext context, Widget? child) => scope.onboarding.completed ? WeaveHome(scope: scope) : OnboardingPage(controller: scope.onboarding, agents: scope.agents),
          );
        },
      ),
    );
  }
}

/// Sidebar plus the selected view.
///
/// A screen's contextual sidebar is docked beside it while sidebars are
/// shown, and rail items then show tooltips. While sidebars are hidden,
/// hovering a rail item that has one floats it over the page until the
/// pointer leaves both the item and the panel.
class WeaveHome extends StatefulWidget {
  const WeaveHome({required this.scope, super.key});

  final WeaveAppScope scope;

  @override
  State<WeaveHome> createState() => _WeaveHomeState();
}

class _WeaveHomeState extends State<WeaveHome> {
  WeaveAppScope get scope => widget.scope;

  /// The destination whose sidebar floats over the page, if any.
  AppDestination? _peek;
  Timer? _hidePeek;

  @override
  void dispose() {
    _hidePeek?.cancel();
    super.dispose();
  }

  /// Pages with a contextual sidebar that the title-bar toggle shows or hides.
  bool get _hasContextualSidebar => switch (scope.app.destination) {
    NewTaskDestination() || PluginsDestination() => true,
    _ => false,
  };

  /// Sidebars float only while they are hidden; shown, they are docked and
  /// the rail shows tooltips instead.
  bool get _canFloat => !scope.app.sidebarExpanded;

  void _hoverRailItem(AppDestination? destination) {
    if (destination == null) {
      _scheduleHidePeek();
      return;
    }
    _hidePeek?.cancel();
    if (_canFloat) {
      setState(() => _peek = destination);
    }
  }

  /// Leaves time to move the pointer from the rail item into the panel.
  void _scheduleHidePeek() {
    _hidePeek?.cancel();
    _hidePeek = Timer(WeaveMotion.peekHideDelay, () {
      if (mounted) {
        setState(() => _peek = null);
      }
    });
  }

  void _closePeek() {
    _hidePeek?.cancel();
    setState(() => _peek = null);
  }

  Widget? _peekContent(AppDestination destination) => switch (destination) {
    NewTaskDestination() => HomeSidebarContent(
      workflow: scope.workflow,
      onNewTask: () {
        _closePeek();
        scope.app.select(const NewTaskDestination());
      },
      onOpenWorkflow: (String taskId) {
        _closePeek();
        scope.app.select(WorkflowDestination(taskId));
      },
    ),
    PluginsDestination() => PluginSidebarContent(
      controller: scope.integrations,
      onNavigate: () {
        _closePeek();
        scope.app.select(const PluginsDestination());
      },
    ),
    _ => null,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WeaveColors.canvas,
    body: ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.app, scope.agents, scope.integrations, scope.workflow]),
      builder: (BuildContext context, Widget? _) => CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => unawaited(scope.app.toggleSidebar()),
          const SingleActivator(LogicalKeyboardKey.comma, meta: true): () => scope.app.select(const SettingsDestination()),
          const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true): scope.app.goBack,
          const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true): scope.app.goForward,
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: <Widget>[
              WeaveWindowTitleBar(
                key: const Key('window-title-bar'),
                trafficLightCenter: scope.trafficLightCenter,
                leading: _TitleBarControls(app: scope.app, canToggleSidebar: _hasContextualSidebar),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      key: const Key('sidebar-shell'),
                      width: WeaveLayout.sidebarCollapsed,
                      child: Sidebar(app: scope.app, onHoverDestination: _hoverRailItem),
                    ),
                    Expanded(
                      // The glow stays fixed behind the page while it scrolls.
                      child: Stack(
                        children: <Widget>[
                          Positioned(
                            left: WeaveLayout.ambientGlowOffset.dx,
                            top: WeaveLayout.ambientGlowOffset.dy,
                            child: const WeaveAmbientGlow(key: Key('ambient-glow')),
                          ),
                          Positioned.fill(
                            // Cross-fades between pages instead of swapping them in one frame.
                            child: AnimatedSwitcher(
                              duration: WeaveMotion.standard,
                              switchInCurve: WeaveMotion.curve,
                              switchOutCurve: WeaveMotion.curve,
                              // Every page fills the pane from the top; the default
                              // centres a page whose content is shorter than the window.
                              layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
                                fit: StackFit.expand,
                                children: <Widget>[...previous, ?current],
                              ),
                              child: switch (scope.app.destination) {
                                NewTaskDestination() => NewTaskPage(
                                  controller: scope.newTask,
                                  workflow: scope.workflow,
                                  agents: scope.agents,
                                  integrations: scope.integrations,
                                  repositoryPicker: scope.repositoryPicker,
                                  onOpenAgents: () => scope.app.select(const AgentsDestination()),
                                  onOpenWorkflow: (String taskId) => scope.app.select(WorkflowDestination(taskId)),
                                  subSidebarVisible: scope.app.sidebarExpanded,
                                  onToggleSubSidebar: () => unawaited(scope.app.toggleSidebar()),
                                  onSubSidebarVisibilityChanged: (bool visible) => unawaited(scope.app.setSidebarExpanded(visible)),
                                ),
                                AgentsDestination() => AgentsPage(controller: scope.agents),
                                PluginsDestination() => IntegrationsPage(
                                  controller: scope.integrations,
                                  subSidebarVisible: scope.app.sidebarExpanded,
                                  onToggleSubSidebar: () => unawaited(scope.app.toggleSidebar()),
                                  onSubSidebarVisibilityChanged: (bool visible) => unawaited(scope.app.setSidebarExpanded(visible)),
                                ),
                                SettingsDestination() => const SettingsPage(),
                                WorkflowDestination(:final String taskId) => WorkflowRunPage(key: ValueKey<String>(taskId), controller: scope.workflow, taskId: taskId),
                              },
                            ),
                          ),
                          Positioned(
                            left: WeaveSpacing.s8,
                            top: WeaveSpacing.s8,
                            bottom: WeaveSpacing.s8,
                            width: WeaveLayout.contextualSidebarWidth,
                            child: AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : WeaveMotion.peekIn,
                              reverseDuration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : WeaveMotion.peekOut,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              // Fades in while sliding a little from the rail, like a drawer.
                              transitionBuilder: (Widget child, Animation<double> animation) => FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(begin: const Offset(-WeaveMotion.peekSlide, 0), end: Offset.zero).animate(animation),
                                  child: child,
                                ),
                              ),
                              child: switch (_peek) {
                                final AppDestination peek when _canFloat && _peekContent(peek) != null => MouseRegion(
                                  key: ValueKey<Type>(peek.runtimeType),
                                  onEnter: (PointerEnterEvent _) => _hidePeek?.cancel(),
                                  onExit: (PointerExitEvent _) => _scheduleHidePeek(),
                                  child: WeaveFloatingPanel(key: const Key('sidebar-peek'), child: _peekContent(peek)!),
                                ),
                                _ => const SizedBox.shrink(key: Key('sidebar-peek-none')),
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Back, forward and the contextual-sidebar toggle, beside the traffic lights.
class _TitleBarControls extends StatelessWidget {
  const _TitleBarControls({required this.app, required this.canToggleSidebar});

  final AppController app;
  final bool canToggleSidebar;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      WeaveIconButton(key: const Key('titlebar-back'), icon: WeaveIcons.arrowLeft, tooltip: 'Back (⌘[)', size: WeaveLayout.windowControlSize, iconSize: WeaveIconSize.control, onPressed: app.canGoBack ? app.goBack : null),
      const SizedBox(width: WeaveSpacing.s4),
      WeaveIconButton(key: const Key('titlebar-forward'), icon: WeaveIcons.arrowRight, tooltip: 'Forward (⌘])', size: WeaveLayout.windowControlSize, iconSize: WeaveIconSize.control, onPressed: app.canGoForward ? app.goForward : null),
      // Only screens with a contextual sidebar offer the toggle.
      if (canToggleSidebar) ...<Widget>[
        const SizedBox(width: WeaveSpacing.s4),
        WeaveIconButton(
          key: const Key('titlebar-toggle-sidebar'),
          icon: app.sidebarExpanded ? WeaveIcons.panelClose : WeaveIcons.panelOpen,
          tooltip: app.sidebarExpanded ? 'Hide sidebar (⌘B)' : 'Show sidebar (⌘B)',
          size: WeaveLayout.windowControlSize,
          iconSize: WeaveIconSize.control,
          onPressed: () => unawaited(app.toggleSidebar()),
        ),
      ],
    ],
  );
}
