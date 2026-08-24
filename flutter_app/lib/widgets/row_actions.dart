import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';

/// One icon action attached to a table row.
class RowAction {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Destructive actions (delete) are tinted red.
  final bool destructive;

  const RowAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.destructive = false,
  });
}

/// Compact cluster of row actions.
///
/// The buttons stay small on the desktop, where a table row is 44px
/// tall, and grow to a full 40px touch target on phones, where the same
/// actions sit in the header of a record card.
class RowActions extends StatelessWidget {
  final List<RowAction> actions;

  const RowActions({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final touch = context.isTouch;
    final hit = touch ? 40.0 : 30.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in actions)
          IconButton(
            icon: Icon(action.icon, size: touch ? 20 : 17),
            color: action.destructive
                ? AppColors.error
                : AppColors.textSecondary,
            tooltip: action.tooltip,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: BoxConstraints(minWidth: hit, minHeight: hit),
            onPressed: action.onPressed,
          ),
      ],
    );
  }
}
