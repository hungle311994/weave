import 'package:flutter/painting.dart';

import '../../tokens/weave_colors.dart';

/// Semantic colour of a status pill or badge.
enum WeaveTone {
  /// Ready, connected, passed, running.
  success(WeaveColors.green),

  /// Modified, in progress.
  info(WeaveColors.blue),

  /// Needs review, setup required.
  warning(WeaveColors.amber),

  /// Failed, offline.
  danger(WeaveColors.redStrong),

  /// Planner badge, workspace counts.
  accent(WeaveColors.purple),

  /// Available, idle.
  neutral(WeaveColors.textTertiary);

  const WeaveTone(this.color);

  final Color color;

  /// Text colour on a tinted background; purple uses its lighter shade.
  Color get foreground => this == WeaveTone.accent ? WeaveColors.purpleSoft : color;
}
