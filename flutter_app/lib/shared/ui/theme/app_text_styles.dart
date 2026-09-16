import 'package:flutter/material.dart';

import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';

/// Shared text styles.
///
/// Sizes follow a small, deliberate scale (10 / 11 / 12 / 13 / 15 / 18 /
/// 20 / 26) rather than ad-hoc numbers, so headings and body copy stay
/// in proportion on every screen. Anything that renders a quantity uses
/// [tabularFigures] so digits line up in columns.
class AppTextStyles {
  AppTextStyles._();

  /// Fixed-advance digits — essential for stock quantities in tables,
  /// and for KPI values that tick up and down without shifting width.
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  // --- Headings -----------------------------------------------------

  static const TextStyle display = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static const TextStyle pageTitleCompact = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static const TextStyle pageSubtitle = TextStyle(
    fontSize: 13,
    height: 1.35,
    color: AppColors.textSecondary,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// Small uppercase label that introduces a block of content.
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    letterSpacing: 1.1,
  );

  // --- Body ---------------------------------------------------------

  static const TextStyle body = TextStyle(
    fontSize: 13,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontSize: 13,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    height: 1.35,
    color: AppColors.textSecondary,
  );

  static const TextStyle captionMuted = TextStyle(
    fontSize: 11,
    height: 1.35,
    color: AppColors.textMuted,
  );

  // --- Numbers ------------------------------------------------------

  static const TextStyle kpiValue = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
    fontFeatures: tabularFigures,
  );

  static const TextStyle kpiValueCompact = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
    fontFeatures: tabularFigures,
  );

  static const TextStyle kpiLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    letterSpacing: 1.1,
  );

  /// Quantities inside table cells and detail rows.
  static const TextStyle numeric = TextStyle(
    fontSize: 13,
    color: AppColors.textPrimary,
    fontFeatures: tabularFigures,
  );

  static const TextStyle numericStrong = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    fontFeatures: tabularFigures,
  );

  // --- Tables -------------------------------------------------------

  static const TextStyle tableHeader = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    letterSpacing: 0.8,
  );

  static const TextStyle tableCell = TextStyle(
    fontSize: 13,
    color: AppColors.textPrimary,
  );

  /// Product references and other identifiers — slightly tightened and
  /// tinted so they read as keys rather than prose.
  static const TextStyle identifier = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.accentLight,
    letterSpacing: 0.1,
  );

  // --- Responsive helpers -------------------------------------------

  static TextStyle title(WindowSize size) =>
      size.isCompact ? pageTitleCompact : pageTitle;

  static TextStyle kpi(WindowSize size) =>
      size.isCompact ? kpiValueCompact : kpiValue;
}
