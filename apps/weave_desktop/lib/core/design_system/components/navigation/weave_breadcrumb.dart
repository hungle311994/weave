import 'package:flutter/widgets.dart';

import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';

/// A compact page-location trail, such as Workspace / New task.
class WeaveBreadcrumb extends StatelessWidget {
  const WeaveBreadcrumb({required this.items, super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Breadcrumb: ${items.join(', ')}',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int index = 0; index < items.length; index++) ...<Widget>[
          if (index > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s8),
              child: Text('/', style: WeaveTypography.breadcrumb),
            ),
          Text(items[index], style: WeaveTypography.breadcrumb),
        ],
      ],
    ),
  );
}
