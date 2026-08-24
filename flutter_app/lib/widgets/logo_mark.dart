import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The SOCOGEN app mark: a gradient tile with the company initial.
///
/// Used by the sidebar, the rail, the login card and the splash screen
/// so the product has one consistent identity everywhere.
class LogoMark extends StatelessWidget {
  final double size;

  const LogoMark({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentLight, AppColors.accent],
        ),
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: AppShadows.low,
      ),
      alignment: Alignment.center,
      child: Text(
        'S',
        style: TextStyle(
          fontSize: size * 0.52,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }
}

/// The app mark next to the product name — the lockup used on the login
/// card and the splash screen.
class LogoLockup extends StatelessWidget {
  final double markSize;
  final double titleSize;
  final String subtitle;

  const LogoLockup({
    super.key,
    this.markSize = 44,
    this.titleSize = 26,
    this.subtitle = 'Gestion de Stock',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LogoMark(size: markSize),
        const SizedBox(height: AppSpacing.md),
        Text(
          'SOCOGEN',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
