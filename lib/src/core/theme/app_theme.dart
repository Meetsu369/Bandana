import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_shadows.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Bandana app theme configuration — Material 3 with BANDANA design tokens.
class AppTheme {
  AppTheme._();

  // Chart axis colors (preserved from existing implementation).
  static const Color accelXColor = Color(0xFFEF5350);
  static const Color accelYColor = Color(0xFF66BB6A);
  static const Color accelZColor = Color(0xFF42A5F5);
  static const Color gyroXColor = Color(0xFFFF7043);
  static const Color gyroYColor = Color(0xFFAB47BC);
  static const Color gyroZColor = Color(0xFFFFA726);

  static const List<Color> axisColors = [
    accelXColor,
    accelYColor,
    accelZColor,
    gyroXColor,
    gyroYColor,
    gyroZColor,
  ];

  static const List<String> axisLabels = ['aX', 'aY', 'aZ', 'gX', 'gY', 'gZ'];

  // ── Backward-compatibility spacing tokens (deprecated, use AppSpacing directly) ──
  static const double spacingXs = AppSpacing.xs;
  static const double spacingSm = AppSpacing.sm;
  static const double spacingMd = AppSpacing.md;
  static const double spacingLg = AppSpacing.lg;
  static const double spacingXl = AppSpacing.xl;

  // ── Backward-compatibility radius tokens (deprecated, use AppRadius directly) ──
  static const double radiusSm = AppRadius.sm;
  static const double radiusMd = AppRadius.md;
  static const double radiusLg = AppRadius.lg;

  // ── Light Theme ──

  static ThemeData get lightTheme {
    const brightness = Brightness.light;

    final colorScheme = ColorScheme.light(
      brightness: brightness,
      primary: AppColors.lightPink,
      onPrimary: AppColors.lightWhite,
      primaryContainer: AppColors.lightPinkSoft,
      onPrimaryContainer: AppColors.lightInk,
      secondary: AppColors.lightForest,
      onSecondary: AppColors.lightWhite,
      secondaryContainer: AppColors.lightMoss.withValues(alpha: 0.15),
      onSecondaryContainer: AppColors.lightInk,
      tertiary: AppColors.lightMoss,
      onTertiary: AppColors.lightWhite,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightInk,
      surfaceContainerHighest: AppColors.lightSlateSoft,
      onSurfaceVariant: AppColors.lightSlate,
      outline: AppColors.lightSlate,
      outlineVariant: AppColors.lightSlateSoft,
      error: AppColors.lightDanger,
      onError: AppColors.lightWhite,
      errorContainer: AppColors.lightDanger.withValues(alpha: 0.15),
      onErrorContainer: AppColors.lightInk,
      shadow: AppColors.lightInk.withValues(alpha: 0.1),
      scrim: AppColors.lightInk.withValues(alpha: 0.5),
      inverseSurface: AppColors.darkSurface,
      onInverseSurface: AppColors.darkInk,
      inversePrimary: AppColors.darkPink,
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.lightBackground,
      canvasColor: AppColors.lightSurface,
    );

    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme, brightness),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: AppShadows.cardBorder(brightness).top,
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: AppColors.lightSurface,
        foregroundColor: AppColors.lightInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.h2For(brightness),
        iconTheme: IconThemeData(color: AppColors.lightInk, size: AppSpacing.iconSizeLarge),
        actionsIconTheme: IconThemeData(color: AppColors.lightInk, size: AppSpacing.iconSizeMedium),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        indicatorColor: AppColors.lightPinkSoft,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        height: 72,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypography.labelFor(brightness).copyWith(color: AppColors.lightPink);
          }
          return AppTypography.labelSmallFor(brightness).copyWith(color: AppColors.lightSlate);
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.lightPink,
        foregroundColor: AppColors.lightWhite,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.button,
          side: AppShadows.cardBorder(brightness).top,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.lightPink,
          foregroundColor: AppColors.lightWhite,
          disabledBackgroundColor: AppColors.lightSlateSoft,
          disabledForegroundColor: AppColors.lightSlate,
          minimumSize: Size(0, AppSpacing.buttonHeight),
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.button,
            side: AppShadows.cardBorder(brightness).top,
          ),
          textStyle: AppTypography.labelFor(brightness),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.lightInk,
          disabledForegroundColor: AppColors.lightSlate,
          minimumSize: Size(0, AppSpacing.buttonHeight),
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          side: AppShadows.buttonBorder(brightness).top,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle: AppTypography.labelFor(brightness),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.lightPink,
          disabledForegroundColor: AppColors.lightSlate,
          minimumSize: Size(AppSpacing.buttonHeightSmall, AppSpacing.buttonHeightSmall),
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonSmall),
          textStyle: AppTypography.labelFor(brightness),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: AppShadows.inputBorder(brightness).top,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: AppShadows.inputBorder(brightness).top,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: AppShadows.inputBorder(brightness, isFocused: true).top,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: AppShadows.inputBorder(brightness, hasError: true).top,
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: AppShadows.inputBorder(brightness, isFocused: true, hasError: true).top,
        ),
        labelStyle: AppTypography.bodySmallFor(brightness),
        hintStyle: AppTypography.bodySmallFor(brightness).copyWith(color: AppColors.lightSlate),
        errorStyle: AppTypography.captionFor(brightness).copyWith(color: AppColors.lightDanger),
        floatingLabelStyle: AppTypography.labelSmallFor(brightness).copyWith(color: AppColors.lightPink),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightSlateSoft,
        disabledColor: AppColors.lightSlateSoft.withValues(alpha: 0.5),
        selectedColor: AppColors.lightPinkSoft,
        secondarySelectedColor: AppColors.lightPinkSoft,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.chipHorizontalPadding,
          vertical: AppSpacing.chipVerticalPadding,
        ),
        labelStyle: AppTypography.labelSmallFor(brightness),
        secondaryLabelStyle: AppTypography.labelSmallFor(brightness).copyWith(color: AppColors.lightWhite),
        brightness: brightness,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
        side: AppShadows.buttonBorder(brightness).top,
        pressElevation: 0,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.lightSlateSoft,
        thickness: 1,
        space: AppSpacing.dividerMargin,
        indent: AppSpacing.dividerMargin,
        endIndent: AppSpacing.dividerMargin,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        titleTextStyle: AppTypography.bodyMediumFor(brightness),
        subtitleTextStyle: AppTypography.bodySmallFor(brightness),
        leadingAndTrailingTextStyle: AppTypography.bodySmallFor(brightness),
        iconColor: AppColors.lightSlate,
        textColor: AppColors.lightInk,
        minTileHeight: AppSpacing.buttonHeightSmall,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smRadius),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.dialog,
          side: AppShadows.cardBorder(brightness).top,
        ),
        titleTextStyle: AppTypography.h3For(brightness),
        contentTextStyle: AppTypography.bodyFor(brightness),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.dialog,
          side: AppShadows.cardBorder(brightness).top,
        ),
        modalBackgroundColor: AppColors.lightSurface,
        dragHandleColor: AppColors.lightSlate,
        dragHandleSize: const Size(36, 4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.lightInk,
        contentTextStyle: AppTypography.bodyFor(brightness).copyWith(color: AppColors.lightWhite),
        actionTextColor: AppColors.lightPinkSoft,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdRadius,
          side: AppShadows.cardBorder(brightness).top,
        ),
        elevation: 0,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.lightInk,
          borderRadius: AppRadius.smRadius,
          boxShadow: AppShadows.raised,
        ),
        textStyle: AppTypography.labelSmallFor(brightness).copyWith(color: AppColors.lightWhite),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        preferBelow: true,
        verticalOffset: 8,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.lightPink,
        linearTrackColor: AppColors.lightPinkSoft,
        circularTrackColor: AppColors.lightPinkSoft,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.lightPink,
        unselectedLabelColor: AppColors.lightSlate,
        indicatorColor: AppColors.lightPink,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: AppTypography.labelFor(brightness),
        unselectedLabelStyle: AppTypography.labelFor(brightness),
        dividerColor: Colors.transparent,
      ),
    );
  }

  // ── Dark Theme ──

  static ThemeData get darkTheme {
    const brightness = Brightness.dark;

    final colorScheme = ColorScheme.dark(
      brightness: brightness,
      primary: AppColors.darkPink,
      onPrimary: AppColors.darkWhite,
      primaryContainer: AppColors.darkPinkSoft,
      onPrimaryContainer: AppColors.darkInk,
      secondary: AppColors.darkForest,
      onSecondary: AppColors.darkWhite,
      secondaryContainer: AppColors.darkMoss.withValues(alpha: 0.2),
      onSecondaryContainer: AppColors.darkInk,
      tertiary: AppColors.darkMoss,
      onTertiary: AppColors.darkWhite,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkInk,
      surfaceContainerHighest: AppColors.darkSlateSoft,
      onSurfaceVariant: AppColors.darkSlate,
      outline: AppColors.darkSlate,
      outlineVariant: AppColors.darkSlateSoft,
      error: AppColors.darkDanger,
      onError: AppColors.darkWhite,
      errorContainer: AppColors.darkDanger.withValues(alpha: 0.2),
      onErrorContainer: AppColors.darkInk,
      shadow: Colors.black.withValues(alpha: 0.3),
      scrim: Colors.black.withValues(alpha: 0.7),
      inverseSurface: AppColors.lightSurface,
      onInverseSurface: AppColors.lightInk,
      inversePrimary: AppColors.lightPink,
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.darkBackground,
      canvasColor: AppColors.darkSurface,
    );

    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme, brightness),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: AppShadows.cardBorder(brightness).top,
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: AppColors.darkSurface,
        foregroundColor: AppColors.darkInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.h2For(brightness),
        iconTheme: IconThemeData(color: AppColors.darkInk, size: AppSpacing.iconSizeLarge),
        actionsIconTheme: IconThemeData(color: AppColors.darkInk, size: AppSpacing.iconSizeMedium),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        indicatorColor: AppColors.darkPinkSoft,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        height: 72,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypography.labelFor(brightness).copyWith(color: AppColors.darkPink);
          }
          return AppTypography.labelSmallFor(brightness).copyWith(color: AppColors.darkSlate);
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.darkPink,
        foregroundColor: AppColors.darkWhite,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.button,
          side: AppShadows.cardBorder(brightness).top,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.darkPink,
          foregroundColor: AppColors.darkWhite,
          disabledBackgroundColor: AppColors.darkSlateSoft,
          disabledForegroundColor: AppColors.darkSlate,
          minimumSize: Size(0, AppSpacing.buttonHeight),
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.button,
            side: AppShadows.cardBorder(brightness).top,
          ),
          textStyle: AppTypography.labelFor(brightness),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkInk,
          disabledForegroundColor: AppColors.darkSlate,
          minimumSize: Size(0, AppSpacing.buttonHeight),
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          side: AppShadows.buttonBorder(brightness).top,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle: AppTypography.labelFor(brightness),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.darkPink,
          disabledForegroundColor: AppColors.darkSlate,
          minimumSize: Size(AppSpacing.buttonHeightSmall, AppSpacing.buttonHeightSmall),
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonSmall),
          textStyle: AppTypography.labelFor(brightness),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: AppShadows.inputBorder(brightness).top,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: AppShadows.inputBorder(brightness).top,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: AppShadows.inputBorder(brightness, isFocused: true).top,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: AppShadows.inputBorder(brightness, hasError: true).top,
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: AppShadows.inputBorder(brightness, isFocused: true, hasError: true).top,
        ),
        labelStyle: AppTypography.bodySmallFor(brightness),
        hintStyle: AppTypography.bodySmallFor(brightness).copyWith(color: AppColors.darkSlate),
        errorStyle: AppTypography.captionFor(brightness).copyWith(color: AppColors.darkDanger),
        floatingLabelStyle: AppTypography.labelSmallFor(brightness).copyWith(color: AppColors.darkPink),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSlateSoft,
        disabledColor: AppColors.darkSlateSoft.withValues(alpha: 0.5),
        selectedColor: AppColors.darkPinkSoft,
        secondarySelectedColor: AppColors.darkPinkSoft,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.chipHorizontalPadding,
          vertical: AppSpacing.chipVerticalPadding,
        ),
        labelStyle: AppTypography.labelSmallFor(brightness),
        secondaryLabelStyle: AppTypography.labelSmallFor(brightness).copyWith(color: AppColors.darkWhite),
        brightness: brightness,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
        side: AppShadows.buttonBorder(brightness).top,
        pressElevation: 0,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.darkSlateSoft,
        thickness: 1,
        space: AppSpacing.dividerMargin,
        indent: AppSpacing.dividerMargin,
        endIndent: AppSpacing.dividerMargin,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        titleTextStyle: AppTypography.bodyMediumFor(brightness),
        subtitleTextStyle: AppTypography.bodySmallFor(brightness),
        leadingAndTrailingTextStyle: AppTypography.bodySmallFor(brightness),
        iconColor: AppColors.darkSlate,
        textColor: AppColors.darkInk,
        minTileHeight: AppSpacing.buttonHeightSmall,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smRadius),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.dialog,
          side: AppShadows.cardBorder(brightness).top,
        ),
        titleTextStyle: AppTypography.h3For(brightness),
        contentTextStyle: AppTypography.bodyFor(brightness),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.dialog,
          side: AppShadows.cardBorder(brightness).top,
        ),
        modalBackgroundColor: AppColors.darkSurface,
        dragHandleColor: AppColors.darkSlate,
        dragHandleSize: const Size(36, 4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkInk,
        contentTextStyle: AppTypography.bodyFor(brightness).copyWith(color: AppColors.darkWhite),
        actionTextColor: AppColors.darkPinkSoft,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdRadius,
          side: AppShadows.cardBorder(brightness).top,
        ),
        elevation: 0,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.darkInk,
          borderRadius: AppRadius.smRadius,
          boxShadow: AppShadows.raised,
        ),
        textStyle: AppTypography.labelSmallFor(brightness).copyWith(color: AppColors.darkWhite),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        preferBelow: true,
        verticalOffset: 8,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.darkPink,
        linearTrackColor: AppColors.darkPinkSoft,
        circularTrackColor: AppColors.darkPinkSoft,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.darkPink,
        unselectedLabelColor: AppColors.darkSlate,
        indicatorColor: AppColors.darkPink,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: AppTypography.labelFor(brightness),
        unselectedLabelStyle: AppTypography.labelFor(brightness),
        dividerColor: Colors.transparent,
      ),
    );
  }

  // ── Text Theme Builder ──

  static TextTheme _buildTextTheme(TextTheme base, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final ink = isLight ? AppColors.lightInk : AppColors.darkInk;
    final slate = isLight ? AppColors.lightSlate : AppColors.darkSlate;

    return base.copyWith(
      displayLarge: AppTypography.displayFor(brightness),
      displayMedium: AppTypography.displayFor(brightness).copyWith(fontSize: 48),
      displaySmall: AppTypography.displayFor(brightness).copyWith(fontSize: 36),
      headlineLarge: AppTypography.h1For(brightness),
      headlineMedium: AppTypography.h2For(brightness),
      headlineSmall: AppTypography.h3For(brightness),
      titleLarge: AppTypography.h3For(brightness),
      titleMedium: AppTypography.labelFor(brightness).copyWith(fontSize: 16),
      titleSmall: AppTypography.labelSmallFor(brightness),
      bodyLarge: AppTypography.bodyFor(brightness),
      bodyMedium: AppTypography.bodyMediumFor(brightness),
      bodySmall: AppTypography.bodySmallFor(brightness),
      labelLarge: AppTypography.labelFor(brightness),
      labelMedium: AppTypography.labelSmallFor(brightness),
      labelSmall: AppTypography.captionFor(brightness),
    ).apply(
      bodyColor: ink,
      displayColor: ink,
      decorationColor: slate,
    );
  }
}