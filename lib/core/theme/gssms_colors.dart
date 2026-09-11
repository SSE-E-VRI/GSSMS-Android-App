import 'package:flutter/material.dart';

/// One semantic tone (success, warning, …) resolved for the active theme.
///
/// [foreground] is for text/icons drawn on [background] (a tint) or on the
/// normal card surface; [border] outlines tinted containers; [solid] and
/// [onSolid] are for filled badges and buttons. Every fg/bg pair meets WCAG AA
/// (4.5:1) — `test/core/theme/gssms_colors_test.dart` measures it.
@immutable
class GssmsTonePalette {
  const GssmsTonePalette({
    required this.foreground,
    required this.background,
    required this.border,
    required this.solid,
    required this.onSolid,
  });

  final Color foreground;
  final Color background;
  final Color border;
  final Color solid;
  final Color onSolid;

  static GssmsTonePalette lerp(GssmsTonePalette a, GssmsTonePalette b, double t) {
    return GssmsTonePalette(
      foreground: Color.lerp(a.foreground, b.foreground, t)!,
      background: Color.lerp(a.background, b.background, t)!,
      border: Color.lerp(a.border, b.border, t)!,
      solid: Color.lerp(a.solid, b.solid, t)!,
      onSolid: Color.lerp(a.onSolid, b.onSolid, t)!,
    );
  }
}

/// Semantic status tones. The UI maps API values (e.g. `TECH_COMPLETED`) to a
/// tone; the tone never feeds back into an API payload.
enum GssmsTone { success, warning, danger, info, neutral, accent }

/// GSSMS semantic colour tokens, resolved per brightness.
///
/// Screens read these through `context.gssms` instead of the brightness-blind
/// `AppTheme.*` constants, so one widget renders correctly in both themes.
@immutable
class GssmsColors extends ThemeExtension<GssmsColors> {
  const GssmsColors({
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.link,
    required this.border,
    required this.borderStrong,
    required this.surfaceInset,
    required this.surfaceRaised,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.neutral,
    required this.accent,
  });

  /// Body and title text.
  final Color textPrimary;

  /// Labels, captions, secondary metadata (AA on every surface).
  final Color textSecondary;

  /// Lowest-emphasis metadata; still AA at 12sp on cards.
  final Color textTertiary;

  /// Brand-coloured text and icons (references, links). Distinct from
  /// `colorScheme.primary` in dark mode, where the brand blue is too dark.
  final Color link;

  final Color border;
  final Color borderStrong;

  /// Recessed boxes inside a card (description wells, read-only values).
  final Color surfaceInset;

  /// Sticky bars that float above content (bottom action bars, filter strips).
  final Color surfaceRaised;

  final GssmsTonePalette success;
  final GssmsTonePalette warning;
  final GssmsTonePalette danger;
  final GssmsTonePalette info;
  final GssmsTonePalette neutral;

  /// Orange — "in progress"/high-priority emphasis, the GSSMS accent.
  final GssmsTonePalette accent;

  GssmsTonePalette tone(GssmsTone tone) {
    switch (tone) {
      case GssmsTone.success:
        return success;
      case GssmsTone.warning:
        return warning;
      case GssmsTone.danger:
        return danger;
      case GssmsTone.info:
        return info;
      case GssmsTone.neutral:
        return neutral;
      case GssmsTone.accent:
        return accent;
    }
  }

  static const GssmsColors light = GssmsColors(
    textPrimary: Color(0xFF1E293B),
    textSecondary: Color(0xFF475569),
    textTertiary: Color(0xFF5B6B80),
    link: Color(0xFF0F4C81),
    border: Color(0xFFE2E8F0),
    borderStrong: Color(0xFFCBD5E1),
    surfaceInset: Color(0xFFF1F5F9),
    surfaceRaised: Color(0xFFFFFFFF),
    success: GssmsTonePalette(
      foreground: Color(0xFF047857),
      background: Color(0xFFECFDF5),
      border: Color(0xFFA7F3D0),
      solid: Color(0xFF047857),
      onSolid: Color(0xFFFFFFFF),
    ),
    warning: GssmsTonePalette(
      foreground: Color(0xFF92400E),
      background: Color(0xFFFFFBEB),
      border: Color(0xFFFCD34D),
      solid: Color(0xFFB45309),
      onSolid: Color(0xFFFFFFFF),
    ),
    danger: GssmsTonePalette(
      foreground: Color(0xFFB91C1C),
      background: Color(0xFFFEF2F2),
      border: Color(0xFFFECACA),
      solid: Color(0xFFB91C1C),
      onSolid: Color(0xFFFFFFFF),
    ),
    info: GssmsTonePalette(
      foreground: Color(0xFF1D4ED8),
      background: Color(0xFFEFF6FF),
      border: Color(0xFFBFDBFE),
      solid: Color(0xFF1D4ED8),
      onSolid: Color(0xFFFFFFFF),
    ),
    neutral: GssmsTonePalette(
      foreground: Color(0xFF475569),
      background: Color(0xFFF1F5F9),
      border: Color(0xFFCBD5E1),
      solid: Color(0xFF475569),
      onSolid: Color(0xFFFFFFFF),
    ),
    accent: GssmsTonePalette(
      foreground: Color(0xFFC2410C),
      background: Color(0xFFFFF7ED),
      border: Color(0xFFFED7AA),
      solid: Color(0xFFC2410C),
      onSolid: Color(0xFFFFFFFF),
    ),
  );

  /// Slate-based dark palette: no pure black, no pure-white body text, tints
  /// dark enough that tone foregrounds keep AA contrast on them.
  static const GssmsColors dark = GssmsColors(
    textPrimary: Color(0xFFE2E8F0),
    textSecondary: Color(0xFFA7B4C7),
    textTertiary: Color(0xFF94A3B8),
    link: Color(0xFF93C5FD),
    border: Color(0xFF2A3649),
    borderStrong: Color(0xFF3B4A61),
    surfaceInset: Color(0xFF0F1828),
    surfaceRaised: Color(0xFF1A2436),
    success: GssmsTonePalette(
      foreground: Color(0xFF6EE7B7),
      background: Color(0xFF0F2E25),
      border: Color(0xFF1F5A47),
      solid: Color(0xFF34D399),
      onSolid: Color(0xFF052E1F),
    ),
    warning: GssmsTonePalette(
      foreground: Color(0xFFFCD34D),
      background: Color(0xFF33260A),
      border: Color(0xFF6B4F12),
      solid: Color(0xFFFBBF24),
      onSolid: Color(0xFF2E1F03),
    ),
    danger: GssmsTonePalette(
      foreground: Color(0xFFFCA5A5),
      background: Color(0xFF3A1418),
      border: Color(0xFF7F1D1D),
      solid: Color(0xFFF87171),
      onSolid: Color(0xFF2D0A0A),
    ),
    info: GssmsTonePalette(
      foreground: Color(0xFF93C5FD),
      background: Color(0xFF0F2440),
      border: Color(0xFF1E3A8A),
      solid: Color(0xFF60A5FA),
      onSolid: Color(0xFF0B1B33),
    ),
    neutral: GssmsTonePalette(
      foreground: Color(0xFFCBD5E1),
      background: Color(0xFF1E293B),
      border: Color(0xFF334155),
      solid: Color(0xFF94A3B8),
      onSolid: Color(0xFF0F172A),
    ),
    accent: GssmsTonePalette(
      foreground: Color(0xFFFDBA74),
      background: Color(0xFF3A1D0C),
      border: Color(0xFF7C2D12),
      solid: Color(0xFFFB923C),
      onSolid: Color(0xFF2B1206),
    ),
  );

  @override
  GssmsColors copyWith({
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? link,
    Color? border,
    Color? borderStrong,
    Color? surfaceInset,
    Color? surfaceRaised,
    GssmsTonePalette? success,
    GssmsTonePalette? warning,
    GssmsTonePalette? danger,
    GssmsTonePalette? info,
    GssmsTonePalette? neutral,
    GssmsTonePalette? accent,
  }) {
    return GssmsColors(
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      link: link ?? this.link,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      surfaceInset: surfaceInset ?? this.surfaceInset,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
      accent: accent ?? this.accent,
    );
  }

  @override
  GssmsColors lerp(ThemeExtension<GssmsColors>? other, double t) {
    if (other is! GssmsColors) return this;
    return GssmsColors(
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      link: Color.lerp(link, other.link, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      surfaceInset: Color.lerp(surfaceInset, other.surfaceInset, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      success: GssmsTonePalette.lerp(success, other.success, t),
      warning: GssmsTonePalette.lerp(warning, other.warning, t),
      danger: GssmsTonePalette.lerp(danger, other.danger, t),
      info: GssmsTonePalette.lerp(info, other.info, t),
      neutral: GssmsTonePalette.lerp(neutral, other.neutral, t),
      accent: GssmsTonePalette.lerp(accent, other.accent, t),
    );
  }
}

extension GssmsThemeContext on BuildContext {
  /// Semantic colour tokens for the active theme. Falls back by brightness so
  /// widgets pumped under a bare `MaterialApp` (tests) still resolve.
  GssmsColors get gssms {
    final theme = Theme.of(this);
    return theme.extension<GssmsColors>() ??
        (theme.brightness == Brightness.dark
            ? GssmsColors.dark
            : GssmsColors.light);
  }

  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;

  /// Module identity colours (Complaints orange, Inspections teal, …) are
  /// tuned for light surfaces; in dark mode lift them toward white so icons
  /// keep ≥3:1 against dark cards while staying recognisably the same hue.
  Color moduleColor(Color base) =>
      isDarkTheme ? Color.lerp(base, Colors.white, 0.45)! : base;
}
