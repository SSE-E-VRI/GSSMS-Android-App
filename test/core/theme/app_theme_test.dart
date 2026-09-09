import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

void main() {
  test('textMuted meets outdoor WCAG AA token and aliases textSecondary', () {
    expect(AppTheme.textMuted, const Color(0xFF475569));
    expect(AppTheme.textSecondary, AppTheme.textMuted);
  });

  test('Inspections and Assets module tokens are distinct', () {
    expect(AppTheme.moduleInspections, const Color(0xFF0F766E));
    expect(AppTheme.moduleAssets, const Color(0xFF1D4ED8));
    expect(AppTheme.moduleInspections, isNot(AppTheme.moduleAssets));
  });

  test('status tokens match the design-system hex values', () {
    expect(AppTheme.statusCritical, const Color(0xFFDC2626));
    expect(AppTheme.statusHigh, const Color(0xFFEA580C));
    expect(AppTheme.statusMedium, const Color(0xFFD97706));
    expect(AppTheme.statusLow, const Color(0xFF64748B));
    expect(AppTheme.statusSuccess, const Color(0xFF059669));
  });

  test('spacing and radius scales are complete', () {
    expect(GssmsSpacing.s4, 4);
    expect(GssmsSpacing.s8, 8);
    expect(GssmsSpacing.s12, 12);
    expect(GssmsSpacing.s16, 16);
    expect(GssmsSpacing.s20, 20);
    expect(GssmsSpacing.s24, 24);
    expect(GssmsSpacing.s32, 32);
    expect(GssmsRadius.r4, 4);
    expect(GssmsRadius.r8, 8);
    expect(GssmsRadius.r12, 12);
    expect(GssmsRadius.r16, 16);
  });

  test('lightTheme textTheme uses the P1-6 scale', () {
    final theme = AppTheme.lightTheme.textTheme;
    expect(theme.titleLarge?.fontSize, 20);
    expect(theme.titleLarge?.fontWeight, FontWeight.w700);
    expect(theme.titleMedium?.fontSize, 16);
    expect(theme.bodyLarge?.fontSize, 16);
    expect(theme.bodyMedium?.fontSize, 14);
    expect(theme.labelLarge?.fontSize, 14);
    expect(theme.labelSmall?.fontSize, 12);
  });

  test('darkTheme is derived from the same seed tokens', () {
    expect(AppTheme.darkTheme.brightness, Brightness.dark);
    expect(AppTheme.darkTheme.colorScheme.primary, AppTheme.primaryBlue);
    expect(AppTheme.darkTheme.textTheme.titleLarge?.fontSize, 20);
    expect(AppTheme.appBarDark, const Color(0xFF020617));
    expect(AppTheme.darkTheme.appBarTheme.backgroundColor, AppTheme.appBarDark);
  });
}
