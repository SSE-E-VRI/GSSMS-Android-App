import 'package:flutter/material.dart';

import 'gssms_colors.dart';
import 'gssms_radius.dart';
import 'gssms_spacing.dart';

export 'gssms_colors.dart';
export 'gssms_radius.dart';
export 'gssms_spacing.dart';

/// Design tokens and Material 3 theme configuration for GSSMS Mobile.
///
/// Widgets should take colours from `Theme.of(context).colorScheme` or
/// `context.gssms` (see [GssmsColors]). The static colour constants below are
/// brightness-blind light-theme values kept for PDF output and for screens
/// not yet migrated; do not add new UI usages of them.
class AppTheme {
  // Brand Colors (Railway / Steel / Blue palette)
  static const Color primaryBlue = Color(0xFF0F4C81);
  static const Color primaryDark = Color(0xFF0A2540);
  static const Color accentOrange = Color(0xFFE05638);
  static const Color backgroundLight = Color(0xFFF4F6F9);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color surfaceCard = Color(0xFFFAFCFE);
  static const Color textDark = Color(0xFF1E293B);

  /// Outdoor-readable muted text (WCAG AA on `backgroundLight` / `surfaceWhite`).
  static const Color textMuted = Color(0xFF475569);

  /// Muted text for dark surfaces (≈7:1 on `primaryDark` / `textDark`).
  /// Use [mutedText] in widgets so secondary copy stays readable in both
  /// themes instead of hard-coding [textMuted].
  static const Color textMutedDark = Color(0xFF94A3B8);

  /// Brightness-aware secondary text colour.
  static Color mutedText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? textMutedDark
          : textMuted;
  static const Color borderGrey = Color(0xFFE2E8F0);
  static const Color successGreen = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);

  /// Dark amber for text on amber-tinted surfaces (warningAmber itself
  /// fails contrast there).
  static const Color warningAmberDark = Color(0xFF92400E);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFFF1F1);
  static const Color errorBorder = Color(0xFFFECACA);
  static const Color surfaceMuted = Color(0xFFF1F5F9);

  /// Dark-theme app bar: one step above the dark scaffold, never pure black.
  static const Color appBarDark = Color(0xFF101A2C);

  /// Dark-theme page background (slate, not black).
  static const Color scaffoldDark = Color(0xFF0B1220);

  /// Dark-theme card / sheet / dialog surface.
  static const Color surfaceDark = Color(0xFF151E2E);

  // Semantic status (severity / operational state)
  static const Color statusCritical = Color(0xFFDC2626);
  static const Color statusHigh = Color(0xFFEA580C);
  static const Color statusMedium = Color(0xFFD97706);
  static const Color statusLow = Color(0xFF64748B);
  static const Color statusSuccess = Color(0xFF059669);

  // Module identity — Inspections and Assets must not share a colour.
  // Resolve for the active theme with `context.moduleColor(...)`.
  static const Color moduleDashboard = primaryBlue;
  static const Color moduleMaintenance = Color(0xFF6D4C9F);
  static const Color moduleComplaints = accentOrange;
  static const Color moduleInspections = Color(0xFF0F766E);
  static const Color moduleAssets = Color(0xFF1D4ED8);
  static const Color moduleReports = Color(0xFFB45309);
  static const Color moduleEnergy = Color(0xFF3730A3);

  // Aliases
  static const Color railwayBlue = primaryBlue;
  static const Color railwayGreen = successGreen;
  static const Color textPrimary = textDark;
  static const Color textSecondary = textMuted;

  /// P1-6 type scale. 14sp is the floor for text on interactive controls;
  /// [TextTheme.labelSmall] (12) and [TextTheme.bodySmall] (13) are metadata
  /// only.
  static const TextTheme textScale = TextTheme(
    headlineSmall: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.45),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45),
    bodySmall: TextStyle(fontSize: 13, height: 1.4),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
  );

  static ThemeData get lightTheme => _theme(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          secondary: accentOrange,
          surface: surfaceWhite,
          error: const Color(0xFFB91C1C),
          brightness: Brightness.light,
        ),
        tokens: GssmsColors.light,
        scaffoldBackground: backgroundLight,
        appBarBackground: primaryDark,
        cardColor: surfaceCard,
        inputFill: surfaceWhite,
        labelColor: textMuted,
      );

  /// Deliberately designed dark theme: the primary comes from the seed's
  /// dark tonal palette (a light blue with dark on-primary text) instead of
  /// the light-theme brand blue, which is unreadable on dark surfaces.
  static ThemeData get darkTheme => _theme(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          brightness: Brightness.dark,
        ).copyWith(
          secondary: const Color(0xFFFFB59E),
          onSecondary: const Color(0xFF5C1A08),
          surface: surfaceDark,
          onSurface: GssmsColors.dark.textPrimary,
          onSurfaceVariant: GssmsColors.dark.textSecondary,
          surfaceContainerLowest: scaffoldDark,
          surfaceContainerLow: const Color(0xFF121A29),
          surfaceContainer: surfaceDark,
          surfaceContainerHigh: const Color(0xFF1A2436),
          surfaceContainerHighest: const Color(0xFF212C40),
          outline: GssmsColors.dark.borderStrong,
          outlineVariant: GssmsColors.dark.border,
          error: GssmsColors.dark.danger.solid,
          onError: GssmsColors.dark.danger.onSolid,
        ),
        tokens: GssmsColors.dark,
        scaffoldBackground: scaffoldDark,
        appBarBackground: appBarDark,
        cardColor: surfaceDark,
        inputFill: const Color(0xFF111A29),
        labelColor: textMutedDark,
      );

  static ThemeData _theme({
    required ColorScheme colorScheme,
    required GssmsColors tokens,
    required Color scaffoldBackground,
    required Color appBarBackground,
    required Color cardColor,
    required Color inputFill,
    required Color labelColor,
  }) {
    final brightness = colorScheme.brightness;
    // Start from Material's typography (font family, letter-spacing,
    // baselines) and apply the GSSMS size scale on top, so component styles
    // below (buttons, app bar, chips) inherit the same family as body text.
    final typography = Typography.material2021(colorScheme: colorScheme);
    final themedText = typography.englishLike
        .merge(brightness == Brightness.dark ? typography.white : typography.black)
        .merge(textScale)
        .apply(
          bodyColor: tokens.textPrimary,
          displayColor: tokens.textPrimary,
        );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(GssmsRadius.r8),
    );
    const buttonMinSize = Size(64, GssmsSize.touchTarget);
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r8),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      canvasColor: scaffoldBackground,
      textTheme: themedText,
      extensions: [tokens],
      dividerColor: tokens.border,
      dividerTheme: DividerThemeData(color: tokens.border, space: 1),
      iconTheme: IconThemeData(color: tokens.textSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBackground,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: themedText.titleLarge?.copyWith(color: Colors.white),
      ),
      tabBarTheme: TabBarTheme(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        dividerColor: Colors.transparent,
        labelStyle: themedText.labelMedium,
        unselectedLabelStyle:
            themedText.labelMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      cardTheme: CardTheme(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: brightness == Brightness.light ? 1 : 0,
        margin: const EdgeInsets.symmetric(
          vertical: GssmsSpacing.s8,
          horizontal: GssmsSpacing.s16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r12),
          side: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: GssmsSpacing.s16,
          vertical: GssmsSpacing.s16,
        ),
        border: inputBorder(tokens.borderStrong),
        enabledBorder: inputBorder(tokens.borderStrong),
        disabledBorder: inputBorder(tokens.border),
        focusedBorder: inputBorder(colorScheme.primary, 2),
        errorBorder: inputBorder(colorScheme.error),
        focusedErrorBorder: inputBorder(colorScheme.error, 2),
        labelStyle: TextStyle(color: labelColor),
        floatingLabelStyle: TextStyle(color: colorScheme.primary),
        hintStyle: TextStyle(color: labelColor),
        helperStyle: TextStyle(color: labelColor),
        prefixIconColor: tokens.textSecondary,
        suffixIconColor: tokens.textSecondary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: tokens.border,
          disabledForegroundColor: tokens.textTertiary,
          minimumSize: const Size.fromHeight(GssmsSize.touchTarget),
          shape: buttonShape,
          textStyle: themedText.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinSize,
          shape: buttonShape,
          textStyle: themedText.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.link,
          minimumSize: buttonMinSize,
          shape: buttonShape,
          side: BorderSide(color: tokens.borderStrong),
          textStyle: themedText.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.link,
          minimumSize: const Size(48, GssmsSize.touchTarget),
          textStyle: themedText.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(GssmsSize.touchTarget),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardColor,
        side: BorderSide(color: tokens.borderStrong),
        labelStyle: themedText.labelMedium?.copyWith(color: tokens.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r8),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r16),
        ),
        titleTextStyle:
            themedText.titleLarge?.copyWith(color: tokens.textPrimary),
        contentTextStyle:
            themedText.bodyMedium?.copyWith(color: tokens.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: tokens.borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(GssmsRadius.r16),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r8),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          themedText.labelSmall?.copyWith(color: tokens.textPrimary),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.textSecondary,
        textColor: tokens.textPrimary,
        minVerticalPadding: GssmsSpacing.s12,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: tokens.border,
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: tokens.textSecondary, width: 1.5),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
