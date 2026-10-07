import 'package:flutter/widgets.dart';

import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';
import '../navigation/weave_breadcrumb.dart';

/// Standard page heading with an optional trailing status or action area.
class WeavePageHeader extends StatelessWidget {
  const WeavePageHeader({required this.breadcrumb, required this.title, required this.subtitle, this.trailing, super.key});

  final List<String> breadcrumb;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (breadcrumb.isNotEmpty) ...<Widget>[
        WeaveBreadcrumb(items: breadcrumb),
        const SizedBox(height: WeaveSpacing.s12),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: WeaveTypography.display, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: WeaveSpacing.s4),
                Text(subtitle, style: WeaveTypography.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[const SizedBox(width: WeaveSpacing.s24), trailing!],
        ],
      ),
    ],
  );
}
