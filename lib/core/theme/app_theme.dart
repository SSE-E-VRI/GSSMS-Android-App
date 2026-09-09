import 'package:flutter/material.dart';

import 'gssms_radius.dart';
import 'gssms_spacing.dart';

export 'gssms_radius.dart';
export 'gssms_spacing.dart';

/// Design tokens and Material 3 theme configuration for GSSMS Mobile.
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
  static const Color borderGrey = Color(0xFFE2E8F0);
  static const Color successGreen = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);

  /// Dark amber for text on amber-tinted surfaces (warningAmber itself
  /// fails contrast there).
  static const Color warningAmberDark = Color(0xFF92400E);
  static const Color errorRed = Color(0xFFEF4444);

  /// Near-black blue used for the dark-theme app bar (tokenized so no raw
  /// literal lives in theme wiring).
  static const Color appBarDark = Color(0xFF020617);

  // Semantic status (severity / operational state)
  static const Color statusCritical = Color(0xFFDC2626);
  static const Color statusHigh = Color(0xFFEA580C);
  static const Color statusMedium = Color(0xFFD97706);
  static const Color statusLow = Color(0xFF64748B);
  static const Color statusSuccess = Color(0xFF059669);

  // Module identity — Inspections and Assets must not share a colour.
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
  /// [TextTheme.labelSmall] (12) is metadata only.
  static const TextTheme textScale = TextTheme(
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
    bodyLarge: TextStyle(fontSize: 16, height: 1.45),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
  );

  static ThemeData get lightTheme => _theme(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          secondary: accentOrange,
          surface: surfaceWhite,
          error: errorRed,
          brightness: Brightness.light,
        ),
        scaffoldBackground: backgroundLight,
        appBarBackground: primaryDark,
        cardColor: surfaceCard,
        inputFill: surfaceWhite,
        textColor: textDark,
      );

  static ThemeData get darkTheme => _theme(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          secondary: accentOrange,
          surface: textDark,
          error: errorRed,
          brightness: Brightness.dark,
        ),
        scaffoldBackground: primaryDark,
        appBarBackground: appBarDark,
        cardColor: textDark,
        inputFill: textDark,
        textColor: surfaceWhite,
      );

  static ThemeData _theme({
    required Brightness brightness,
    required ColorScheme colorScheme,
    required Color scaffoldBackground,
    required Color appBarBackground,
    required Color cardColor,
    required Color inputFill,
    required Color textColor,
  }) {
    final themedText = textScale.apply(
      bodyColor: textColor,
      displayColor: textColor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: themedText,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBackground,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textScale.titleLarge?.copyWith(color: Colors.white),
      ),
      cardTheme: CardTheme(
        color: cardColor,
        elevation: 1,
        margin: const EdgeInsets.symmetric(
          vertical: GssmsSpacing.s8,
          horizontal: GssmsSpacing.s16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r12),
          side: BorderSide(
            color: brightness == Brightness.light
                ? borderGrey
                : borderGrey.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: GssmsSpacing.s16,
          vertical: GssmsSpacing.s16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r8),
          borderSide: const BorderSide(color: borderGrey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r8),
          borderSide: const BorderSide(color: borderGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r8),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r8),
          borderSide: const BorderSide(color: errorRed),
        ),
        labelStyle: const TextStyle(color: textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GssmsRadius.r8),
          ),
          textStyle: textScale.labelLarge?.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
