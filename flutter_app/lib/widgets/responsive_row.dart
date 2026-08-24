import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// One child of a [ResponsiveRow], with its share of the row width.
class RowItem {
  final Widget child;
  final int flex;

  const RowItem({required this.child, this.flex = 1});
}

/// Lays its children out side by side when there is room, and stacks
/// them to full width once the available space drops below
/// [stackBelow].
///
/// Form rows use this instead of a bare [Row] of [Expanded]s: three
/// fields sharing 360px of phone screen leave no usable width each, so
/// below the threshold they become three full-width fields instead.
class ResponsiveRow extends StatelessWidget {
  final List<RowItem> items;
  final double spacing;
  final double stackBelow;
  final CrossAxisAlignment crossAxisAlignment;

  const ResponsiveRow({
    super.key,
    required this.items,
    this.spacing = AppSpacing.md,
    this.stackBelow = 560,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < stackBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                items[i].child,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              Expanded(flex: items[i].flex, child: items[i].child),
            ],
          ],
        );
      },
    );
  }
}
