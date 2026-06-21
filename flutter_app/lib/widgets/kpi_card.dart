import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// One KPI tile: an icon, an uppercase label and a large value, all
/// tinted with [color]. Used on the Dashboard and Rapports screens.
class KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const KpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label.toUpperCase(), style: AppTextStyles.kpiLabel),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: AppTextStyles.kpiValue.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Responsive row of [KpiCard]s: as many per row as fit at 220px each,
/// wrapping onto additional rows on narrow screens.
class KpiRow extends StatelessWidget {
  final List<KpiCard> cards;

  const KpiRow({super.key, required this.cards});

  static const double _spacing = 12;
  static const double _minCardWidth = 200;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var perRow = (constraints.maxWidth + _spacing) ~/ (_minCardWidth + _spacing);
        perRow = perRow.clamp(1, cards.length);
        final width = (constraints.maxWidth - _spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}
