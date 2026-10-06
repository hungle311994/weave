import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';

/// A labelled text input in the design style; [WeaveTextField.multiline] is the
/// text-area variant used for task descriptions and review notes.
class WeaveTextField extends StatelessWidget {
  const WeaveTextField({this.controller, this.focusNode, this.label, this.hintText, this.helperText, this.errorText, this.prefixIcon, this.enabled = true, this.autofocus = false, this.onChanged, this.onSubmitted, super.key}) : minLines = null, maxLines = 1;

  const WeaveTextField.multiline({this.controller, this.focusNode, this.label, this.hintText, this.helperText, this.errorText, this.enabled = true, this.autofocus = false, this.onChanged, this.minLines = 4, this.maxLines, super.key}) : prefixIcon = null, onSubmitted = null;

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Shown above the field, e.g. "Task description".
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final WeaveIcons? prefixIcon;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? minLines;

  /// Null lets a multiline field grow with its text.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final TextField field = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: maxLines == 1 ? TextInputType.text : TextInputType.multiline,
      style: WeaveTypography.bodyLarge.copyWith(color: WeaveColors.textPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        helperText: helperText,
        errorText: errorText,
        prefixIcon: prefixIcon == null ? null : WeaveIcon(prefixIcon!, size: 16, color: WeaveColors.textDisabled),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 20),
      ),
    );
    if (label == null) {
      return field;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label!, style: WeaveTypography.label),
        const SizedBox(height: WeaveSpacing.s8),
        field,
      ],
    );
  }
}
