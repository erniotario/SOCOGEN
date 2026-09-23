import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:erp/shared/ui/theme/app_spacing.dart';

/// Content wrapper for the app's form dialogs.
///
/// A fixed `SizedBox(width: 420)` overflows once the screen is narrower
/// than the dialog's own insets and padding, which is every phone in
/// portrait. This takes the smaller of [maxWidth] and the width actually
/// available, and always scrolls vertically so a tall form still fits a
/// short window (a phone in landscape, for instance).
class DialogBody extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const DialogBody({super.key, this.maxWidth = 420, required this.child});

  /// Horizontal space the dialog itself consumes: the inset padding set
  /// in [AppTheme] on both sides, plus AlertDialog's content padding.
  static const double _chrome = (AppSpacing.xl + 24) * 2;

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - _chrome;
    final width = math.max(240.0, math.min(maxWidth, available));
    return SizedBox(
      width: width,
      child: SingleChildScrollView(child: child),
    );
  }
}
