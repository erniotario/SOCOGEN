import 'package:flutter/material.dart';

import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';

/// Card with an icon+title header and a divider, used to group related
/// fields/content on the Paramètres and Sécurité screens.
class SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  /// Optional control shown at the right of the header row (a button, a
  /// status chip, …).
  final Widget? trailing;

  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final padding = context.isCompact ? AppSpacing.lg : AppSpacing.xl;
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: appSurfaceDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.accentLight),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.sectionLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: AppSpacing.lg),
          ...children,
        ],
      ),
    );
  }
}
