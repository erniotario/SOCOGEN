import 'package:flutter/material.dart';

import 'package:erp/shared/ui/theme/app_breakpoints.dart';
import 'package:erp/shared/ui/theme/app_colors.dart';
import 'package:erp/shared/ui/theme/app_spacing.dart';
import 'package:erp/shared/ui/theme/app_text_styles.dart';

/// One KPI tile: a tinted icon, an uppercase label and a large value.
/// Used on the Dashboard and Rapports screens.
///
/// The tile lays out side-by-side when it has room and stacks the icon
/// above the text once it gets narrow, so four tiles stay readable two
/// to a row on a phone.
class KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const KpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 190;
        final content = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: stacked ? AppSpacing.md : AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconBadge(icon: icon, color: color),
                    const SizedBox(height: AppSpacing.sm),
                    _Label(label: label),
                    const SizedBox(height: AppSpacing.xxs),
                    _Value(value: value, color: color, compact: true),
                  ],
                )
              : Row(
                  children: [
                    _IconBadge(icon: icon, color: color),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Label(label: label),
                          const SizedBox(height: AppSpacing.xxs),
                          _Value(value: value, color: color, compact: false),
                        ],
                      ),
                    ),
                  ],
                ),
        );

        return Material(
          color: AppColors.elevated,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _Label extends StatelessWidget {
  final String label;

  const _Label({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: AppTextStyles.kpiLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Value extends StatelessWidget {
  final String value;
  final Color color;
  final bool compact;

  const _Value({
    required this.value,
    required this.color,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    // The value animates between states so a refresh reads as an update
    // rather than a repaint.
    return AnimatedDefaultTextStyle(
      duration: AppDurations.fast,
      curve: AppCurves.standard,
      style: (compact
              ? AppTextStyles.kpiValueCompact
              : AppTextStyles.kpiValue)
          .copyWith(color: color),
      child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Responsive row of [KpiCard]s: as many per row as fit, wrapping onto
/// additional rows on narrow screens. Two tiles fit side by side on a
/// phone in portrait; four fit on a desktop window.
class KpiRow extends StatelessWidget {
  final List<KpiCard> cards;

  const KpiRow({super.key, required this.cards});

  static const double _spacing = AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    final minWidth = context.isCompact ? 148.0 : 200.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        var perRow = (constraints.maxWidth + _spacing) ~/ (minWidth + _spacing);
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
