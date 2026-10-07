import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/design_system/design_system.dart';
import '../app_controller.dart';

/// Fixed icon rail for Home, Agents, Plugins, and the local profile.
class Sidebar extends StatelessWidget {
  const Sidebar({required this.app, this.onHoverDestination, super.key});

  final AppController app;

  /// Called with a destination that has a contextual sidebar when the
  /// pointer enters its item, and with `null` when it leaves.
  final ValueChanged<AppDestination?>? onHoverDestination;

  Widget _hoverable(AppDestination destination, Widget item) => MouseRegion(
    onEnter: (PointerEnterEvent _) => onHoverDestination?.call(destination),
    onExit: (PointerExitEvent _) => onHoverDestination?.call(null),
    child: item,
  );

  Future<void> _openAccountMenu(BuildContext context) async {
    final RenderBox anchorBox = context.findRenderObject()! as RenderBox;
    final Offset origin = anchorBox.localToGlobal(Offset.zero);
    final WeaveAccountAction? action = await showWeaveAccountMenu(context: context, anchor: origin & anchorBox.size, name: app.userName);
    if (action == WeaveAccountAction.settings) {
      app.select(const SettingsDestination());
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppDestination selection = app.destination;
    return Material(
      color: WeaveColors.sidebar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            const SizedBox(height: WeaveLayout.windowContentTopPadding),
            const WeaveLogoMark(),
            const SizedBox(height: WeaveSpacing.s32),
            _hoverable(
              const NewTaskDestination(),
              WeaveNavigationItem(
                key: const Key('sidebar-home'),
                // While sidebars are hidden, hovering floats this one instead.
                tooltip: app.sidebarExpanded,
                label: 'Home',
                icon: WeaveIcons.home,
                onPressed: () => app.select(const NewTaskDestination()),
                expanded: false,
                selected: selection is NewTaskDestination,
              ),
            ),
            const SizedBox(height: WeaveSpacing.s8),
            WeaveNavigationItem(
              key: const Key('sidebar-agents'),
              label: 'Agents',
              icon: WeaveIcons.bot,
              onPressed: () => app.select(const AgentsDestination()),
              expanded: false,
              selected: selection is AgentsDestination,
            ),
            const SizedBox(height: WeaveSpacing.s8),
            _hoverable(
              const PluginsDestination(),
              WeaveNavigationItem(
                key: const Key('sidebar-plugins'),
                // While sidebars are hidden, hovering floats this one instead.
                tooltip: app.sidebarExpanded,
                label: 'Plugins',
                icon: WeaveIcons.squareSlash,
                onPressed: () => app.select(const PluginsDestination()),
                expanded: false,
                selected: selection is PluginsDestination,
              ),
            ),
            const Spacer(),
            Builder(
              builder: (BuildContext accountContext) => WeaveAccountButton(
                key: const Key('sidebar-account'),
                name: app.userName,
                expanded: false,
                onPressed: () => _openAccountMenu(accountContext),
              ),
            ),
            const SizedBox(height: WeaveSpacing.s12),
          ],
        ),
      ),
    );
  }
}
