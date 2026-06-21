import 'package:flutter/material.dart';

/// Dark, GitHub-inspired color palette shared across the app.
class AppColors {
  AppColors._();

  // Backgrounds
  static const Color bg = Color(0xFF0D1117);
  static const Color sidebar = Color(0xFF010409);
  static const Color surface = Color(0xFF161B22);
  static const Color elevated = Color(0xFF111827);

  // Borders
  static const Color border = Color(0xFF21262D);
  static const Color borderStrong = Color(0xFF30363D);

  // Text
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF484F58);

  // Accent
  static const Color accent = Color(0xFF1F6FEB);
  static const Color accentLight = Color(0xFF58A6FF);
  static const Color accentHover = Color(0xFF388BFD);

  // Status: success
  static const Color success = Color(0xFF3FB950);
  static const Color successBg = Color(0xFF1B4332);

  // Status: warning
  static const Color warning = Color(0xFFD29922);
  static const Color warningBg = Color(0xFF3D2B0A);

  // Status: error
  static const Color error = Color(0xFFF85149);
  static const Color errorBg = Color(0xFF3D0D0A);
}
