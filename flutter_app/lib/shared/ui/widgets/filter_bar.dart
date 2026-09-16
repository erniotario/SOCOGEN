import 'package:flutter/material.dart';

import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';

/// One control inside a [FilterBar]. [flex] sets its share of the row
/// when the fields sit side by side.
class FilterField {
  final Widget child;
  final int flex;

  const FilterField({required this.child, this.flex = 2});
}

/// Panel grouping a screen's search box, dropdowns and date pickers.
///
/// The fields sit on one row when there is room and stack to full width
/// once the panel gets narrow, which keeps every control comfortably
/// tappable on a phone instead of squeezing three dropdowns into a line.
class FilterBar extends StatelessWidget {
  final List<FilterField> fields;

  /// When non-null a "clear" button is shown; pass null while no filter
  /// is active so the control only appears when it can do something.
  final VoidCallback? onClear;

  /// Extra controls (export buttons, toggles) placed after the fields.
  final List<Widget> trailing;

  const FilterBar({
    super.key,
    required this.fields,
    this.onClear,
    this.trailing = const [],
  });

  /// Below this width the fields stack instead of sharing a row.
  static const double _stackBelow = 640;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: appSurfaceDecoration(radius: AppRadius.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < _stackBelow;
          final clearButton = onClear == null
              ? null
              : (stacked
                  ? OutlinedButton.icon(
                      onPressed: onClear,
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                      label: const Text('Effacer les filtres'),
                    )
                  : IconButton(
                      tooltip: 'Effacer les filtres',
                      onPressed: onClear,
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                      color: AppColors.accentLight,
                    ));

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.md),
                  fields[i].child,
                ],
                for (final widget in trailing) ...[
                  const SizedBox(height: AppSpacing.md),
                  widget,
                ],
                if (clearButton != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  clearButton,
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.md),
                Expanded(flex: fields[i].flex, child: fields[i].child),
              ],
              for (final widget in trailing) ...[
                const SizedBox(width: AppSpacing.md),
                widget,
              ],
              if (clearButton != null) ...[
                const SizedBox(width: AppSpacing.sm),
                clearButton,
              ],
            ],
          );
        },
      ),
    );
  }
}
