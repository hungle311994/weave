import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';

/// One choice in a [WeaveSegmentedControl].
final class WeaveSegment<T> {
  const WeaveSegment({required this.value, required this.label, required this.icon});

  final T value;
  final String label;
  final WeaveIcons icon;
}

/// Compact single-selection control used for Write / Read only access. The
/// selected background slides between segments when the value changes.
class WeaveSegmentedControl<T> extends StatefulWidget {
  const WeaveSegmentedControl({required this.segments, required this.value, required this.onChanged, this.semanticLabel = 'Options', super.key});

  final List<WeaveSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  final String semanticLabel;

  @override
  State<WeaveSegmentedControl<T>> createState() => _WeaveSegmentedControlState<T>();
}

class _WeaveSegmentedControlState<T> extends State<WeaveSegmentedControl<T>> {
  static final Color _selectedColor = WeaveColors.purple.withValues(alpha: 0.2);

  final GlobalKey _track = GlobalKey();
  List<GlobalKey> _segmentKeys = <GlobalKey>[];

  /// Segment bounds inside the track, measured after layout; segments size to
  /// their labels, so the indicator cannot be placed before they are laid out.
  List<Rect> _segmentRects = const <Rect>[];

  void _measure(Duration _) {
    if (!mounted) {
      return;
    }
    final RenderBox? track = _track.currentContext?.findRenderObject() as RenderBox?;
    if (track == null || !track.hasSize) {
      return;
    }
    final List<Rect> rects = <Rect>[];
    for (final GlobalKey key in _segmentKeys) {
      final RenderBox? segment = key.currentContext?.findRenderObject() as RenderBox?;
      if (segment == null || !segment.hasSize) {
        return;
      }
      rects.add(segment.localToGlobal(Offset.zero, ancestor: track) & segment.size);
    }
    if (!listEquals(rects, _segmentRects)) {
      setState(() => _segmentRects = rects);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_segmentKeys.length != widget.segments.length) {
      _segmentKeys = <GlobalKey>[for (int index = 0; index < widget.segments.length; index++) GlobalKey()];
      _segmentRects = const <Rect>[];
    }
    WidgetsBinding.instance.addPostFrameCallback(_measure);

    final bool enabled = widget.onChanged != null;
    final int selectedIndex = widget.segments.indexWhere((WeaveSegment<T> segment) => segment.value == widget.value);
    final bool measured = selectedIndex >= 0 && _segmentRects.length == widget.segments.length;
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: WeaveColors.panel,
            borderRadius: WeaveRadii.controlAll,
            border: Border.all(color: WeaveColors.borderSubtle),
          ),
          child: SizedBox(
            height: WeaveLayout.segmentedControlHeight,
            child: Padding(
              padding: const EdgeInsets.all(WeaveLayout.segmentedControlInset),
              child: Stack(
                key: _track,
                children: <Widget>[
                  if (measured)
                    AnimatedPositioned.fromRect(
                      key: const Key('weave-segment-indicator'),
                      rect: _segmentRects[selectedIndex],
                      duration: WeaveMotion.standard,
                      curve: WeaveMotion.curve,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: _selectedColor, borderRadius: WeaveRadii.mdAll),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int index = 0; index < widget.segments.length; index++) ...<Widget>[
                        if (index > 0) const SizedBox(width: WeaveLayout.segmentedControlGap),
                        KeyedSubtree(
                          key: _segmentKeys[index],
                          child: _Segment<T>(segment: widget.segments[index], selected: index == selectedIndex, paintsSelection: !measured && index == selectedIndex, onChanged: widget.onChanged),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({required this.segment, required this.selected, required this.paintsSelection, required this.onChanged});

  final WeaveSegment<T> segment;
  final bool selected;

  /// Until segments are measured the selected one draws its own background.
  final bool paintsSelection;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;
    final Color foreground = selected ? WeaveColors.textPrimary : WeaveColors.textDisabled;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: segment.label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: paintsSelection ? _WeaveSegmentedControlState._selectedColor : null, borderRadius: WeaveRadii.mdAll),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? () => onChanged!(segment.value) : null,
            mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
            borderRadius: WeaveRadii.mdAll,
            focusColor: WeaveColors.purple.withValues(alpha: 0.22),
            hoverColor: WeaveColors.onAccent.withValues(alpha: 0.06),
            splashFactory: NoSplash.splashFactory,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  WeaveIcon(segment.icon, size: WeaveIconSize.segmented, color: selected ? WeaveColors.purpleSoft : foreground),
                  const SizedBox(width: WeaveSpacing.s6),
                  AnimatedDefaultTextStyle(
                    duration: WeaveMotion.standard,
                    curve: WeaveMotion.curve,
                    style: WeaveTypography.caption.copyWith(color: foreground, fontWeight: selected ? WeaveTypography.semiBold : WeaveTypography.medium),
                    child: Text(segment.label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
