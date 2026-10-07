import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:weave_workflow/weave_workflow.dart';

import '../../../core/design_system/design_system.dart';
import '../domain/diff_document.dart';

/// Review surface for the "changes" checkpoint: the implementer and its
/// self-review have finished, and the user approves the working-tree changes
/// before Weave runs verification and the final review.
class CodeReviewPage extends StatefulWidget {
  const CodeReviewPage({required this.checkpointDetails, required this.checklist, required this.settings, required this.loadDiffs, required this.onDecision, super.key});

  /// The checkpoint text: the self-review summary, then the changed files.
  final String checkpointDetails;
  final WorkflowChecklist checklist;
  final Future<WorkflowSettings?> settings;

  /// Changes of every repository of the workflow.
  final Future<List<RepositoryDiff>> Function() loadDiffs;
  final void Function(CheckpointDecision decision, String? feedback) onDecision;

  /// The self-review summary part of [checkpointDetails]; Weave appends the
  /// changed-file list after it, which this screen shows as a diff instead.
  static String summaryOf(String checkpointDetails) => checkpointDetails.split('\n\nChanged files:').first.trim();

  @override
  State<CodeReviewPage> createState() => _CodeReviewPageState();
}

class _CodeReviewPageState extends State<CodeReviewPage> {
  final TextEditingController _feedback = TextEditingController();
  late final Future<(DiffDocument, bool)> _changes = widget.loadDiffs().then(
    (List<RepositoryDiff> diffs) => (
      DiffDocument.combine(<String, DiffDocument>{for (final RepositoryDiff diff in diffs) diff.name: DiffDocument.parse(diff.patch)}),
      diffs.any((RepositoryDiff diff) => diff.isTruncated),
    ),
  );
  int _selected = 0;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const Padding(
        padding: EdgeInsets.fromLTRB(WeaveLayout.pageGutter, WeaveLayout.windowContentTopPadding, WeaveSpacing.s28, WeaveSpacing.s20),
        child: WeavePageHeader(
          breadcrumb: <String>['Workspace', 'Review changes'],
          title: 'Review changes',
          subtitle: 'Inspect the diff, test cases and self-review before Weave verifies the changes.',
          trailing: WeaveStatusPill(label: 'Needs review', tone: WeaveTone.warning),
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(WeaveLayout.pageGutter, 0, WeaveSpacing.s28, WeaveSpacing.s32),
          child: FutureBuilder<(DiffDocument, bool)>(
            future: _changes,
            builder: (BuildContext context, AsyncSnapshot<(DiffDocument, bool)> snapshot) => FutureBuilder<WorkflowSettings?>(
              future: widget.settings,
              builder: (BuildContext context, AsyncSnapshot<WorkflowSettings?> settings) => LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget files = _ChangedFiles(snapshot: snapshot, selected: _selected, onSelect: (int index) => setState(() => _selected = index));
                  final Widget diff = _DiffPanel(snapshot: snapshot, selected: _selected);
                  if (constraints.maxWidth >= WeaveLayout.codeReviewBreakpoint) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(width: WeaveLayout.codeReviewFilesWidth, child: files),
                        const SizedBox(width: WeaveSpacing.s20),
                        Expanded(child: diff),
                        const SizedBox(width: WeaveSpacing.s20),
                        SizedBox(
                          width: WeaveLayout.codeReviewChecksWidth,
                          child: _ChecksPanel(widget: widget, settings: settings.data, feedback: _feedback, fillHeight: true),
                        ),
                      ],
                    );
                  }
                  return ListView(
                    children: <Widget>[
                      SizedBox(
                        height: WeaveLayout.codeReviewStackedDiffHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            SizedBox(width: WeaveLayout.codeReviewFilesWidth, child: files),
                            const SizedBox(width: WeaveSpacing.s20),
                            Expanded(child: diff),
                          ],
                        ),
                      ),
                      const SizedBox(height: WeaveSpacing.s20),
                      _ChecksPanel(widget: widget, settings: settings.data, feedback: _feedback, fillHeight: false),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

(String, WeaveTone) _describe(DiffFileStatus status) => switch (status) {
  DiffFileStatus.modified => ('Modified', WeaveTone.info),
  DiffFileStatus.added => ('Added', WeaveTone.success),
  DiffFileStatus.deleted => ('Deleted', WeaveTone.danger),
  DiffFileStatus.renamed => ('Renamed', WeaveTone.accent),
};

class _ChangedFiles extends StatelessWidget {
  const _ChangedFiles({required this.snapshot, required this.selected, required this.onSelect});

  final AsyncSnapshot<(DiffDocument, bool)> snapshot;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final (DiffDocument, bool)? changes = snapshot.data;
    final DiffDocument? document = changes?.$1;
    return WeaveCard(
      padding: const EdgeInsets.fromLTRB(WeaveSpacing.s10, WeaveSpacing.s20, WeaveSpacing.s10, WeaveSpacing.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Changed files', style: WeaveTypography.titleSmall),
                const SizedBox(height: WeaveSpacing.s4),
                Text(
                  document == null ? 'Reading changes…' : '${document.files.length} ${document.files.length == 1 ? 'file' : 'files'} · +${document.additions} −${document.deletions}',
                  key: const Key('review-summary'),
                  style: WeaveTypography.caption,
                ),
                if (changes != null && changes.$2) ...<Widget>[
                  const SizedBox(height: WeaveSpacing.s4),
                  Text('Showing the first part of a large diff.', style: WeaveTypography.caption.copyWith(color: WeaveColors.amber)),
                ],
              ],
            ),
          ),
          const SizedBox(height: WeaveSpacing.s16),
          Expanded(
            child: ListView.separated(
              itemCount: document?.files.length ?? 0,
              separatorBuilder: (BuildContext context, int index) => const SizedBox(height: WeaveSpacing.s8),
              itemBuilder: (BuildContext context, int index) {
                final DiffFile file = document!.files[index];
                final bool isSelected = index == selected;
                final (String _, WeaveTone tone) = _describe(file.status);
                return WeaveTooltip(
                  message: file.path,
                  child: WeaveCard(
                    key: ValueKey<String>('review-file-${file.path}'),
                    surface: isSelected ? WeaveSurface.selected : WeaveSurface.field,
                    borderColor: isSelected ? null : WeaveColors.surface,
                    radius: WeaveRadii.md,
                    padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s12, vertical: WeaveSpacing.s10),
                    onTap: () => onSelect(index),
                    child: Row(
                      children: <Widget>[
                        Text(
                          file.status.letter,
                          style: WeaveTypography.caption.copyWith(color: tone.foreground, fontWeight: WeaveTypography.semiBold),
                        ),
                        const SizedBox(width: WeaveSpacing.s8),
                        Expanded(
                          child: Text(
                            file.repository == null ? path.basename(file.path) : '${file.repository} · ${path.basename(file.path)}',
                            style: WeaveTypography.caption.copyWith(color: isSelected ? WeaveColors.purpleSoft : WeaveColors.textSecondary, fontWeight: WeaveTypography.medium),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffPanel extends StatelessWidget {
  const _DiffPanel({required this.snapshot, required this.selected});

  final AsyncSnapshot<(DiffDocument, bool)> snapshot;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final DiffDocument? document = snapshot.data?.$1;
    final Widget content;
    if (snapshot.hasError) {
      content = _message('Could not read the changes: ${snapshot.error}');
    } else if (document == null) {
      content = const Center(child: CircularProgressIndicator());
    } else if (document.isEmpty) {
      content = _message('The working tree has no uncommitted changes.');
    } else {
      final DiffFile file = document.files[selected.clamp(0, document.files.length - 1)];
      final (String label, WeaveTone tone) = _describe(file.status);
      content = WeaveSplitDiff(
        key: ValueKey<String>('review-diff-${file.path}'),
        path: file.status == DiffFileStatus.renamed && file.originalPath != null ? '${file.originalPath} → ${file.path}' : file.path,
        additions: file.additions,
        deletions: file.deletions,
        statusLabel: label,
        statusTone: tone,
        originalLineCount: file.originalLineCount,
        updatedLineCount: file.updatedLineCount,
        placeholder: file.isBinary
            ? 'Binary file — no text changes to show.'
            : file.hunks.isEmpty
            ? 'No line changes in this file.'
            : null,
        rows: <WeaveDiffRow>[
          for (final DiffHunk hunk in file.hunks) ...<WeaveDiffRow>[
            WeaveDiffHunkRow(hunk.header),
            for (final SplitDiffRow row in hunk.splitRows) WeaveDiffLineRow(original: _cell(row.original, original: true), updated: _cell(row.updated, original: false)),
          ],
        ],
      );
    }
    return WeaveCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(borderRadius: WeaveRadii.panelAll, child: content),
    );
  }

  static Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(WeaveSpacing.s24),
      child: Text(text, style: WeaveTypography.body, textAlign: TextAlign.center),
    ),
  );

  static WeaveDiffCell? _cell(DiffLine? line, {required bool original}) {
    if (line == null) {
      return null;
    }
    return WeaveDiffCell(
      number: (original ? line.originalNumber : line.updatedNumber) ?? 0,
      text: line.text,
      kind: switch (line.kind) {
        DiffLineKind.context => WeaveDiffLineKind.context,
        DiffLineKind.added => WeaveDiffLineKind.added,
        DiffLineKind.removed => WeaveDiffLineKind.removed,
      },
    );
  }
}

class _ChecksPanel extends StatelessWidget {
  const _ChecksPanel({required this.widget, required this.settings, required this.feedback, required this.fillHeight});

  final CodeReviewPage widget;
  final WorkflowSettings? settings;
  final TextEditingController feedback;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final List<VerificationCommand>? commands = settings?.verificationCommands;
    final List<ChecklistItem> testCases = widget.checklist.testCases;
    final Widget details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (commands == null)
          Text('Loading verification settings…', style: WeaveTypography.caption)
        else if (commands.isEmpty)
          Text('No verification commands configured.', style: WeaveTypography.caption)
        else
          for (final VerificationCommand command in commands)
            _CheckRow(
              label: command.label,
              code: true,
              status: const WeaveStatusPill(label: 'After approval', tone: WeaveTone.neutral),
            ),
        const _CheckRow(
          label: 'Self-review',
          status: WeaveStatusPill(label: 'Complete', tone: WeaveTone.success),
        ),
        const SizedBox(height: WeaveSpacing.s12),
        const Divider(height: WeaveLayout.divider, thickness: WeaveLayout.divider, color: WeaveColors.borderSubtle),
        const SizedBox(height: WeaveSpacing.s24),
        Text('TEST CASES', style: WeaveTypography.overline),
        const SizedBox(height: WeaveSpacing.s12),
        if (testCases.isEmpty) Text('The plan lists no test cases.', style: WeaveTypography.caption),
        for (final ChecklistItem item in testCases)
          Padding(
            padding: const EdgeInsets.only(bottom: WeaveSpacing.s12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _TestCaseIcon(status: item.status),
                const SizedBox(width: WeaveSpacing.s8),
                Expanded(child: Text(item.title, style: WeaveTypography.bodySmall)),
              ],
            ),
          ),
        const SizedBox(height: WeaveSpacing.s12),
        Text('AGENT SUMMARY', style: WeaveTypography.overline),
        const SizedBox(height: WeaveSpacing.s8),
        SelectableText(CodeReviewPage.summaryOf(widget.checkpointDetails), key: const Key('review-agent-summary'), style: WeaveTypography.bodySmall),
      ],
    );
    final Widget actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WeaveTextField.multiline(key: const Key('checkpoint-feedback'), controller: feedback, hintText: 'What should change? (for Request changes)', minLines: 2, maxLines: 4),
        const SizedBox(height: WeaveSpacing.s12),
        Row(
          children: <Widget>[
            Expanded(
              child: WeaveButton(key: const Key('checkpoint-revise'), label: 'Request changes', onPressed: () => widget.onDecision(CheckpointDecision.revise, feedback.text)),
            ),
            const SizedBox(width: WeaveSpacing.s12),
            Expanded(
              child: WeaveButton.primary(key: const Key('checkpoint-approve'), label: 'Approve', onPressed: () => widget.onDecision(CheckpointDecision.approve, null)),
            ),
          ],
        ),
        const SizedBox(height: WeaveSpacing.s8),
        WeaveButton(key: const Key('checkpoint-cancel'), label: 'Cancel workflow', variant: WeaveButtonVariant.ghost, expand: true, onPressed: () => widget.onDecision(CheckpointDecision.cancel, null)),
      ],
    );
    return WeaveCard(
      padding: const EdgeInsets.all(WeaveSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          Text('Verification', style: WeaveTypography.titleMedium),
          const SizedBox(height: WeaveSpacing.s4),
          Text('Weave runs these after you approve; then the reviewer checks the result.', style: WeaveTypography.caption),
          const SizedBox(height: WeaveSpacing.s20),
          if (fillHeight) Expanded(child: SingleChildScrollView(child: details)) else details,
          const SizedBox(height: WeaveSpacing.s20),
          actions,
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.status, this.code = false});

  final String label;
  final Widget status;

  /// Verification commands are shown as code.
  final bool code;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WeaveSpacing.s12),
    child: Row(
      children: <Widget>[
        Expanded(
          child: WeaveTooltip(
            message: label,
            child: Text(
              label,
              style: code ? WeaveTypography.code.copyWith(color: WeaveColors.cyan) : WeaveTypography.bodySmall.copyWith(color: WeaveColors.textPrimary, fontWeight: WeaveTypography.medium),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: WeaveSpacing.s8),
        status,
      ],
    ),
  );
}

class _TestCaseIcon extends StatelessWidget {
  const _TestCaseIcon({required this.status});

  final ChecklistItemStatus status;

  @override
  Widget build(BuildContext context) {
    final (WeaveIcons icon, Color color, String label) = switch (status) {
      ChecklistItemStatus.done || ChecklistItemStatus.verified => (WeaveIcons.check, WeaveColors.green, 'Done'),
      ChecklistItemStatus.notDone || ChecklistItemStatus.needsChanges => (WeaveIcons.close, WeaveColors.red, 'Not done'),
      ChecklistItemStatus.pending || ChecklistItemStatus.inProgress => (WeaveIcons.circle, WeaveColors.textTertiary, 'Pending'),
    };
    return WeaveIcon(icon, size: WeaveIconSize.compact, color: color, semanticLabel: label);
  }
}
