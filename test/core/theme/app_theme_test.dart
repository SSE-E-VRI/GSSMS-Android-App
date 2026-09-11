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

  test('warning amber dark token for text on amber tints', () {
    expect(AppTheme.warningAmberDark, const Color(0xFF92400E));
  });

  test('error tint tokens for validation surfaces', () {
    expect(AppTheme.errorLight, const Color(0xFFFFF1F1));
    expect(AppTheme.errorBorder, const Color(0xFFFECACA));
    expect(AppTheme.surfaceMuted, const Color(0xFFF1F5F9));
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

  test('darkTheme uses the seed dark palette, not the light brand blue', () {
    expect(AppTheme.darkTheme.brightness, Brightness.dark);
    // The light brand blue (#0F4C81) is unreadable as text/icons on dark
    // surfaces; the dark primary must come from the seed's dark tones.
    expect(AppTheme.darkTheme.colorScheme.primary, isNot(AppTheme.primaryBlue));
    expect(AppTheme.darkTheme.colorScheme.surface, AppTheme.surfaceDark);
    expect(AppTheme.darkTheme.textTheme.titleLarge?.fontSize, 20);
    expect(AppTheme.darkTheme.appBarTheme.backgroundColor, AppTheme.appBarDark);
    expect(AppTheme.darkTheme.scaffoldBackgroundColor, AppTheme.scaffoldDark);
  });

  test('both themes size buttons to the 48dp touch target', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final size = theme.elevatedButtonTheme.style?.minimumSize?.resolve({});
      expect(size?.height, GssmsSize.touchTarget);
      final textSize = theme.textButtonTheme.style?.minimumSize?.resolve({});
      expect(textSize?.height, GssmsSize.touchTarget);
    }
  });

  test('darkTheme input labels use the dark muted token', () {
    expect(AppTheme.textMutedDark, const Color(0xFF94A3B8));
    expect(
      AppTheme.darkTheme.inputDecorationTheme.labelStyle?.color,
      AppTheme.textMutedDark,
    );
    expect(
      AppTheme.darkTheme.inputDecorationTheme.hintStyle?.color,
      AppTheme.textMutedDark,
    );
    expect(
      AppTheme.lightTheme.inputDecorationTheme.labelStyle?.color,
      AppTheme.textMuted,
    );
  });

  testWidgets('mutedText resolves to textMuted in the light theme',
      (tester) async {
    Color? light;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(builder: (context) {
          light = AppTheme.mutedText(context);
          return const SizedBox();
        }),
      ),
    );
    expect(light, AppTheme.textMuted);
  });

  testWidgets('mutedText resolves to textMutedDark in the dark theme',
      (tester) async {
    Color? dark;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Builder(builder: (context) {
          dark = AppTheme.mutedText(context);
          return const SizedBox();
        }),
      ),
    );
    expect(dark, AppTheme.textMutedDark);
  });
}
