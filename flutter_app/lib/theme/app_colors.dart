import 'package:flutter/material.dart';

/// Dark, GitHub-inspired color palette shared across the app.
class AppColors {
  AppColors._();

  // Backgrounds
  static const Color bg = Color(0xFF0D1117);
  static const Color sidebar = Color(0xFF010409);
  static const Color surface = Color(0xFF161B22);
  static const Color elevated = Color(0xFF111827);

  /// Surface tint used while a row or tile is hovered/pressed.
  static const Color surfaceHover = Color(0xFF1C222B);

  /// Background of the active navigation entry and other selected rows.
  static const Color selected = Color(0xFF1C2D4A);

  /// Dim layer behind dialogs, drawers and bottom sheets.
  static const Color scrim = Color(0xB3010409);

  // Borders
  static const Color border = Color(0xFF21262D);
  static const Color borderStrong = Color(0xFF30363D);

  // Text
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF484F58);

  /// The dimmer label tone used by inactive navigation entries.
  static const Color textFaint = Color(0xFF7D8590);

  // Accent
  static const Color accent = Color(0xFF1F6FEB);
  static const Color accentLight = Color(0xFF58A6FF);
  static const Color accentHover = Color(0xFF388BFD);

  /// Very low-opacity accent, for selected-row washes and chip fills.
  static const Color accentSubtle = Color(0x2958A6FF);

  // Status: success
  static const Color success = Color(0xFF3FB950);
  static const Color successBg = Color(0xFF1B4332);

  // Status: warning
  static const Color warning = Color(0xFFD29922);
  static const Color warningBg = Color(0xFF3D2B0A);

  // Status: error
  static const Color error = Color(0xFFF85149);
  static const Color errorBg = Color(0xFF3D0D0A);

  // Status: informational
  static const Color info = Color(0xFF58A6FF);
  static const Color infoBg = Color(0xFF10243E);
}
