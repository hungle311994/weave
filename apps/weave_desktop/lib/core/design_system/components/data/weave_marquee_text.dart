import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../tokens/weave_effects.dart';
import '../../tokens/weave_typography.dart';

/// One-line text that reveals overflow by scrolling slowly while it is
/// [active]: it waits a moment, scrolls at [WeaveMotion.marqueeSpeed], rests
/// at the end, returns to the start and repeats until it is inactive.
///
/// Pass [active] to let a larger surface (e.g. the whole card) drive it;
/// when `null`, hovering the text itself does. Reduced motion keeps it still.
class WeaveMarqueeText extends StatefulWidget {
  const WeaveMarqueeText(this.text, {this.style, this.active, super.key});

  final String text;
  final TextStyle? style;
  final bool? active;

  @override
  State<WeaveMarqueeText> createState() => _WeaveMarqueeTextState();
}

class _WeaveMarqueeTextState extends State<WeaveMarqueeText> {
  final ScrollController _scrollController = ScrollController();
  bool _hovered = false;

  /// Bumped whenever scrolling must stop, so a running loop notices.
  int _generation = 0;

  /// The current wait of the loop; cancelled when it stops.
  Timer? _timer;

  bool get _active => widget.active ?? _hovered;

  @override
  void initState() {
    super.initState();
    if (widget.active ?? false) {
      // The scroll extent is known only after the first layout.
      WidgetsBinding.instance.addPostFrameCallback((Duration _) => _restart());
    }
  }

  @override
  void didUpdateWidget(WeaveMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.active ?? _hovered) != _active || oldWidget.text != widget.text) {
      _restart();
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _setHovered(bool hovered) {
    _hovered = hovered;
    if (widget.active == null) {
      _restart();
    }
  }

  void _restart() {
    final int generation = ++_generation;
    _timer?.cancel();
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(0, duration: WeaveMotion.standard, curve: WeaveMotion.curve);
    }
    if (_active) {
      _loop(generation);
    }
  }

  /// Completes after [duration], or never once cancelled.
  Future<void> _wait(Duration duration) {
    final Completer<void> done = Completer<void>();
    _timer = Timer(duration, done.complete);
    return done.future;
  }

  Future<void> _loop(int generation) async {
    bool current() => mounted && generation == _generation;
    while (current()) {
      await _wait(WeaveMotion.marqueeDelay);
      if (!mounted) {
        return;
      }
      if (!current() || !_scrollController.hasClients || MediaQuery.disableAnimationsOf(context)) {
        return;
      }
      final double distance = _scrollController.position.maxScrollExtent;
      if (distance <= 0) {
        return;
      }
      await _scrollController.animateTo(
        distance,
        duration: Duration(milliseconds: (distance / WeaveMotion.marqueeSpeed * 1000).round()),
        curve: Curves.linear,
      );
      if (!current()) {
        return;
      }
      await _wait(WeaveMotion.marqueePause);
      if (!current() || !_scrollController.hasClients) {
        return;
      }
      await _scrollController.animateTo(0, duration: WeaveMotion.slow, curve: WeaveMotion.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget text = ClipRect(
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(widget.text, style: widget.style ?? WeaveTypography.bodyStrong, maxLines: 1, softWrap: false),
      ),
    );
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: widget.active != null
          ? text
          : MouseRegion(
              onEnter: (PointerEnterEvent _) => _setHovered(true),
              onExit: (PointerExitEvent _) => _setHovered(false),
              child: text,
            ),
    );
  }
}
