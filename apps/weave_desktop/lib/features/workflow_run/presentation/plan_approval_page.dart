import 'package:flutter/material.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../../../core/design_system/design_system.dart';

/// Review surface shown before an approved plan may edit the repository.
class PlanApprovalPage extends StatefulWidget {
  const PlanApprovalPage({required this.request, required this.plan, required this.checklist, required this.settings, required this.onDecision, super.key});

  final String request;
  final String plan;
  final WorkflowChecklist checklist;
  final Future<WorkflowSettings?> settings;
  final void Function(CheckpointDecision decision, String? feedback) onDecision;

  @override
  State<PlanApprovalPage> createState() => _PlanApprovalPageState();
}

class _PlanApprovalPageState extends State<PlanApprovalPage> {
  final TextEditingController _feedback = TextEditingController();

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(WeaveLayout.pageGutter, WeaveLayout.windowContentTopPadding, WeaveSpacing.s28, WeaveSpacing.s20),
        child: WeavePageHeader(
          breadcrumb: const <String>['Workspace', 'Review the implementation plan'],
          title: 'Review the implementation plan',
          subtitle: 'Confirm the scope before any code changes are made.',
          trailing: const WeaveStatusPill(label: 'Needs review', tone: WeaveTone.warning),
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(WeaveLayout.pageGutter, 0, WeaveSpacing.s28, WeaveSpacing.s32),
          child: FutureBuilder<WorkflowSettings?>(
            future: widget.settings,
            builder: (BuildContext context, AsyncSnapshot<WorkflowSettings?> snapshot) => LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final WorkflowSettings? settings = snapshot.data;
                if (constraints.maxWidth >= WeaveLayout.newTaskPreviewBreakpoint) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: _PlanPanel(request: widget.request, plan: widget.plan, checklist: widget.checklist, settings: settings, fillHeight: true),
                      ),
                      const SizedBox(width: WeaveSpacing.s24),
                      SizedBox(
                        width: WeaveLayout.newTaskPreviewWidth,
                        child: _ReviewPanel(checklist: widget.checklist, settings: settings, feedback: _feedback, onDecision: widget.onDecision, fillHeight: true),
                      ),
                    ],
                  );
                }
                return ListView(
                  children: <Widget>[
                    _PlanPanel(request: widget.request, plan: widget.plan, checklist: widget.checklist, settings: settings, fillHeight: false),
                    const SizedBox(height: WeaveSpacing.s16),
                    _ReviewPanel(checklist: widget.checklist, settings: settings, feedback: _feedback, onDecision: widget.onDecision, fillHeight: false),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ],
  );
}

class _PlanPanel extends StatelessWidget {
  const _PlanPanel({required this.request, required this.plan, required this.checklist, required this.settings, required this.fillHeight});

  final String request;
  final String plan;
  final WorkflowChecklist checklist;
  final WorkflowSettings? settings;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final Widget content = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < checklist.items.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: WeaveSpacing.s12),
            WeaveCard(
              surface: WeaveSurface.sunken,
              padding: const EdgeInsets.all(WeaveSpacing.s16),
              radius: WeaveRadii.card,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  WeaveCountBubble.plan(count: index + 1),
                  const SizedBox(width: WeaveSpacing.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(checklist.items[index].title, style: WeaveTypography.titleSmall),
                        const SizedBox(height: WeaveSpacing.s4),
                        Text(checklist.items[index].kind == ChecklistItemKind.task ? 'Implementation task' : 'Test case', style: WeaveTypography.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (checklist.isEmpty) SelectableText(plan.trimRight(), style: WeaveTypography.body),
          const SizedBox(height: WeaveSpacing.s24),
          Text('VERIFICATION COMMANDS', style: WeaveTypography.overline),
          const SizedBox(height: WeaveSpacing.s8),
          if (settings == null)
            Text('Loading verification settings…', style: WeaveTypography.caption)
          else if (settings!.verificationCommands.isEmpty)
            Text('No verification commands configured.', style: WeaveTypography.caption)
          else
            for (int index = 0; index < settings!.verificationCommands.length; index++) ...<Widget>[
              if (index > 0) const SizedBox(height: WeaveSpacing.s8),
              WeaveCard(
                surface: WeaveSurface.sunken,
                padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s12, vertical: WeaveSpacing.s8),
                child: Text(settings!.verificationCommands[index].label, style: WeaveTypography.code.copyWith(color: WeaveColors.cyan)),
              ),
            ],
        ],
      ),
    );
    return WeaveCard(
      padding: const EdgeInsets.all(WeaveSpacing.s28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          Text('Implementation plan', style: WeaveTypography.titleLarge),
          const SizedBox(height: WeaveSpacing.s4),
          Text(request, style: WeaveTypography.body),
          const SizedBox(height: WeaveSpacing.s32),
          if (fillHeight) Expanded(child: content) else content,
        ],
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({required this.checklist, required this.settings, required this.feedback, required this.onDecision, required this.fillHeight});

  final WorkflowChecklist checklist;
  final WorkflowSettings? settings;
  final TextEditingController feedback;
  final void Function(CheckpointDecision decision, String? feedback) onDecision;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final List<Widget> facts = <Widget>[
      const _ReviewFact(title: 'Planner was read-only', subtitle: 'Repository edits were not allowed during planning.'),
      _ReviewFact(title: '${checklist.tasks.length} implementation ${checklist.tasks.length == 1 ? 'task' : 'tasks'}', subtitle: 'Review the requested scope before approval.'),
      _ReviewFact(title: '${checklist.testCases.length} ${checklist.testCases.length == 1 ? 'test case' : 'test cases'}', subtitle: 'These cases will be tracked through review.'),
      _ReviewFact(
        title: '${settings?.verificationCommands.length ?? 0} verification ${settings?.verificationCommands.length == 1 ? 'command' : 'commands'}',
        subtitle: settings == null ? 'Loading workflow settings…' : 'Weave runs these commands before final review.',
      ),
    ];
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int index = 0; index < facts.length; index++) ...<Widget>[if (index > 0) const SizedBox(height: WeaveSpacing.s20), facts[index]],
        if (fillHeight) const Spacer() else const SizedBox(height: WeaveSpacing.s32),
        WeaveTextField.multiline(key: const Key('checkpoint-feedback'), controller: feedback, label: 'REVIEW NOTE', hintText: 'Optional feedback for the planning agent…', minLines: 3, maxLines: 5),
        const SizedBox(height: WeaveSpacing.s16),
        Wrap(
          spacing: WeaveSpacing.s8,
          runSpacing: WeaveSpacing.s8,
          alignment: WrapAlignment.end,
          children: <Widget>[
            WeaveButton(label: 'Cancel workflow', variant: WeaveButtonVariant.ghost, onPressed: () => onDecision(CheckpointDecision.cancel, null)),
            WeaveButton(key: const Key('checkpoint-revise'), label: 'Request revision', onPressed: () => onDecision(CheckpointDecision.revise, feedback.text)),
            WeaveButton.primary(key: const Key('checkpoint-approve'), label: 'Approve plan', onPressed: () => onDecision(CheckpointDecision.approve, null)),
          ],
        ),
      ],
    );
    return WeaveCard(
      padding: const EdgeInsets.all(WeaveSpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          Text('Review checklist', style: WeaveTypography.titleMedium),
          const SizedBox(height: WeaveSpacing.s24),
          if (fillHeight) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

class _ReviewFact extends StatelessWidget {
  const _ReviewFact({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const WeaveIcon(WeaveIcons.check, size: WeaveIconSize.control, color: WeaveColors.green),
      const SizedBox(width: WeaveSpacing.s16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: WeaveTypography.bodyStrong),
            const SizedBox(height: WeaveSpacing.s2),
            Text(subtitle, style: WeaveTypography.caption),
          ],
        ),
      ),
    ],
  );
}
