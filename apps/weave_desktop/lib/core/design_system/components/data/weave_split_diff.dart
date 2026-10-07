import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';
import '../feedback/weave_status_pill.dart';
import '../feedback/weave_tone.dart';
import '../overlays/weave_tooltip.dart';

enum WeaveDiffLineKind { context, added, removed }

/// One side of a [WeaveDiffLineRow].
final class WeaveDiffCell {
  const WeaveDiffCell({required this.number, required this.text, required this.kind});

  final int number;
  final String text;
  final WeaveDiffLineKind kind;
}

/// A row of a [WeaveSplitDiff].
sealed class WeaveDiffRow {
  const WeaveDiffRow();
}

/// A `@@ … @@` hunk header spanning both columns.
final class WeaveDiffHunkRow extends WeaveDiffRow {
  const WeaveDiffHunkRow(this.header);

  final String header;
}

/// A line pair; a null side has no line there (e.g. the original of an addition).
final class WeaveDiffLineRow extends WeaveDiffRow {
  const WeaveDiffLineRow({this.original, this.updated});

  final WeaveDiffCell? original;
  final WeaveDiffCell? updated;
}

/// Side-by-side diff of one file, as in the Code Review screen: a file header
/// with counts and status, "Original" and "Updated" columns, and aligned rows.
class WeaveSplitDiff extends StatelessWidget {
  const WeaveSplitDiff({required this.path, required this.additions, required this.deletions, required this.statusLabel, required this.statusTone, required this.rows, required this.originalLineCount, required this.updatedLineCount, this.placeholder, super.key});

  final String path;
  final int additions;
  final int deletions;

  /// E.g. "Modified" in [WeaveTone.info].
  final String statusLabel;
  final WeaveTone statusTone;
  final List<WeaveDiffRow> rows;
  final int originalLineCount;
  final int updatedLineCount;

  /// Shown instead of the rows, e.g. for a binary file.
  final String? placeholder;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _FileHeader(path: path, additions: additions, deletions: deletions, statusLabel: statusLabel, statusTone: statusTone),
      SizedBox(
        height: WeaveLayout.diffColumnHeaderHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _ColumnHeader(title: 'Original', detail: 'Before · ${_lines(originalLineCount)}', background: WeaveColors.diffOriginalHeader, color: WeaveColors.red),
            ),
            const _ColumnDivider(),
            Expanded(
              child: _ColumnHeader(title: 'Updated', detail: 'After · ${_lines(updatedLineCount)}', background: WeaveColors.diffUpdatedHeader, color: WeaveColors.greenBright),
            ),
          ],
        ),
      ),
      const Divider(height: WeaveLayout.divider, thickness: WeaveLayout.divider, color: WeaveColors.borderSubtle),
      Expanded(
        child: ColoredBox(
          color: WeaveColors.panel,
          child: placeholder != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(WeaveSpacing.s24),
                    child: Text(placeholder!, style: WeaveTypography.body, textAlign: TextAlign.center),
                  ),
                )
              : SelectionArea(
                  child: ListView.builder(
                    itemExtent: WeaveLayout.diffLineHeight,
                    itemCount: rows.length,
                    itemBuilder: (BuildContext context, int index) => switch (rows[index]) {
                      WeaveDiffHunkRow(:final String header) => _HunkRow(header: header),
                      WeaveDiffLineRow(:final WeaveDiffCell? original, :final WeaveDiffCell? updated) => Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: _Cell(cell: original)),
                          const _ColumnDivider(),
                          Expanded(child: _Cell(cell: updated)),
                        ],
                      ),
                    },
                  ),
                ),
        ),
      ),
    ],
  );

  static String _lines(int count) => '$count ${count == 1 ? 'line' : 'lines'}';
}

class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.path, required this.additions, required this.deletions, required this.statusLabel, required this.statusTone});

  final String path;
  final int additions;
  final int deletions;
  final String statusLabel;
  final WeaveTone statusTone;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: WeaveColors.surfaceElevated,
      border: Border(bottom: BorderSide(color: WeaveColors.borderSubtle)),
    ),
    child: SizedBox(
      height: WeaveLayout.diffFileHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s18),
        child: Row(
          children: <Widget>[
            const WeaveIcon(WeaveIcons.fileCode, size: WeaveIconSize.control, color: WeaveColors.textSecondary),
            const SizedBox(width: WeaveSpacing.s10),
            Expanded(
              child: WeaveTooltip(
                message: path,
                child: Text(path, style: WeaveTypography.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: WeaveSpacing.s12),
            Text(
              '+$additions',
              style: WeaveTypography.bodySmall.copyWith(color: WeaveColors.greenBright, fontWeight: WeaveTypography.medium),
            ),
            const SizedBox(width: WeaveSpacing.s6),
            Text(
              '−$deletions',
              style: WeaveTypography.bodySmall.copyWith(color: WeaveColors.red, fontWeight: WeaveTypography.medium),
            ),
            const SizedBox(width: WeaveSpacing.s12),
            WeaveStatusPill(label: statusLabel, tone: statusTone),
          ],
        ),
      ),
    ),
  );
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.title, required this.detail, required this.background, required this.color});

  final String title;
  final String detail;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: background,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: WeaveTypography.bodySmall.copyWith(color: color, fontWeight: WeaveTypography.semiBold),
          ),
          const SizedBox(width: WeaveSpacing.s8),
          Expanded(
            child: Text(
              detail,
              style: WeaveTypography.micro.copyWith(fontWeight: WeaveTypography.regular),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ColumnDivider extends StatelessWidget {
  const _ColumnDivider();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: WeaveLayout.divider,
    child: ColoredBox(color: WeaveColors.diffColumnDivider),
  );
}

class _HunkRow extends StatelessWidget {
  const _HunkRow({required this.header});

  final String header;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: WeaveColors.diffHunk,
    child: Padding(
      padding: const EdgeInsets.only(left: WeaveLayout.diffGutterWidth + WeaveLayout.diffMarkerWidth, right: WeaveSpacing.s12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          header,
          style: WeaveTypography.micro.copyWith(color: WeaveColors.diffHunkText, fontWeight: WeaveTypography.regular),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
}

class _Cell extends StatelessWidget {
  const _Cell({required this.cell});

  final WeaveDiffCell? cell;

  @override
  Widget build(BuildContext context) {
    final WeaveDiffCell? line = cell;
    if (line == null) {
      return const ColoredBox(color: WeaveColors.diffEmpty);
    }
    final (Color background, Color gutter, Color number, String marker, Color markerColor) = switch (line.kind) {
      WeaveDiffLineKind.context => (WeaveColors.panel, WeaveColors.surfaceSunken, WeaveColors.textDisabled, '', WeaveColors.textDisabled),
      WeaveDiffLineKind.added => (WeaveColors.diffAdded, WeaveColors.diffAddedGutter, WeaveColors.greenDeep, '+', WeaveColors.greenBright),
      WeaveDiffLineKind.removed => (WeaveColors.diffRemoved, WeaveColors.diffRemovedGutter, WeaveColors.diffRemovedNumber, '-', WeaveColors.red),
    };
    final TextStyle small = WeaveTypography.micro.copyWith(fontWeight: WeaveTypography.regular);
    return ColoredBox(
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: WeaveLayout.diffGutterWidth,
            child: ColoredBox(
              color: gutter,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: WeaveLayout.diffNumberWidth,
                  child: Text(
                    '${line.number}',
                    style: small.copyWith(color: number),
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: WeaveLayout.diffMarkerWidth,
            child: Center(
              child: Text(
                marker,
                style: small.copyWith(color: markerColor, fontWeight: WeaveTypography.medium),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: WeaveSpacing.s12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(line.text, style: WeaveTypography.code, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
