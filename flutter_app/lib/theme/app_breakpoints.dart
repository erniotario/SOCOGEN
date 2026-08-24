import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Material 3 window size classes.
///
/// The app is used on phones (compact), tablets and small windows
/// (medium) and on Windows desktop (expanded / large). Every adaptive
/// decision in the UI is expressed in terms of these four buckets rather
/// than raw pixel checks, so behaviour stays consistent across screens.
enum WindowSize { compact, medium, expanded, large }

class AppBreakpoints {
  AppBreakpoints._();

  /// Phones in portrait sit below this width.
  static const double medium = 600;

  /// Tablets in landscape / small desktop windows.
  static const double expanded = 840;

  /// Roomy desktop windows: the sidebar can show labels.
  static const double large = 1200;

  static WindowSize of(double width) {
    if (width >= large) return WindowSize.large;
    if (width >= expanded) return WindowSize.expanded;
    if (width >= medium) return WindowSize.medium;
    return WindowSize.compact;
  }
}

extension WindowSizeX on WindowSize {
  bool get isCompact => this == WindowSize.compact;
  bool get isMedium => this == WindowSize.medium;
  bool get isExpanded => this == WindowSize.expanded;
  bool get isLarge => this == WindowSize.large;

  bool get atLeastMedium => index >= WindowSize.medium.index;
  bool get atLeastExpanded => index >= WindowSize.expanded.index;
  bool get atLeastLarge => index >= WindowSize.large.index;

  /// Picks the value for this size class, falling back to the closest
  /// smaller one that was supplied. [compact] is therefore required.
  T pick<T>({required T compact, T? medium, T? expanded, T? large}) {
    switch (this) {
      case WindowSize.large:
        return large ?? expanded ?? medium ?? compact;
      case WindowSize.expanded:
        return expanded ?? medium ?? compact;
      case WindowSize.medium:
        return medium ?? compact;
      case WindowSize.compact:
        return compact;
    }
  }
}

extension ResponsiveContext on BuildContext {
  /// Size class of the whole window. Use [AppBreakpoints.of] with a
  /// `LayoutBuilder` constraint instead when a widget only owns a pane.
  WindowSize get windowSize =>
      AppBreakpoints.of(MediaQuery.sizeOf(this).width);

  bool get isCompact => windowSize.isCompact;

  /// True on phones/tablets, where hit targets must be finger sized and
  /// hover affordances are pointless.
  bool get isTouch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
