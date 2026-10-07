import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';

/// One selectable row in a [WeavePopoverMenu].
final class WeavePopoverItem<T> {
  const WeavePopoverItem({required this.value, required this.title, this.subtitle, this.icon, this.brand, this.selected = false});

  final T value;
  final String title;
  final String? subtitle;
  final WeaveIcons? icon;
  final BrandMark? brand;
  final bool selected;
}

/// A labelled group of menu items; a null label creates an action group.
final class WeavePopoverGroup<T> {
  const WeavePopoverGroup({required this.items, this.label});

  final String? label;
  final List<WeavePopoverItem<T>> items;
}

/// Grouped menu used by workspace switching, chat commands and selects.
class WeavePopoverMenu<T> extends StatefulWidget {
  const WeavePopoverMenu({required this.groups, required this.onSelected, this.width = WeaveLayout.popoverWidth, super.key});

  final List<WeavePopoverGroup<T>> groups;
  final ValueChanged<T>? onSelected;
  final double width;

  @override
  State<WeavePopoverMenu<T>> createState() => _WeavePopoverMenuState<T>();
}

class _WeavePopoverMenuState<T> extends State<WeavePopoverMenu<T>> {
  int _focusedIndex = 0;

  List<WeavePopoverItem<T>> get _items => widget.groups.expand<WeavePopoverItem<T>>((WeavePopoverGroup<T> group) => group.items).toList(growable: false);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _items.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final int direction = event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() => _focusedIndex = (_focusedIndex + direction) % _items.length);
      if (_focusedIndex < 0) {
        setState(() => _focusedIndex = _items.length - 1);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.space) {
      widget.onSelected?.call(_items[_focusedIndex].value);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onSelected != null;
    int index = 0;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        enabled: enabled,
        label: 'Menu',
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: SizedBox(
            width: widget.width,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WeaveColors.surfaceElevated,
                borderRadius: WeaveRadii.panelAll,
                border: Border.all(color: WeaveColors.borderSubtle),
                boxShadow: WeaveShadows.popover,
              ),
              // Scrolls when the menu is taller than the room beside its
              // anchor; no scrollbar gutter inside a compact menu.
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(WeaveSpacing.s8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int groupIndex = 0; groupIndex < widget.groups.length; groupIndex++) ...<Widget>[
                        if (groupIndex > 0)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: WeaveSpacing.s4, vertical: WeaveSpacing.s6),
                            child: Divider(),
                          ),
                        if (widget.groups[groupIndex].label case final String label)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s10, vertical: WeaveSpacing.s6),
                            child: Text(label.toUpperCase(), style: WeaveTypography.overline),
                          ),
                        for (final WeavePopoverItem<T> item in widget.groups[groupIndex].items) _item(item, index++, enabled),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(WeavePopoverItem<T> item, int index, bool enabled) {
    final bool focused = index == _focusedIndex;
    final bool compact = item.subtitle == null;
    return Semantics(
      button: true,
      selected: item.selected,
      enabled: enabled,
      label: item.subtitle == null ? item.title : '${item.title}, ${item.subtitle}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: focused ? WeaveColors.purple.withValues(alpha: 0.14) : null, borderRadius: WeaveRadii.controlAll),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? () => widget.onSelected!(item.value) : null,
            mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
            onHover: (bool hovering) {
              if (hovering) {
                setState(() => _focusedIndex = index);
              }
            },
            borderRadius: WeaveRadii.controlAll,
            splashFactory: NoSplash.splashFactory,
            focusColor: WeaveColors.purple.withValues(alpha: 0.22),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? WeaveSpacing.s40 : WeaveLayout.popoverItemHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s12, vertical: WeaveSpacing.s8),
                child: Row(
                  children: <Widget>[
                    if (item.brand != null) BrandIcon(item.brand!, size: WeaveIconSize.compact) else if (item.icon != null) WeaveIcon(item.icon!, size: WeaveIconSize.compact, color: focused ? WeaveColors.purpleSoft : WeaveColors.textSecondary),
                    if (item.brand != null || item.icon != null) const SizedBox(width: WeaveSpacing.s12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(item.title, style: WeaveTypography.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (item.subtitle != null)
                            Text(
                              item.subtitle!,
                              style: WeaveTypography.caption.copyWith(color: WeaveColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (item.selected) const WeaveIcon(WeaveIcons.check, size: WeaveIconSize.compact, color: WeaveColors.purpleSoft),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a [WeavePopoverMenu] below [anchor].
Future<T?> showWeavePopoverMenu<T>({required BuildContext context, required Rect anchor, required List<WeavePopoverGroup<T>> groups, double width = WeaveLayout.popoverWidth}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss menu',
    barrierColor: WeaveColors.canvas.withValues(alpha: 0),
    transitionDuration: WeaveMotion.fast,
    pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => CustomSingleChildLayout(
      delegate: WeavePopoverLayout(anchor: anchor, width: width),
      child: Material(
        type: MaterialType.transparency,
        child: WeavePopoverMenu<T>(groups: groups, width: width, onSelected: (T value) => Navigator.of(context).pop<T>(value)),
      ),
    ),
  );
}

/// Places a popover under its [anchor], or above it when there is not
/// enough room below; when neither side fits, it opens on the roomier side
/// and its content scrolls. It always stays inside the window.
final class WeavePopoverLayout extends SingleChildLayoutDelegate {
  const WeavePopoverLayout({required this.anchor, required this.width});

  final Rect anchor;
  final double width;

  static const double _gap = WeaveSpacing.s4;
  static const double _margin = WeaveSpacing.s8;

  double _below(Size size) => size.height - anchor.bottom - _gap - _margin;

  double _above() => anchor.top - _gap - _margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints.tightFor(width: width).copyWith(maxHeight: math.max(0, math.max(_below(constraints.biggest), _above())));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double left = math.max(_margin, math.min(anchor.left, size.width - width - _margin));
    final double below = _below(size);
    final double above = _above();
    final bool opensBelow = childSize.height <= below || (childSize.height > above && below >= above);
    return Offset(left, opensBelow ? anchor.bottom + _gap : anchor.top - _gap - childSize.height);
  }

  @override
  bool shouldRelayout(WeavePopoverLayout oldDelegate) => anchor != oldDelegate.anchor || width != oldDelegate.width;
}
