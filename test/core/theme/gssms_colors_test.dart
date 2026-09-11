import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.red / 255) +
      0.7152 * channel(c.green / 255) +
      0.0722 * channel(c.blue / 255);
  final la = luminance(a);
  final lb = luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const aa = 4.5;
  const aaLargeOrIcon = 3.0;

  final themes = <String, (ThemeData, GssmsColors)>{
    'light': (AppTheme.lightTheme, GssmsColors.light),
    'dark': (AppTheme.darkTheme, GssmsColors.dark),
  };

  themes.forEach((name, pair) {
    final (theme, tokens) = pair;
    final surfaces = <String, Color>{
      'scaffold': theme.scaffoldBackgroundColor,
      'card': theme.cardTheme.color!,
      'inset': tokens.surfaceInset,
      'raised': tokens.surfaceRaised,
    };

    group('$name theme', () {
      test('registers the GssmsColors extension', () {
        expect(theme.extension<GssmsColors>(), tokens);
      });

      surfaces.forEach((surfaceName, surface) {
        test('text tokens meet AA on $surfaceName', () {
          expect(contrast(tokens.textPrimary, surface), greaterThanOrEqualTo(aa));
          expect(contrast(tokens.textSecondary, surface), greaterThanOrEqualTo(aa));
          expect(contrast(tokens.textTertiary, surface), greaterThanOrEqualTo(aa));
          expect(contrast(tokens.link, surface), greaterThanOrEqualTo(aa));
        });
      });

      for (final tone in GssmsTone.values) {
        test('${tone.name} tone meets AA for tinted and solid badges', () {
          final p = tokens.tone(tone);
          expect(contrast(p.foreground, p.background), greaterThanOrEqualTo(aa));
          expect(contrast(p.foreground, theme.cardTheme.color!),
              greaterThanOrEqualTo(aa));
          expect(contrast(p.onSolid, p.solid), greaterThanOrEqualTo(aa));
        });
      }

      test('primary action colours are readable', () {
        final scheme = theme.colorScheme;
        expect(contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(aa));
        // Primary used as an icon/indicator on the card surface.
        expect(contrast(scheme.primary, theme.cardTheme.color!),
            greaterThanOrEqualTo(aaLargeOrIcon));
      });

      test('app bar foreground is readable', () {
        expect(
          contrast(theme.appBarTheme.foregroundColor!,
              theme.appBarTheme.backgroundColor!),
          greaterThanOrEqualTo(aa),
        );
      });

      test('card borders stay visible against the page', () {
        // Cards must remain distinguishable: either the fill or the border
        // separates them from the scaffold.
        final fillDelta =
            contrast(theme.cardTheme.color!, theme.scaffoldBackgroundColor);
        final borderDelta =
            contrast(tokens.border, theme.scaffoldBackgroundColor);
        expect(math.max(fillDelta, borderDelta), greaterThan(1.1));
      });
    });
  });

  test('dark theme avoids pure black and pure-white body text', () {
    expect(AppTheme.darkTheme.scaffoldBackgroundColor, isNot(Colors.black));
    expect(GssmsColors.dark.textPrimary, isNot(Colors.white));
  });

  testWidgets('context.gssms resolves per active theme', (tester) async {
    GssmsColors? resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Builder(builder: (context) {
          resolved = context.gssms;
          return const SizedBox();
        }),
      ),
    );
    expect(resolved, GssmsColors.dark);
  });

  testWidgets('context.gssms falls back by brightness without the extension',
      (tester) async {
    GssmsColors? resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(builder: (context) {
          resolved = context.gssms;
          return const SizedBox();
        }),
      ),
    );
    expect(resolved, GssmsColors.dark);
  });
}
