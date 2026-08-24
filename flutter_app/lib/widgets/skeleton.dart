import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A shimmering placeholder block.
///
/// Skeletons are used instead of a centred spinner while a screen loads
/// for the first time: the page keeps its shape, so content appears to
/// resolve in place rather than replacing a blank screen.
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const Skeleton({
    super.key,
    this.width,
    this.height = 12,
    this.radius = AppRadius.xs,
  });

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Sweep a soft highlight from left to right across the block.
        final t = _controller.value * 2 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 0.6, 0),
              end: Alignment(t + 0.6, 0),
              colors: const [
                AppColors.surface,
                AppColors.surfaceHover,
                AppColors.surface,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton stand-in for a table or list while its data loads.
class SkeletonList extends StatelessWidget {
  final int rows;
  final double rowHeight;
  final EdgeInsets padding;

  const SkeletonList({
    super.key,
    this.rows = 8,
    this.rowHeight = 44,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows; i++) ...[
            SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  const Expanded(flex: 3, child: Skeleton(height: 12)),
                  const SizedBox(width: AppSpacing.lg),
                  const Expanded(flex: 5, child: Skeleton(height: 12)),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Skeleton(
                        width: 40 + (i.isEven ? 12 : 0),
                        height: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i != rows - 1)
              const Divider(color: AppColors.border, height: 1),
          ],
        ],
      ),
    );
  }
}

/// Skeleton stand-in for a row of KPI tiles.
class SkeletonKpiRow extends StatelessWidget {
  final int count;

  const SkeletonKpiRow({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppSpacing.md;
        var perRow = (constraints.maxWidth + spacing) ~/ (200 + spacing);
        perRow = perRow.clamp(1, count);
        final width = (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: width,
                height: 78,
                decoration: appSurfaceDecoration(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Skeleton(width: 70, height: 9),
                    SizedBox(height: AppSpacing.sm),
                    Skeleton(width: 44, height: 18),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
