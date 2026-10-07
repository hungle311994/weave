import 'package:flutter/material.dart';
import 'package:weave_agents/weave_agents.dart';

import '../../../../core/design_system/design_system.dart';
import 'add_agent_dialog.dart';

/// Offers well-known agents to add with one click, marking those found on
/// this Mac; "Custom command" opens the full form for any other CLI. Returns
/// the definition to save to `agents.json`, or `null` when cancelled.
Future<AgentDefinition?> showAgentGalleryDialog(BuildContext context, {required Set<String> existingIds, required Future<bool> Function(String executable) isInstalled}) => showDialog<AgentDefinition>(
  context: context,
  builder: (BuildContext context) => _AgentGalleryDialog(existingIds: existingIds, isInstalled: isInstalled),
);

class _AgentGalleryDialog extends StatefulWidget {
  const _AgentGalleryDialog({required this.existingIds, required this.isInstalled});

  final Set<String> existingIds;
  final Future<bool> Function(String executable) isInstalled;

  @override
  State<_AgentGalleryDialog> createState() => _AgentGalleryDialogState();
}

class _AgentGalleryDialogState extends State<_AgentGalleryDialog> {
  /// Whether each catalog agent's command is on this Mac; absent while checking.
  final Map<String, bool> _installed = <String, bool>{};

  @override
  void initState() {
    super.initState();
    for (final AgentCatalogEntry entry in agentCatalog) {
      widget.isInstalled(entry.definition.executable).then((bool installed) {
        if (mounted) {
          setState(() => _installed[entry.definition.id] = installed);
        }
      });
    }
  }

  Future<void> _custom() async {
    final AgentDefinition? definition = await showAddAgentDialog(context, existingIds: widget.existingIds);
    if (definition != null && mounted) {
      Navigator.of(context).pop(definition);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: WeaveColors.surface.withValues(alpha: 0),
    elevation: 0,
    child: WeaveDialog(
      title: 'Add agent',
      subtitle: 'Pick a command-line coding agent. It signs in with its own account; Weave stores no credentials.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final AgentCatalogEntry entry in agentCatalog) ...<Widget>[
            _GalleryRow(
              key: ValueKey<String>('gallery-${entry.definition.id}'),
              entry: entry,
              installed: _installed[entry.definition.id],
              added: widget.existingIds.contains(entry.definition.id),
              onAdd: () => Navigator.of(context).pop(entry.definition),
            ),
            const SizedBox(height: WeaveSpacing.s12),
          ],
          const SizedBox(height: WeaveSpacing.s4),
          const Divider(height: WeaveLayout.divider, thickness: WeaveLayout.divider, color: WeaveColors.borderSubtle),
          const SizedBox(height: WeaveSpacing.s16),
          Row(
            children: <Widget>[
              Expanded(child: Text('Another agent? Describe how to run its command.', style: WeaveTypography.caption)),
              const SizedBox(width: WeaveSpacing.s12),
              WeaveButton(key: const Key('gallery-custom'), label: 'Custom command', icon: WeaveIcons.terminal, size: WeaveButtonSize.small, onPressed: _custom),
            ],
          ),
        ],
      ),
      actions: <Widget>[WeaveButton(label: 'Close', onPressed: () => Navigator.of(context).pop())],
    ),
  );
}

class _GalleryRow extends StatelessWidget {
  const _GalleryRow({required this.entry, required this.installed, required this.added, required this.onAdd, super.key});

  final AgentCatalogEntry entry;

  /// `null` while checking this Mac.
  final bool? installed;
  final bool added;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final AgentDefinition agent = entry.definition;
    final BrandMark? brand = BrandMark.byName(agent.brand);
    final (String status, WeaveTone tone) = switch (installed) {
      null => ('Checking…', WeaveTone.neutral),
      true => ('Installed', WeaveTone.success),
      false => ('Not installed', WeaveTone.neutral),
    };
    return WeaveCard(
      padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16, vertical: WeaveSpacing.s12),
      child: Row(
        children: <Widget>[
          WeaveCard(
            surface: WeaveSurface.sunken,
            radius: WeaveRadii.control,
            borderColor: WeaveColors.agentTile,
            padding: const EdgeInsets.all(WeaveSpacing.s8),
            child: brand == null ? const WeaveIcon(WeaveIcons.bot, size: WeaveSpacing.s20) : BrandIcon(brand, size: WeaveSpacing.s20),
          ),
          const SizedBox(width: WeaveSpacing.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(agent.displayName, style: WeaveTypography.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(entry.summary, style: WeaveTypography.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: WeaveSpacing.s12),
          WeaveStatusPill(key: Key('gallery-status-${agent.id}'), label: status, tone: tone),
          const SizedBox(width: WeaveSpacing.s12),
          if (added) WeaveBadge(key: Key('gallery-added-${agent.id}'), label: 'Added', tone: WeaveTone.success) else WeaveButton.primary(key: Key('gallery-add-${agent.id}'), label: 'Add', size: WeaveButtonSize.small, onPressed: onAdd),
        ],
      ),
    );
  }
}
