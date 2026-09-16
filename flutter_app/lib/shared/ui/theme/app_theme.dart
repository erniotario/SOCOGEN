import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:socogen/shared/ui/theme/app_colors.dart';
import 'package:socogen/shared/ui/theme/app_spacing.dart';
import 'package:socogen/shared/ui/theme/app_text_styles.dart';

/// Global [ThemeData] for the app: a dark, GitHub-inspired surface set
/// shared by the Windows desktop build and the Android build.
///
/// Everything platform-dependent (hit-target density, scrollbar
/// behaviour, page transitions) is resolved here once, so screens can be
/// written without platform checks.
class AppTheme {
  AppTheme._();

  static bool get _isTouch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final isTouch = _isTouch;

    final colorScheme = base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: AppColors.accentLight,
      onPrimary: AppColors.bg,
      primaryContainer: AppColors.selected,
      onPrimaryContainer: AppColors.accentLight,
      secondary: AppColors.accent,
      onSecondary: AppColors.textPrimary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.elevated,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
      error: AppColors.error,
      onError: AppColors.textPrimary,
      errorContainer: AppColors.errorBg,
      onErrorContainer: AppColors.error,
      scrim: AppColors.scrim,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bg,
      // Drives Dropdown/menu surfaces; the Scaffold keeps its own color.
      canvasColor: AppColors.surface,
      dividerColor: AppColors.border,
      splashFactory: InkRipple.splashFactory,
      focusColor: AppColors.accentSubtle,
      hoverColor: AppColors.surfaceHover,
      highlightColor: Colors.transparent,

      // Touch builds get finger-sized targets; desktop stays compact so
      // more rows fit on screen.
      visualDensity: isTouch
          ? VisualDensity.standard
          : const VisualDensity(horizontal: -1, vertical: -1),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),

      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.sidebar,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.pageTitleCompact,
        iconTheme: IconThemeData(color: AppColors.textSecondary, size: 22),
        actionsIconTheme:
            IconThemeData(color: AppColors.textSecondary, size: 22),
      ),

      // --- Navigation -----------------------------------------------------

      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.sidebar,
        surfaceTintColor: Colors.transparent,
        scrimColor: AppColors.scrim,
        elevation: 0,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.sidebar,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.selected,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.accentLight : AppColors.textFaint,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? AppColors.accentLight : AppColors.textFaint,
          );
        }),
      ),

      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.sidebar,
        indicatorColor: AppColors.selected,
        elevation: 0,
        useIndicator: true,
        selectedIconTheme: IconThemeData(color: AppColors.accentLight, size: 22),
        unselectedIconTheme: IconThemeData(color: AppColors.textFaint, size: 22),
        selectedLabelTextStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.accentLight,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textFaint,
        ),
      ),

      // --- Surfaces --------------------------------------------------------

      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: AppColors.scrim,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: AppColors.borderStrong),
        ),
        titleTextStyle: AppTextStyles.pageTitleCompact,
        contentTextStyle: AppTextStyles.body,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: AppColors.borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: AppTextStyles.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.borderStrong),
        ),
      ),

      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: const BorderSide(color: AppColors.borderStrong),
            ),
          ),
        ),
      ),

      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: AppTextStyles.body,
      ),

      // --- Inputs ----------------------------------------------------------

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: !isTouch,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: isTouch ? 14 : 10,
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        floatingLabelStyle:
            const TextStyle(color: AppColors.accentLight, fontSize: 13),
        helperStyle: AppTextStyles.captionMuted,
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 11),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        border: const OutlineInputBorder(
          borderRadius: AppRadius.fieldRadius,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.fieldRadius,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.fieldRadius,
          borderSide: BorderSide(color: AppColors.accentHover, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.fieldRadius,
          borderSide: BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.fieldRadius,
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        disabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.fieldRadius,
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),

      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.accentLight,
        selectionColor: AppColors.accentSubtle,
        selectionHandleColor: AppColors.accentLight,
      ),

      // --- Buttons ---------------------------------------------------------

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.borderStrong,
          disabledForegroundColor: AppColors.textMuted,
          elevation: 0,
          minimumSize: Size(0, isTouch ? 46 : 38),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.borderStrong;
            }
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered)) {
              return AppColors.accentHover;
            }
            return AppColors.accent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: Size(0, isTouch ? 46 : 38),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.borderStrong),
          minimumSize: Size(0, isTouch ? 46 : 38),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentLight,
          minimumSize: Size(0, isTouch ? 44 : 34),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          hoverColor: AppColors.surfaceHover,
          minimumSize: Size.square(isTouch ? 44 : 34),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.selected
                  : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.accentLight
                  : AppColors.textSecondary),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.border),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),

      // --- Feedback & misc -------------------------------------------------

      iconTheme: const IconThemeData(color: AppColors.textSecondary),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.elevated,
        selectedColor: AppColors.selected,
        side: const BorderSide(color: AppColors.border),
        labelStyle: AppTextStyles.caption,
        secondaryLabelStyle: AppTextStyles.caption,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        titleTextStyle: AppTextStyles.body,
        subtitleTextStyle: AppTextStyles.caption,
        selectedColor: AppColors.accentLight,
        selectedTileColor: AppColors.selected,
      ),

      dataTableTheme: DataTableThemeData(
        headingTextStyle: AppTextStyles.tableHeader,
        dataTextStyle: AppTextStyles.tableCell,
        headingRowColor: WidgetStateProperty.all(AppColors.elevated),
        dataRowColor: WidgetStateProperty.all(AppColors.surface),
        dividerThickness: 1,
      ),

      scrollbarTheme: ScrollbarThemeData(
        // Desktop keeps the thumb visible so long tables read as
        // scrollable at a glance; touch platforms fade it in on scroll.
        thumbVisibility: WidgetStatePropertyAll(!isTouch),
        interactive: !isTouch,
        thickness: WidgetStatePropertyAll(isTouch ? 4 : 9),
        radius: const Radius.circular(AppRadius.sm),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return AppColors.textSecondary;
          }
          if (states.contains(WidgetState.hovered)) {
            return AppColors.textMuted;
          }
          return AppColors.borderStrong;
        }),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.elevated,
        contentTextStyle: AppTextStyles.body,
        actionTextColor: AppColors.accentLight,
        elevation: 0,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.borderStrong),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentLight,
        linearTrackColor: AppColors.border,
        circularTrackColor: Colors.transparent,
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.accent;
          return AppColors.surface;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: AppColors.borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.surface),
        trackOutlineColor: const WidgetStatePropertyAll(AppColors.borderStrong),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.accentLight
                : AppColors.borderStrong),
      ),

      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: AppColors.elevated,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.borderStrong),
          boxShadow: AppShadows.low,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        textStyle: AppTextStyles.caption,
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        headerBackgroundColor: AppColors.elevated,
        headerForegroundColor: AppColors.textPrimary,
        dividerColor: AppColors.border,
        todayBorder: const BorderSide(color: AppColors.accentLight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: AppColors.borderStrong),
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          if (states.contains(WidgetState.disabled)) return AppColors.textMuted;
          return AppColors.textPrimary;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.accent
                : Colors.transparent),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.textPrimary),
        yearBackgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.accent
                : Colors.transparent),
      ),
    );
  }
}
