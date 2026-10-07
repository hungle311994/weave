import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';
import '../overlays/weave_popover_menu.dart';

/// A select field whose options use [WeavePopoverMenu].
class WeaveSelect<T> extends StatefulWidget {
  const WeaveSelect({required this.value, required this.options, required this.onChanged, this.label, this.semanticLabel = 'Select option', super.key});

  final T value;
  final List<WeavePopoverItem<T>> options;
  final ValueChanged<T>? onChanged;
  final String? label;
  final String semanticLabel;

  @override
  State<WeaveSelect<T>> createState() => _WeaveSelectState<T>();
}

class _WeaveSelectState<T> extends State<WeaveSelect<T>> {
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _open() async {
    final RenderBox? box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || widget.onChanged == null) {
      return;
    }
    final Offset origin = box.localToGlobal(Offset.zero);
    final T? selected = await showWeavePopoverMenu<T>(
      context: context,
      anchor: origin & box.size,
      width: box.size.width,
      groups: <WeavePopoverGroup<T>>[WeavePopoverGroup<T>(items: widget.options)],
    );
    if (selected != null && mounted) {
      widget.onChanged!(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onChanged != null;
    final WeavePopoverItem<T> selected = widget.options.firstWhere((WeavePopoverItem<T> option) => option.value == widget.value);
    final Widget field = Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      value: selected.title,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          key: _anchorKey,
          decoration: BoxDecoration(
            color: WeaveColors.surface,
            borderRadius: WeaveRadii.controlAll,
            border: Border.all(color: WeaveColors.border),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: enabled ? _open : null,
              mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
              borderRadius: WeaveRadii.controlAll,
              splashFactory: NoSplash.splashFactory,
              hoverColor: WeaveColors.onAccent.withValues(alpha: 0.06),
              focusColor: WeaveColors.purple.withValues(alpha: 0.22),
              child: SizedBox(
                height: WeaveLayout.selectHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16),
                  child: Row(
                    children: <Widget>[
                      if (selected.brand != null) ...<Widget>[BrandIcon(selected.brand!, size: WeaveIconSize.control), const SizedBox(width: WeaveSpacing.s10)] else if (selected.icon != null) ...<Widget>[WeaveIcon(selected.icon!, size: WeaveIconSize.control), const SizedBox(width: WeaveSpacing.s10)],
                      Expanded(
                        child: Text(
                          selected.title,
                          style: WeaveTypography.bodySmall.copyWith(color: WeaveColors.textPrimary, fontWeight: WeaveTypography.medium),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const WeaveIcon(WeaveIcons.chevronDown, size: WeaveIconSize.control, color: WeaveColors.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.label == null) {
      return field;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(widget.label!, style: WeaveTypography.label),
        const SizedBox(height: WeaveSpacing.s8),
        field,
      ],
    );
  }
}
