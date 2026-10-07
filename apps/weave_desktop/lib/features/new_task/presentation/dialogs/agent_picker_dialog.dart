import 'package:flutter/material.dart';
import 'package:weave_agents/weave_agents.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../agents/presentation/agents_controller.dart';

/// Agent, optional model override, and fallback chosen for one workflow role.
final class AgentPickerResult {
  const AgentPickerResult({required this.agentId, required this.model, required this.fallbackAgentId});

  final String agentId;
  final String? model;
  final String? fallbackAgentId;
}

/// Opens a provider-neutral picker populated from the configured agent registry.
Future<AgentPickerResult?> showAgentPickerDialog({required BuildContext context, required String roleLabel, required AgentsController agents, required String? selectedAgentId, required String model, required String? fallbackAgentId}) => showDialog<AgentPickerResult>(
  context: context,
  traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  requestFocus: true,
  builder: (BuildContext context) => _AgentPickerDialog(roleLabel: roleLabel, agents: agents, selectedAgentId: selectedAgentId, model: model, fallbackAgentId: fallbackAgentId),
);

class _AgentPickerDialog extends StatefulWidget {
  const _AgentPickerDialog({required this.roleLabel, required this.agents, required this.selectedAgentId, required this.model, required this.fallbackAgentId});

  final String roleLabel;
  final AgentsController agents;
  final String? selectedAgentId;
  final String model;
  final String? fallbackAgentId;

  @override
  State<_AgentPickerDialog> createState() => _AgentPickerDialogState();
}

class _AgentPickerDialogState extends State<_AgentPickerDialog> {
  late String? _selectedAgentId = widget.selectedAgentId;
  late String? _fallbackAgentId = widget.fallbackAgentId;
  late final TextEditingController _model = TextEditingController(text: widget.model);

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedAgentId case final String agentId) {
      Navigator.of(context).pop(AgentPickerResult(agentId: agentId, model: _model.text.trim().isEmpty ? null : _model.text.trim(), fallbackAgentId: _fallbackAgentId == agentId ? null : _fallbackAgentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<WeavePopoverItem<String>> fallbackOptions = <WeavePopoverItem<String>>[
      const WeavePopoverItem<String>(value: '', title: 'None', icon: WeaveIcons.close),
      for (final AgentAdapter adapter in widget.agents.agents)
        if (adapter.id != _selectedAgentId) WeavePopoverItem<String>(value: adapter.id, title: adapter.displayName, icon: WeaveIcons.bot),
    ];
    final String fallbackValue = fallbackOptions.any((WeavePopoverItem<String> option) => option.value == (_fallbackAgentId ?? '')) ? (_fallbackAgentId ?? '') : '';

    return Dialog(
      backgroundColor: WeaveColors.surface.withValues(alpha: 0),
      elevation: 0,
      child: WeaveDialog(
        title: 'Select an agent',
        subtitle: 'Choose a connected agent and optional model for ${widget.roleLabel.toLowerCase()}.',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final AgentAdapter adapter in widget.agents.agents) ...<Widget>[
              Opacity(
                opacity: widget.agents.availabilityOf(adapter.id)?.isAvailable == false ? 0.45 : 1,
                child: WeaveCard(
                  key: Key('pick-agent-${adapter.id}'),
                  surface: _selectedAgentId == adapter.id ? WeaveSurface.selected : WeaveSurface.elevated,
                  padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16, vertical: WeaveSpacing.s10),
                  onTap: widget.agents.availabilityOf(adapter.id)?.isAvailable == false
                      ? null
                      : () => setState(() {
                          _selectedAgentId = adapter.id;
                          if (_fallbackAgentId == adapter.id) {
                            _fallbackAgentId = null;
                          }
                        }),
                  child: Row(
                    children: <Widget>[
                      const WeaveIcon(WeaveIcons.bot, size: WeaveSpacing.s24),
                      const SizedBox(width: WeaveSpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(adapter.displayName, style: WeaveTypography.bodyStrong),
                            Text(adapter.id, style: WeaveTypography.caption),
                          ],
                        ),
                      ),
                      WeaveStatusPill(label: widget.agents.availabilityOf(adapter.id)?.isAvailable == false ? 'Setup required' : 'Ready', tone: widget.agents.availabilityOf(adapter.id)?.isAvailable == false ? WeaveTone.warning : WeaveTone.success),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: WeaveSpacing.s10),
            ],
            const SizedBox(height: WeaveSpacing.s8),
            WeaveTextField(controller: _model, label: 'Model override', hintText: 'Use the agent default'),
            const SizedBox(height: WeaveSpacing.s16),
            WeaveSelect<String>(value: fallbackValue, options: fallbackOptions, onChanged: (String id) => setState(() => _fallbackAgentId = id.isEmpty ? null : id), label: 'Fallback agent', semanticLabel: 'Select fallback agent'),
          ],
        ),
        actions: <Widget>[
          WeaveButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
          WeaveButton.primary(key: const Key('agent-select'), label: 'Select agent', onPressed: _selectedAgentId == null ? null : _submit),
        ],
      ),
    );
  }
}
