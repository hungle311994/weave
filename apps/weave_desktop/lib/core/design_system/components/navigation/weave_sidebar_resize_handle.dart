import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';

/// The draggable separator between the sidebar and workspace.
class WeaveSidebarResizeHandle extends StatefulWidget {
  const WeaveSidebarResizeHandle({required this.expanded, required this.onToggle, required this.onDragStart, required this.onDragUpdate, required this.onDragEnd, super.key});

  final bool expanded;
  final VoidCallback onToggle;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  State<WeaveSidebarResizeHandle> createState() => _WeaveSidebarResizeHandleState();
}

class _WeaveSidebarResizeHandleState extends State<WeaveSidebarResizeHandle> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Sidebar resize handle');
  bool _hovered = false;
  bool _dragging = false;

  void _setDragging(bool dragging) {
    if (_dragging != dragging) {
      setState(() => _dragging = dragging);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.space) {
      widget.onToggle();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && widget.expanded || event.logicalKey == LogicalKeyboardKey.arrowRight && !widget.expanded) {
      widget.onToggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // The whole narrow hit target highlights on hover/drag. There is no permanent
    // grip, so the divider stays visually quiet until it is being used.
    final bool active = _hovered || _dragging;
    return Semantics(
      button: true,
      label: 'Resize sidebar',
      value: widget.expanded ? 'Expanded' : 'Collapsed',
      increasedValue: widget.expanded ? null : 'Expanded',
      decreasedValue: widget.expanded ? 'Collapsed' : null,
      onTap: widget.onToggle,
      onIncrease: widget.expanded ? null : widget.onToggle,
      onDecrease: widget.expanded ? widget.onToggle : null,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (PointerEnterEvent event) => setState(() => _hovered = true),
          onExit: (PointerExitEvent event) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onToggle,
            onHorizontalDragStart: (DragStartDetails details) {
              _setDragging(true);
              widget.onDragStart(details);
            },
            onHorizontalDragUpdate: widget.onDragUpdate,
            onHorizontalDragEnd: (DragEndDetails details) {
              _setDragging(false);
              widget.onDragEnd(details);
            },
            onHorizontalDragCancel: () => _setDragging(false),
            child: AnimatedContainer(
              key: const Key('sidebar-resize-handle-surface'),
              width: WeaveLayout.sidebarResizeHandleWidth,
              duration: WeaveMotion.fast,
              curve: WeaveMotion.curve,
              color: active ? WeaveColors.tint(WeaveColors.purple) : WeaveColors.sidebar,
            ),
          ),
        ),
      ),
    );
  }
}
