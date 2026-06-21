import 'package:flutter/material.dart';

import '../data/models/view_models.dart';
import '../theme/app_colors.dart';

/// Maps a [StockStatus] to its accent color: green/orange/red, matching
/// the thresholds used by the Dashboard and Rapports screens.
extension StockStatusColor on StockStatus {
  Color get color {
    switch (this) {
      case StockStatus.enStock:
        return AppColors.success;
      case StockStatus.stockFaible:
        return AppColors.warning;
      case StockStatus.rupture:
        return AppColors.error;
    }
  }
}

/// Small colored pill showing a [StockStatus] label, used on the
/// Rapports table.
class StatusBadge extends StatelessWidget {
  final StockStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
