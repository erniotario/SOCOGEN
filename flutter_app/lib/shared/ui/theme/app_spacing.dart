import 'package:flutter/widgets.dart';

import 'package:socogen/shared/ui/theme/app_breakpoints.dart';
import 'package:socogen/shared/ui/theme/app_colors.dart';

/// Spacing scale. Every gap in the UI is a multiple of 4 so that rhythm
/// stays consistent between screens and across window sizes.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Outer padding of a page body: tight on phones, generous on desktop.
  static EdgeInsets pagePadding(WindowSize size) => size.pick(
        compact: const EdgeInsets.fromLTRB(md, md, md, md),
        medium: const EdgeInsets.fromLTRB(xl, lg, xl, lg),
        expanded: const EdgeInsets.all(xxl),
      );

  /// Horizontal padding of the page header, kept in step with
  /// [pagePadding] so titles line up with the content below them.
  static double pageGutter(WindowSize size) =>
      size.pick(compact: md, medium: xl, expanded: xxl);
}

/// Corner radii. Small controls use [sm]/[md]; surfaces that group
/// content (cards, tables, dialogs) use [lg] and up.
class AppRadius {
  AppRadius._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 14;
  static const double xxl = 20;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius fieldRadius = BorderRadius.all(Radius.circular(md));
}

/// Motion durations. Kept short: this is a data-entry tool, so movement
/// should feel immediate rather than decorative.
class AppDurations {
  AppDurations._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
}

class AppCurves {
  AppCurves._();

  /// Material 3 "emphasized decelerate" — the default for anything that
  /// enters the screen.
  static const Curve enter = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Material 3 "emphasized accelerate" — for anything leaving.
  static const Curve exit = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Standard easing for state changes (hover, selection, resize).
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
}

/// Shadows. The palette is very dark, so elevation is carried mostly by
/// borders; shadows stay subtle and are only used to lift transient
/// surfaces (menus, dialogs, sheets) off the page.
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> low = [
    BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> medium = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static const List<BoxShadow> high = [
    BoxShadow(color: Color(0x66000000), blurRadius: 32, offset: Offset(0, 12)),
  ];
}

/// Shared decoration for the "raised panel" surface used by cards,
/// tables and section blocks.
BoxDecoration appSurfaceDecoration({
  Color color = AppColors.elevated,
  double radius = AppRadius.lg,
  Color border = AppColors.border,
  List<BoxShadow>? shadows,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border),
    boxShadow: shadows,
  );
}
