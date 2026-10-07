import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../../../core/design_system/design_system.dart';
import '../domain/mcp_server_readiness.dart';
import 'integrations_controller.dart';

/// Built-in and custom MCP servers: what each provides, whether it can start
/// on this Mac, and forms to add or edit a custom one.
class IntegrationsPage extends StatefulWidget {
  const IntegrationsPage({required this.controller, required this.subSidebarVisible, required this.onToggleSubSidebar, required this.onSubSidebarVisibilityChanged, super.key});

  final IntegrationsController controller;
  final bool subSidebarVisible;
  final VoidCallback onToggleSubSidebar;
  final ValueChanged<bool> onSubSidebarVisibilityChanged;

  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage> {
  double? _draggedCategoryWidth;

  /// Filters the catalog by name or description, and searches the registry.
  String _query = '';

  /// Waits for a pause in typing before asking the MCP Registry.
  Timer? _registryDebounce;

  IntegrationsController get controller => widget.controller;

  /// Re-checks when the user comes back to Weave, e.g. after installing a command.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => controller.refresh());
    // Local checks only (environment variables, commands); cheap on every visit.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        controller.refresh();
      }
    });
  }

  @override
  void dispose() {
    _registryDebounce?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _search(String query) {
    setState(() => _query = query);
    _registryDebounce?.cancel();
    _registryDebounce = Timer(WeaveMotion.searchDebounce, () => controller.searchRegistry(query));
  }

  Future<void> _edit([McpServerDefinition? server]) async {
    final McpServerDefinition? saved = await showDialog<McpServerDefinition>(
      context: context,
      builder: (BuildContext context) => _McpServerDialog(server: server, takenIds: <String>{for (final McpServerDefinition existing in controller.servers) existing.id}),
    );
    if (saved == null || !mounted) {
      return;
    }
    await controller.saveServer(saved);
    if (mounted) {
      // Show the saved plugin, with whether it is ready, in its installed view.
      controller.showPluginGroup(pluginGroupKey(saved));
      showWeaveToast(context, message: '${saved.displayName} was saved to mcp.json.', tone: WeaveToastTone.success);
    }
  }

  /// Adds a catalog or registry server to `mcp.json` as is, under an ID no
  /// other server uses; its tokens stay `${NAME}` references, so the toast
  /// says which variables still need to be set.
  Future<void> _addServer(McpServerDefinition server) async {
    final Set<String> taken = <String>{for (final McpServerDefinition existing in controller.servers) existing.id};
    String id = server.id;
    for (int suffix = 2; taken.contains(id); suffix++) {
      id = '${server.id}-$suffix';
    }
    final McpServerDefinition added = id == server.id ? server : McpServerDefinition(id: id, displayName: server.displayName, transport: server.transport, linkPatterns: server.linkPatterns, setupHint: server.setupHint, description: server.description, brand: server.brand);
    await controller.saveServer(added);
    if (!mounted) {
      return;
    }
    final String? problem = controller.readinessOf(added.id)?.problem;
    showWeaveToast(context, message: problem == null ? '${added.displayName} was added.' : '${added.displayName} was added. $problem', tone: problem == null ? WeaveToastTone.success : WeaveToastTone.info);
  }

  bool _matches(McpServerDefinition server) {
    final String query = _query.trim().toLowerCase();
    return query.isEmpty || <String?>[server.displayName, server.description, server.id].any((String? text) => text?.toLowerCase().contains(query) ?? false);
  }

  Future<void> _remove(McpServerDefinition server) async {
    final bool? confirmed = await showWeaveDialog<bool>(
      context: context,
      title: 'Remove MCP server?',
      subtitle: 'This removes the custom server from Weave. It does not delete external data or credentials.',
      accent: WeaveColors.redStrong,
      body: Text('${server.displayName} (${server.id}) will no longer be available to new workflows.', style: WeaveTypography.body),
      actions: <Widget>[
        WeaveButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop(false)),
        WeaveButton.danger(key: const Key('confirm-remove-mcp'), label: 'Remove server', onPressed: () => Navigator.of(context).pop(true)),
      ],
    );
    if (confirmed == true && mounted) {
      await controller.removeServer(server.id);
      if (mounted && !controller.servers.any((McpServerDefinition remaining) => pluginGroupKey(remaining) == controller.selectedPluginGroup)) {
        // Nothing of this plugin is left to show.
        controller.showSection(PluginSection.plugins);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool dragging = _draggedCategoryWidth != null;
    final double categoryWidth = _draggedCategoryWidth ?? (widget.subSidebarVisible ? WeaveLayout.contextualSidebarWidth : 0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AnimatedContainer(
          key: const Key('plugin-sub-sidebar'),
          width: categoryWidth,
          duration: dragging ? WeaveMotion.instant : WeaveMotion.standard,
          curve: WeaveMotion.curve,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: WeaveLayout.contextualSidebarWidth,
              maxWidth: WeaveLayout.contextualSidebarWidth,
              child: SizedBox(
                width: WeaveLayout.contextualSidebarWidth,
                child: PluginSidebarContent(controller: controller),
              ),
            ),
          ),
        ),
        WeaveSidebarResizeHandle(
          key: const Key('plugin-sub-sidebar-handle'),
          expanded: widget.subSidebarVisible,
          onToggle: widget.onToggleSubSidebar,
          onDragStart: (DragStartDetails details) => setState(() => _draggedCategoryWidth = widget.subSidebarVisible ? WeaveLayout.contextualSidebarWidth : 0),
          onDragUpdate: (DragUpdateDetails details) {
            setState(() {
              _draggedCategoryWidth = ((_draggedCategoryWidth ?? 0) + details.delta.dx).clamp(0, WeaveLayout.contextualSidebarMaxWidth).toDouble();
            });
          },
          onDragEnd: (DragEndDetails details) {
            final bool visible = (_draggedCategoryWidth ?? 0) >= WeaveLayout.contextualSidebarBreakpoint;
            setState(() => _draggedCategoryWidth = null);
            widget.onSubSidebarVisibilityChanged(visible);
          },
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(WeaveLayout.pageGutter, WeaveLayout.windowContentTopPadding, WeaveSpacing.s28, WeaveSpacing.s32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                WeavePageHeader(
                  breadcrumb: const <String>['Home', 'Plugins'],
                  title: 'Plugins',
                  subtitle: 'Extend agents with MCP servers and reusable skills.',
                  trailing: controller.section == PluginSection.skills ? null : WeaveButton.primary(key: const Key('add-mcp'), label: 'Add plugin', icon: WeaveIcons.plus, onPressed: _edit),
                ),
                const SizedBox(height: WeaveSpacing.s24),
                Expanded(child: _sectionContent()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionContent() => switch (controller.section) {
    // Installed plugins are listed in the sidebar; this view is the catalog.
    PluginSection.plugins => ListView(
      key: const Key('plugin-catalog'),
      children: <Widget>[
        WeaveTextField(key: const Key('plugin-search'), hintText: 'Search plugins and the MCP Registry', prefixIcon: WeaveIcons.search, onChanged: _search),
        ..._catalog(),
      ],
    ),
    PluginSection.installed => _serverList(
      <McpServerDefinition>[
        for (final McpServerDefinition server in controller.servers)
          if (pluginGroupKey(server) == controller.selectedPluginGroup) server,
      ],
      emptyMessage: 'This plugin has no configured servers.',
    ),
    PluginSection.skills => ListView(
      children: <Widget>[
        WeaveCard(
          key: const Key('skills-empty'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const WeaveIcon(WeaveIcons.fileCode, size: WeaveSpacing.s28, color: WeaveColors.purpleSoft),
              const SizedBox(height: WeaveSpacing.s12),
              Text('Skills', style: WeaveTypography.titleMedium),
              const SizedBox(height: WeaveSpacing.s4),
              Text('Reusable agent instructions will appear here when skill installation is available.', style: WeaveTypography.bodySmall),
            ],
          ),
        ),
      ],
    ),
  };

  /// Well-known servers by category; + adds one, an installed one shows Added.
  List<Widget> _catalog() {
    final Set<String> installed = <String>{for (final McpServerDefinition server in controller.servers) server.id};
    final List<Widget> sections = <Widget>[
      for (final McpCatalogCategory category in McpCatalogCategory.values)
        if (<McpCatalogEntry>[
              for (final McpCatalogEntry entry in mcpCatalog)
                if (entry.category == category && _matches(entry.server)) entry,
            ]
            case final List<McpCatalogEntry> entries when entries.isNotEmpty)
          Column(
            key: Key('catalog-${category.name}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: WeaveSpacing.s28),
              Text(category.label, style: WeaveTypography.titleSmall),
              const SizedBox(height: WeaveSpacing.s12),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) => _Grid(
                  width: constraints.maxWidth,
                  gap: WeaveSpacing.s12,
                  children: <Widget>[
                    for (final McpCatalogEntry entry in entries) _CatalogRow(key: ValueKey<String>('catalog-${entry.server.id}'), server: entry.server, installed: installed.contains(entry.server.id), onAdd: () => _addServer(entry.server)),
                  ],
                ),
              ),
            ],
          ),
    ];
    return <Widget>[
      if (sections.isEmpty && _query.trim().isNotEmpty) ...<Widget>[const SizedBox(height: WeaveSpacing.s28), Text('None of the suggested plugins match.', key: const Key('catalog-no-match'), style: WeaveTypography.bodySmall)] else ...sections,
      if (_query.trim().length >= 2) _registrySection(),
    ];
  }

  /// Community servers from the public MCP Registry for the search text.
  Widget _registrySection() {
    final Set<String> installedEndpoints = <String>{for (final McpServerDefinition server in controller.servers) _transportLine(server)};
    final List<McpRegistryEntry> results = controller.registryResults;
    final Widget body;
    if (controller.searchingRegistry || controller.registryQuery != _query.trim()) {
      body = Text('Searching the MCP Registry…', key: const Key('registry-searching'), style: WeaveTypography.caption);
    } else if (controller.registryError case final String error) {
      body = Text(
        error,
        key: const Key('registry-error'),
        style: WeaveTypography.caption.copyWith(color: WeaveColors.amber),
      );
    } else if (results.isEmpty) {
      body = Text('No MCP Registry server matches. Use Add plugin for any other MCP server.', key: const Key('registry-empty'), style: WeaveTypography.caption);
    } else {
      body = LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) => _Grid(
          width: constraints.maxWidth,
          gap: WeaveSpacing.s12,
          children: <Widget>[
            for (final McpRegistryEntry entry in results)
              _RegistryRow(
                key: ValueKey<String>('registry-${entry.name}'),
                entry: entry,
                installed: entry.server != null && installedEndpoints.contains(_transportLine(entry.server!)),
                onAdd: entry.server == null ? null : () => _addServer(entry.server!),
              ),
          ],
        ),
      );
    }
    return Column(
      key: const Key('catalog-registry'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: WeaveSpacing.s28),
        Row(
          children: <Widget>[
            Text('MCP Registry', style: WeaveTypography.titleSmall),
            const SizedBox(width: WeaveSpacing.s8),
            const WeaveBadge(label: 'Community', tone: WeaveTone.neutral),
          ],
        ),
        const SizedBox(height: WeaveSpacing.s4),
        Text('Published to registry.modelcontextprotocol.io by their authors and not reviewed by Weave; check a server before adding it. Only your search text is sent.', style: WeaveTypography.caption),
        const SizedBox(height: WeaveSpacing.s12),
        body,
      ],
    );
  }

  Widget _serverList(List<McpServerDefinition> servers, {String? emptyMessage}) => ListView(
    children: <Widget>[
      if (servers.isEmpty)
        WeaveCard(child: Text(emptyMessage ?? 'No plugins are configured.', style: WeaveTypography.bodySmall))
      else
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget grid = LayoutBuilder(
              builder: (BuildContext context, BoxConstraints grid) => _Grid(
                width: grid.maxWidth,
                children: <Widget>[
                  for (final McpServerDefinition server in servers)
                    _ServerCard(
                      key: ValueKey<String>('mcp-card-${server.id}'),
                      server: server,
                      readiness: controller.readinessOf(server.id),
                      custom: controller.isCustom(server.id),
                      onEdit: () => _edit(server),
                      onRemove: () => _remove(server),
                    ),
                ],
              ),
            );
            final Widget side = _Readiness(controller: controller);
            if (constraints.maxWidth >= WeaveLayout.agentsSideColumnBreakpoint) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: grid),
                  const SizedBox(width: WeaveSpacing.s24),
                  SizedBox(width: WeaveLayout.newTaskPreviewWidth, child: side),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                grid,
                const SizedBox(height: WeaveSpacing.s24),
                side,
              ],
            );
          },
        ),
    ],
  );
}

/// The Plugins screen's sidebar: Plugins, Skills and the installed plugins.
/// Used docked beside the screen and floating over any screen;
/// [onNavigate] runs after a choice, e.g. to open the Plugins screen.
class PluginSidebarContent extends StatelessWidget {
  const PluginSidebarContent({required this.controller, this.onNavigate, super.key});

  final IntegrationsController controller;
  final VoidCallback? onNavigate;

  List<_InstalledPluginGroup> get _groups {
    final Map<String, List<McpServerDefinition>> grouped = <String, List<McpServerDefinition>>{};
    for (final McpServerDefinition server in controller.servers) {
      grouped.putIfAbsent(pluginGroupKey(server), () => <McpServerDefinition>[]).add(server);
    }
    return <_InstalledPluginGroup>[
      for (final MapEntry<String, List<McpServerDefinition>> entry in grouped.entries) _InstalledPluginGroup(key: entry.key, servers: entry.value),
    ];
  }

  @override
  Widget build(BuildContext context) => WeaveCard(
    key: const Key('plugin-categories'),
    radius: 0,
    surface: WeaveSurface.sunken,
    padding: const EdgeInsets.fromLTRB(WeaveSpacing.s16, WeaveLayout.windowContentTopPadding, WeaveSpacing.s16, WeaveSpacing.s16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Customize', style: WeaveTypography.titleSmall),
        const SizedBox(height: WeaveSpacing.s16),
        _item(PluginSection.plugins, 'Plugins', WeaveIcons.squareSlash),
        const SizedBox(height: WeaveSpacing.s6),
        _item(PluginSection.skills, 'Skills', WeaveIcons.fileCode),
        const SizedBox(height: WeaveSpacing.s24),
        Text('INSTALLED', style: WeaveTypography.overline),
        const SizedBox(height: WeaveSpacing.s8),
        for (final _InstalledPluginGroup group in _groups)
          Padding(
            padding: const EdgeInsets.only(bottom: WeaveSpacing.s4),
            child: WeaveCard(
              key: ValueKey<String>('installed-plugin-${group.key}'),
              surface: controller.section == PluginSection.installed && controller.selectedPluginGroup == group.key ? WeaveSurface.selected : WeaveSurface.sunken,
              padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s12, vertical: WeaveSpacing.s8),
              onTap: () {
                controller.showPluginGroup(group.key);
                onNavigate?.call();
              },
              child: Row(
                children: <Widget>[
                  if (BrandMark.byName(group.brand) case final BrandMark brand) BrandIcon(brand, size: WeaveIconSize.compact) else const WeaveIcon(WeaveIcons.squareSlash, size: WeaveIconSize.compact),
                  const SizedBox(width: WeaveSpacing.s10),
                  Expanded(
                    child: Text(group.label, style: WeaveTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _item(PluginSection value, String label, WeaveIcons icon) => WeaveCard(
    key: Key('plugin-category-${value.name}'),
    surface: controller.section == value ? WeaveSurface.selected : WeaveSurface.sunken,
    padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s12, vertical: WeaveSpacing.s10),
    onTap: () {
      controller.showSection(value);
      onNavigate?.call();
    },
    child: Row(
      children: <Widget>[
        WeaveIcon(icon, size: WeaveIconSize.compact),
        const SizedBox(width: WeaveSpacing.s10),
        Text(label, style: WeaveTypography.bodyStrong),
      ],
    ),
  );
}

/// The installed plugin [server] belongs to: its brand, or its own ID.
String pluginGroupKey(McpServerDefinition server) {
  final String? brand = server.brand?.trim().toLowerCase();
  return brand == null || brand.isEmpty ? server.id : brand;
}

final class _InstalledPluginGroup {
  const _InstalledPluginGroup({required this.key, required this.servers});

  final String key;
  final List<McpServerDefinition> servers;

  McpServerDefinition get first => servers.first;
  String get label => first.displayName.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '');
  String? get brand => first.brand;
}

/// Server cards, two per row when there is room; cards in a row share its height.
class _Grid extends StatelessWidget {
  const _Grid({required this.width, required this.children, this.gap = WeaveSpacing.s24});

  final double width;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final int columns = math.max(1, math.min(WeaveLayout.integrationGridMaxColumns, ((width + gap) / (WeaveLayout.integrationCardMinWidth + gap)).floor()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int start = 0; start < children.length; start += columns) ...<Widget>[
          if (start > 0) SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int column = 0; column < columns; column++) ...<Widget>[
                  if (column > 0) SizedBox(width: gap),
                  Expanded(child: start + column < children.length ? children[start + column] : const SizedBox.shrink()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

(String, WeaveTone) _status(McpServerReadiness? readiness) => switch (readiness) {
  null => ('Checking…', WeaveTone.neutral),
  McpServerReadiness(isReady: true) => ('Ready', WeaveTone.success),
  _ => ('Needs setup', WeaveTone.warning),
};

String _transportLine(McpServerDefinition server) => switch (server.transport) {
  McpHttpTransport(:final String url) => url,
  McpStdioTransport(:final String command, :final List<String> arguments) => <String>[command, ...arguments].join(' '),
};

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.server, required this.readiness, required this.custom, required this.onEdit, required this.onRemove, super.key});

  final McpServerDefinition server;
  final McpServerReadiness? readiness;

  /// From `mcp.json`, so it can be edited and removed.
  final bool custom;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final BrandMark? brand = BrandMark.byName(server.brand);
    final (String status, WeaveTone tone) = _status(readiness);
    return WeaveCard(
      padding: const EdgeInsets.all(WeaveSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              WeaveCard(
                surface: WeaveSurface.sunken,
                radius: WeaveRadii.control + WeaveSpacing.s2,
                borderColor: WeaveColors.agentTile,
                padding: const EdgeInsets.all(WeaveSpacing.s10),
                child: brand != null ? BrandIcon(brand, size: WeaveSpacing.s28) : WeaveIcon(server.transport is McpHttpTransport ? WeaveIcons.atSign : WeaveIcons.terminal, size: WeaveSpacing.s28),
              ),
              const SizedBox(width: WeaveSpacing.s14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(server.displayName, style: WeaveTypography.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(server.description ?? (server.transport is McpHttpTransport ? 'HTTP server' : 'Local command'), style: WeaveTypography.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: WeaveSpacing.s16),
          Text(
            _transportLine(server),
            style: WeaveTypography.code.copyWith(color: WeaveColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (readiness?.problem case final String problem) ...<Widget>[const SizedBox(height: WeaveSpacing.s6), Text(problem, style: WeaveTypography.caption.copyWith(color: WeaveColors.amber))],
          if (server.setupHint case final String hint) ...<Widget>[const SizedBox(height: WeaveSpacing.s6), Text(hint, style: WeaveTypography.caption)],
          const Spacer(),
          const SizedBox(height: WeaveSpacing.s16),
          Row(
            children: <Widget>[
              WeaveStatusPill(key: Key('mcp-status-${server.id}'), label: status, tone: tone),
              const Spacer(),
              if (custom) ...<Widget>[
                WeaveIconButton(key: Key('remove-mcp-${server.id}'), icon: WeaveIcons.trash, tooltip: 'Remove ${server.displayName}', iconSize: WeaveIconSize.compact, onPressed: onRemove),
                const SizedBox(width: WeaveSpacing.s8),
                WeaveButton(key: Key('edit-mcp-${server.id}'), label: 'Configure', size: WeaveButtonSize.small, onPressed: onEdit),
              ] else
                const WeaveBadge(label: 'Built-in', tone: WeaveTone.neutral),
            ],
          ),
        ],
      ),
    );
  }
}

/// One catalog server: what it is, and + to add it to `mcp.json`.
class _CatalogRow extends StatelessWidget {
  const _CatalogRow({required this.server, required this.installed, required this.onAdd, super.key});

  final McpServerDefinition server;
  final bool installed;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final BrandMark? brand = BrandMark.byName(server.brand);
    return WeaveCard(
      padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16, vertical: WeaveSpacing.s12),
      child: Row(
        children: <Widget>[
          WeaveCard(
            surface: WeaveSurface.sunken,
            radius: WeaveRadii.control,
            borderColor: WeaveColors.agentTile,
            padding: const EdgeInsets.all(WeaveSpacing.s8),
            child: brand != null ? BrandIcon(brand, size: WeaveSpacing.s20) : WeaveIcon(server.transport is McpHttpTransport ? WeaveIcons.atSign : WeaveIcons.terminal, size: WeaveSpacing.s20),
          ),
          const SizedBox(width: WeaveSpacing.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(server.displayName, style: WeaveTypography.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (server.description case final String description) Text(description, style: WeaveTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: WeaveSpacing.s12),
          if (installed) WeaveBadge(key: Key('catalog-added-${server.id}'), label: 'Added', tone: WeaveTone.success) else WeaveIconButton(key: Key('catalog-add-${server.id}'), icon: WeaveIcons.plus, tooltip: 'Add ${server.displayName}', onPressed: onAdd),
        ],
      ),
    );
  }
}

/// One MCP Registry server: + adds it, unless Weave cannot run it.
class _RegistryRow extends StatelessWidget {
  const _RegistryRow({required this.entry, required this.installed, required this.onAdd, super.key});

  final McpRegistryEntry entry;
  final bool installed;

  /// Null when Weave cannot run the server.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final McpServerDefinition? server = entry.server;
    return WeaveCard(
      padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16, vertical: WeaveSpacing.s12),
      child: Row(
        children: <Widget>[
          WeaveCard(
            surface: WeaveSurface.sunken,
            radius: WeaveRadii.control,
            borderColor: WeaveColors.agentTile,
            padding: const EdgeInsets.all(WeaveSpacing.s8),
            child: WeaveIcon(server?.transport is McpStdioTransport ? WeaveIcons.terminal : WeaveIcons.atSign, size: WeaveSpacing.s20),
          ),
          const SizedBox(width: WeaveSpacing.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(entry.displayName, style: WeaveTypography.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(entry.description.isEmpty ? entry.name : entry.description, style: WeaveTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  entry.name,
                  style: WeaveTypography.caption.copyWith(color: WeaveColors.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: WeaveSpacing.s12),
          if (installed)
            WeaveBadge(key: Key('registry-added-${entry.name}'), label: 'Added', tone: WeaveTone.success)
          else if (onAdd == null)
            WeaveTooltip(
              message: entry.unsupportedReason ?? 'Weave cannot run this server.',
              child: WeaveBadge(key: Key('registry-unsupported-${entry.name}'), label: 'Not supported', tone: WeaveTone.warning),
            )
          else
            WeaveIconButton(key: Key('registry-add-${entry.name}'), icon: WeaveIcons.plus, tooltip: 'Add ${entry.displayName}', onPressed: onAdd),
        ],
      ),
    );
  }
}

/// Local readiness of every server and how Weave uses them.
class _Readiness extends StatelessWidget {
  const _Readiness({required this.controller});

  final IntegrationsController controller;

  @override
  Widget build(BuildContext context) => WeaveCard(
    key: const Key('mcp-readiness'),
    padding: const EdgeInsets.all(WeaveSpacing.s24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Server readiness', style: WeaveTypography.titleMedium),
        const SizedBox(height: WeaveSpacing.s4),
        Text('Checked on this Mac, without connecting, each time you open this screen or come back to Weave: environment variables and commands.', style: WeaveTypography.caption),
        const SizedBox(height: WeaveSpacing.s20),
        for (final McpServerDefinition server in controller.servers) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(server.id, style: WeaveTypography.label),
                    Text(controller.readinessOf(server.id)?.problem ?? (server.transport is McpHttpTransport ? 'HTTP' : 'Command found'), style: WeaveTypography.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: WeaveSpacing.s12),
              WeaveStatusPill(label: _status(controller.readinessOf(server.id)).$1, tone: _status(controller.readinessOf(server.id)).$2),
            ],
          ),
          const SizedBox(height: WeaveSpacing.s20),
        ],
        const Divider(height: WeaveLayout.divider, thickness: WeaveLayout.divider, color: WeaveColors.borderSubtle),
        const SizedBox(height: WeaveSpacing.s24),
        Text('ACCESS POLICY', style: WeaveTypography.overline),
        const SizedBox(height: WeaveSpacing.s10),
        Text(
          'Servers are off until a workflow enables them in Advanced settings, or you accept Weave\'s suggestion for a link they handle. Tokens stay in environment variables written as \${NAME}; Weave never stores them.',
          style: WeaveTypography.bodySmall,
        ),
        const SizedBox(height: WeaveSpacing.s12),
        Text('Custom servers are defined in:', style: WeaveTypography.caption),
        SelectableText(controller.configurationPath, style: WeaveTypography.code.copyWith(color: WeaveColors.textSecondary)),
      ],
    ),
  );
}

/// Adds a custom MCP server, or edits one from `mcp.json` ([server]).
class _McpServerDialog extends StatefulWidget {
  const _McpServerDialog({required this.server, required this.takenIds});

  final McpServerDefinition? server;

  /// IDs already used by other servers.
  final Set<String> takenIds;

  @override
  State<_McpServerDialog> createState() => _McpServerDialogState();
}

class _McpServerDialogState extends State<_McpServerDialog> {
  late final McpServerDefinition? _server = widget.server;
  late final TextEditingController _id = TextEditingController(text: _server?.id ?? '');
  late final TextEditingController _name = TextEditingController(text: _server?.displayName ?? '');
  late final TextEditingController _description = TextEditingController(text: _server?.description ?? '');
  late final TextEditingController _endpoint = TextEditingController(text: _server == null ? '' : _transportLine(_server));
  late final TextEditingController _values = TextEditingController(
    text: switch (_server?.transport) {
      McpHttpTransport(:final Map<String, String> headers) => _lines(headers),
      McpStdioTransport(:final Map<String, String> environment) => _lines(environment),
      null => '',
    },
  );
  late final TextEditingController _links = TextEditingController(text: _server?.linkPatterns.join('\n') ?? '');
  late bool _isHttp = _server?.transport is! McpStdioTransport;

  static String _lines(Map<String, String> values) => <String>[for (final MapEntry<String, String>(:String key, :String value) in values.entries) '$key=$value'].join('\n');

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[_id, _name, _description, _endpoint, _values, _links]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _showError(String message) => showWeaveToast(context, message: message, tone: WeaveToastTone.danger);

  void _submit() {
    try {
      final String id = _id.text.trim();
      if (_server == null && widget.takenIds.contains(id)) {
        throw FormatException('An MCP server with the ID "$id" already exists.');
      }
      final Map<String, String> values = <String, String>{};
      for (final String line in _values.text.split('\n')) {
        if (line.trim().isEmpty) {
          continue;
        }
        final int separator = line.indexOf('=');
        if (separator <= 0) {
          throw const FormatException('Each header or variable must look like NAME=value.');
        }
        values[line.substring(0, separator).trim()] = line.substring(separator + 1).trim();
      }
      final List<String> command = _isHttp ? const <String>[] : splitCommandLine(_endpoint.text);
      if (!_isHttp && command.isEmpty) {
        throw const FormatException('Enter the command that starts the server.');
      }
      Navigator.of(context).pop(
        McpServerDefinition(
          id: id,
          displayName: _name.text.trim().isEmpty ? id : _name.text.trim(),
          description: _description.text,
          brand: _server?.brand,
          setupHint: _server?.setupHint,
          transport: _isHttp ? McpHttpTransport(url: _endpoint.text, headers: values) : McpStdioTransport(command: command.first, arguments: command.skip(1).toList(), environment: values),
          linkPatterns: <String>[
            for (final String line in _links.text.split('\n'))
              if (line.trim().isNotEmpty) line.trim(),
          ],
        ),
      );
    } on FormatException catch (error) {
      _showError(error.message);
    } on ArgumentError catch (error) {
      _showError('${error.name ?? 'Value'} ${error.message}');
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: WeaveColors.surface.withValues(alpha: 0),
    elevation: 0,
    child: WeaveDialog(
      title: _server == null ? 'Add MCP server' : 'Configure ${_server.displayName}',
      subtitle: 'Connect a local or remote MCP server. Write tokens as \${NAME}; Weave reads them from the environment when a workflow starts.',
      accent: WeaveColors.cyan,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: WeaveSegmentedControl<bool>(
              key: const Key('mcp-transport'),
              semanticLabel: 'Transport',
              segments: const <WeaveSegment<bool>>[
                WeaveSegment<bool>(value: true, label: 'HTTP', icon: WeaveIcons.atSign),
                WeaveSegment<bool>(value: false, label: 'Command (stdio)', icon: WeaveIcons.terminal),
              ],
              value: _isHttp,
              onChanged: (bool isHttp) => setState(() => _isHttp = isHttp),
            ),
          ),
          const SizedBox(height: WeaveSpacing.s16),
          WeaveTextField(key: const Key('mcp-name'), controller: _name, label: 'Name', hintText: 'e.g. Linear'),
          const SizedBox(height: WeaveSpacing.s16),
          WeaveTextField(key: const Key('mcp-id'), controller: _id, label: 'ID', hintText: 'e.g. linear', enabled: _server == null, helperText: _server == null ? 'Agents see its tools as mcp__<id>__…' : 'The ID cannot change.'),
          const SizedBox(height: WeaveSpacing.s16),
          WeaveTextField(key: const Key('mcp-description'), controller: _description, label: 'Description (optional)', hintText: 'e.g. Issues and project context'),
          const SizedBox(height: WeaveSpacing.s16),
          WeaveTextField(key: const Key('mcp-endpoint'), controller: _endpoint, label: _isHttp ? 'URL' : 'Command', hintText: _isHttp ? 'https://mcp.example.com/mcp' : 'npx -y some-mcp-server'),
          const SizedBox(height: WeaveSpacing.s16),
          WeaveTextField.multiline(
            controller: _values,
            label: _isHttp ? 'Headers' : 'Environment',
            hintText: 'NAME=value, one per line',
            helperText: r'Use ${VAR} to read a token from the environment instead of saving it.',
            minLines: 1,
            maxLines: 4,
          ),
          const SizedBox(height: WeaveSpacing.s16),
          WeaveTextField.multiline(
            controller: _links,
            label: 'Link patterns',
            hintText: 'One regular expression per line',
            helperText: 'Weave offers this server when a request contains a matching link.',
            minLines: 1,
            maxLines: 3,
          ),
        ],
      ),
      actions: <Widget>[
        WeaveButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        WeaveButton.primary(key: const Key('save-mcp'), label: _server == null ? 'Add server' : 'Save', onPressed: _submit),
      ],
    ),
  );
}
