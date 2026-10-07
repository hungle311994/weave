import 'package:flutter/material.dart';
import 'package:weave_agents/weave_agents.dart';

import '../../../../core/design_system/design_system.dart';

/// Configurable workflow settings edited by the Advanced settings dialog.
final class AdvancedSettingsResult {
  AdvancedSettingsResult({required this.maxReviewCycles, required this.verificationCommands, required Set<String> mcpServerIds, required this.requirePlanApproval, required this.requireChangesApproval, required this.reviewPlan, required this.maxTokens, required this.saveAsDefaults}) : mcpServerIds = Set<String>.unmodifiable(mcpServerIds);

  final int maxReviewCycles;
  final String verificationCommands;
  final Set<String> mcpServerIds;
  final bool requirePlanApproval;
  final bool requireChangesApproval;
  final bool reviewPlan;
  final int? maxTokens;
  final bool saveAsDefaults;
}

/// Opens settings that genuinely affect workflow execution.
Future<AdvancedSettingsResult?> showAdvancedSettingsDialog({
  required BuildContext context,
  required int maxReviewCycles,
  required String verificationCommands,
  required List<McpServerDefinition> mcpServers,
  required Set<String> selectedMcpServerIds,
  required bool requirePlanApproval,
  required bool requireChangesApproval,
  required bool reviewPlan,
  required String maxTokens,
  required bool saveAsDefaults,
  String confirmLabel = 'Save settings',
}) => showDialog<AdvancedSettingsResult>(
  context: context,
  traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  requestFocus: true,
  builder: (BuildContext context) => _AdvancedSettingsDialog(
    maxReviewCycles: maxReviewCycles,
    verificationCommands: verificationCommands,
    mcpServers: mcpServers,
    selectedMcpServerIds: selectedMcpServerIds,
    requirePlanApproval: requirePlanApproval,
    requireChangesApproval: requireChangesApproval,
    reviewPlan: reviewPlan,
    maxTokens: maxTokens,
    saveAsDefaults: saveAsDefaults,
    confirmLabel: confirmLabel,
  ),
);

class _AdvancedSettingsDialog extends StatefulWidget {
  const _AdvancedSettingsDialog({required this.maxReviewCycles, required this.verificationCommands, required this.mcpServers, required this.selectedMcpServerIds, required this.requirePlanApproval, required this.requireChangesApproval, required this.reviewPlan, required this.maxTokens, required this.saveAsDefaults, required this.confirmLabel});

  final int maxReviewCycles;
  final String verificationCommands;
  final List<McpServerDefinition> mcpServers;
  final Set<String> selectedMcpServerIds;
  final bool requirePlanApproval;
  final bool requireChangesApproval;
  final bool reviewPlan;
  final String maxTokens;
  final bool saveAsDefaults;
  final String confirmLabel;

  @override
  State<_AdvancedSettingsDialog> createState() => _AdvancedSettingsDialogState();
}

class _AdvancedSettingsDialogState extends State<_AdvancedSettingsDialog> {
  late int _maxReviewCycles = widget.maxReviewCycles;
  late bool _requirePlanApproval = widget.requirePlanApproval;
  late bool _requireChangesApproval = widget.requireChangesApproval;
  late bool _reviewPlan = widget.reviewPlan;
  late bool _saveAsDefaults = widget.saveAsDefaults;
  late final Set<String> _mcpServerIds = Set<String>.of(widget.selectedMcpServerIds);
  late final TextEditingController _verification = TextEditingController(text: widget.verificationCommands);
  late final TextEditingController _maxTokens = TextEditingController(text: widget.maxTokens);
  String? _error;

  @override
  void dispose() {
    _verification.dispose();
    _maxTokens.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _maxReviewCycles = 3;
      _requirePlanApproval = false;
      _requireChangesApproval = false;
      _reviewPlan = false;
      _saveAsDefaults = false;
      _mcpServerIds.clear();
      _verification.clear();
      _maxTokens.clear();
      _error = null;
    });
  }

  void _save() {
    final String tokens = _maxTokens.text.trim();
    final int? maxTokens = tokens.isEmpty ? null : int.tryParse(tokens);
    if (tokens.isNotEmpty && (maxTokens == null || maxTokens < 1)) {
      setState(() => _error = 'The token budget must be a positive number, or empty for no limit.');
      return;
    }
    Navigator.of(context).pop(
      AdvancedSettingsResult(
        maxReviewCycles: _maxReviewCycles,
        verificationCommands: _verification.text,
        mcpServerIds: _mcpServerIds,
        requirePlanApproval: _requirePlanApproval,
        requireChangesApproval: _requireChangesApproval,
        reviewPlan: _reviewPlan,
        maxTokens: maxTokens,
        saveAsDefaults: _saveAsDefaults,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: WeaveColors.surface.withValues(alpha: 0),
    elevation: 0,
    child: WeaveDialog(
      title: 'Advanced workflow settings',
      subtitle: 'Configure checkpoints, review cycles, verification, and integrations.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          WeaveSelect<int>(
            key: const Key('max-reviews'),
            value: _maxReviewCycles,
            options: <WeavePopoverItem<int>>[for (int count = 1; count <= 6; count++) WeavePopoverItem<int>(value: count, title: '$count review ${count == 1 ? 'cycle' : 'cycles'}')],
            onChanged: (int count) => setState(() => _maxReviewCycles = count),
            label: 'Review limit',
            semanticLabel: 'Select maximum review cycles',
          ),
          const SizedBox(height: WeaveSpacing.s16),
          WeaveTextField.multiline(key: const Key('verification'), controller: _verification, label: 'Verification commands', hintText: 'One per line, e.g. fvm dart analyze', helperText: 'Run by Weave before every review, without a shell.', minLines: 2, maxLines: 4),
          const SizedBox(height: WeaveSpacing.s20),
          Text('CHECKPOINTS', style: WeaveTypography.overline),
          const SizedBox(height: WeaveSpacing.s8),
          _SettingSwitch(label: 'Approve the plan before implementation', value: _requirePlanApproval, onChanged: (bool value) => setState(() => _requirePlanApproval = value), controlKey: const Key('approve-plan')),
          _SettingSwitch(label: 'Approve changes before final review', value: _requireChangesApproval, onChanged: (bool value) => setState(() => _requireChangesApproval = value), controlKey: const Key('approve-changes')),
          _SettingSwitch(label: 'Let the reviewer check the plan', value: _reviewPlan, onChanged: (bool value) => setState(() => _reviewPlan = value), controlKey: const Key('review-plan')),
          const SizedBox(height: WeaveSpacing.s16),
          WeaveTextField(key: const Key('max-tokens'), controller: _maxTokens, label: 'Token budget', hintText: 'Empty means no limit'),
          if (widget.mcpServers.isNotEmpty) ...<Widget>[
            const SizedBox(height: WeaveSpacing.s20),
            Text('MCP SERVERS', style: WeaveTypography.overline),
            const SizedBox(height: WeaveSpacing.s8),
            for (final McpServerDefinition server in widget.mcpServers)
              Padding(
                padding: const EdgeInsets.only(bottom: WeaveSpacing.s10),
                child: Row(
                  children: <Widget>[
                    WeaveCheckbox(
                      key: Key('mcp-${server.id}'),
                      value: _mcpServerIds.contains(server.id),
                      onChanged: (bool selected) => setState(() => selected ? _mcpServerIds.add(server.id) : _mcpServerIds.remove(server.id)),
                      semanticLabel: 'Use ${server.displayName}',
                    ),
                    const SizedBox(width: WeaveSpacing.s10),
                    Expanded(child: Text(server.displayName, style: WeaveTypography.bodyStrong)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: WeaveSpacing.s12),
          Row(
            children: <Widget>[
              WeaveCheckbox(value: _saveAsDefaults, onChanged: (bool value) => setState(() => _saveAsDefaults = value), semanticLabel: 'Save as repository defaults'),
              const SizedBox(width: WeaveSpacing.s10),
              Expanded(child: Text('Save these settings as defaults for this repository', style: WeaveTypography.body)),
            ],
          ),
          if (_error case final String error) ...<Widget>[const SizedBox(height: WeaveSpacing.s12), Text(error, style: WeaveTypography.bodySmall.copyWith(color: WeaveColors.red))],
        ],
      ),
      actions: <Widget>[
        WeaveButton(label: 'Reset', onPressed: _reset),
        WeaveButton.primary(key: const Key('advanced-save'), label: widget.confirmLabel, onPressed: _save),
      ],
    ),
  );
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({required this.label, required this.value, required this.onChanged, required this.controlKey});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key controlKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: WeaveSpacing.s6),
    child: Row(
      children: <Widget>[
        Expanded(child: Text(label, style: WeaveTypography.body)),
        WeaveSwitch(key: controlKey, value: value, onChanged: onChanged, semanticLabel: label),
      ],
    ),
  );
}
