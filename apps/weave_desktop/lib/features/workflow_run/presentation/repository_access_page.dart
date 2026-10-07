import 'package:flutter/material.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../../../core/design_system/design_system.dart';

/// Asks, after planning, which repositories of a multi-repository workflow
/// the implementer may edit; the plan's proposal is preselected.
class RepositoryAccessPage extends StatefulWidget {
  const RepositoryAccessPage({required this.checkpoint, required this.onDecision, super.key});

  final WorkflowCheckpoint checkpoint;
  final void Function(CheckpointDecision decision, String? feedback, Set<String>? editableRepositories) onDecision;

  @override
  State<RepositoryAccessPage> createState() => _RepositoryAccessPageState();
}

class _RepositoryAccessPageState extends State<RepositoryAccessPage> {
  final TextEditingController _feedback = TextEditingController();
  late final Set<String> _selected = <String>{
    for (final WorkflowRepositoryChoice choice in widget.checkpoint.repositories)
      if (choice.proposed) choice.path,
  };

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(WeaveLayout.pageGutter, WeaveLayout.windowContentTopPadding, WeaveSpacing.s28, WeaveSpacing.s40),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: WeaveLayout.newTaskFormWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const WeavePageHeader(
              breadcrumb: <String>['Workspace', 'Repository access'],
              title: 'Allow edits to these repositories?',
              subtitle: 'The plan is ready. Choose which repositories the implementer may change; the others stay read-only.',
              trailing: WeaveStatusPill(label: 'Needs review', tone: WeaveTone.warning),
            ),
            const SizedBox(height: WeaveSpacing.s24),
            WeaveCard(
              padding: const EdgeInsets.all(WeaveSpacing.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final (int index, WorkflowRepositoryChoice choice) in widget.checkpoint.repositories.indexed) ...<Widget>[
                    if (index > 0) const SizedBox(height: WeaveSpacing.s12),
                    _RepositoryChoiceRow(
                      choice: choice,
                      isWorkingDirectory: index == 0,
                      selected: _selected.contains(choice.path),
                      onChanged: (bool selected) => setState(() => selected ? _selected.add(choice.path) : _selected.remove(choice.path)),
                    ),
                  ],
                  const SizedBox(height: WeaveSpacing.s20),
                  Text('Weave stops the workflow if the implementer changes a repository you did not allow, or moves HEAD or the branch of any of them.', style: WeaveTypography.caption),
                  const SizedBox(height: WeaveSpacing.s24),
                  WeaveTextField.multiline(key: const Key('checkpoint-feedback'), controller: _feedback, label: 'Note for the planner', hintText: 'Optional: what the plan should change, e.g. which repository to edit instead…', minLines: 2, maxLines: 4),
                  const SizedBox(height: WeaveSpacing.s16),
                  Wrap(
                    spacing: WeaveSpacing.s8,
                    runSpacing: WeaveSpacing.s8,
                    alignment: WrapAlignment.end,
                    children: <Widget>[
                      WeaveButton(key: const Key('checkpoint-cancel'), label: 'Cancel workflow', variant: WeaveButtonVariant.ghost, onPressed: () => widget.onDecision(CheckpointDecision.cancel, null, null)),
                      WeaveButton(key: const Key('checkpoint-revise'), label: 'Revise plan', onPressed: () => widget.onDecision(CheckpointDecision.revise, _feedback.text, null)),
                      WeaveButton.primary(
                        key: const Key('checkpoint-approve'),
                        label: _selected.isEmpty ? 'Choose a repository' : 'Allow ${_selected.length == 1 ? '1 repository' : '${_selected.length} repositories'}',
                        onPressed: _selected.isEmpty ? null : () => widget.onDecision(CheckpointDecision.approve, null, Set<String>.of(_selected)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RepositoryChoiceRow extends StatelessWidget {
  const _RepositoryChoiceRow({required this.choice, required this.isWorkingDirectory, required this.selected, required this.onChanged});

  final WorkflowRepositoryChoice choice;
  final bool isWorkingDirectory;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => WeaveCard(
    key: ValueKey<String>('repository-choice-${choice.name}'),
    surface: selected ? WeaveSurface.selected : WeaveSurface.elevated,
    padding: const EdgeInsets.all(WeaveSpacing.s16),
    onTap: () => onChanged(!selected),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: WeaveSpacing.s2),
          child: WeaveCheckbox(value: selected, onChanged: onChanged, semanticLabel: 'Allow edits to ${choice.name}'),
        ),
        const SizedBox(width: WeaveSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: WeaveSpacing.s8,
                runSpacing: WeaveSpacing.s4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(choice.name, style: WeaveTypography.bodyStrong),
                  if (isWorkingDirectory) const WeaveBadge(label: 'Working directory', tone: WeaveTone.neutral),
                  if (choice.proposed) const WeaveBadge(label: 'In the plan', tone: WeaveTone.accent),
                ],
              ),
              const SizedBox(height: WeaveSpacing.s2),
              Text(choice.path, style: WeaveTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: WeaveSpacing.s6),
              Text(
                choice.reason ?? (choice.proposed ? 'The plan changes this repository.' : 'The plan does not change this repository; it stays read-only unless you allow it.'),
                style: WeaveTypography.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
