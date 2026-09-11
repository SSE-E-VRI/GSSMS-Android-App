import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';

void main() {
  Future<void> pump(WidgetTester tester, ThemeData theme, Widget child) {
    return tester.pumpWidget(
      MaterialApp(theme: theme, home: Scaffold(body: Center(child: child))),
    );
  }

  testWidgets('StatusChip uses the success tone foreground in light theme',
      (tester) async {
    await pump(
      tester,
      AppTheme.lightTheme,
      const StatusChip(label: 'Verified', tone: GssmsTone.success),
    );

    final text = tester.widget<Text>(find.text('Verified'));
    expect(text.style?.color, GssmsColors.light.success.foreground);
  });

  testWidgets('StatusChip resolves tone colours for the dark theme',
      (tester) async {
    await pump(
      tester,
      AppTheme.darkTheme,
      const StatusChip(label: 'Verified', tone: GssmsTone.success),
    );

    final text = tester.widget<Text>(find.text('Verified'));
    expect(text.style?.color, GssmsColors.dark.success.foreground);
  });

  testWidgets('StatusChip shows its icon so meaning is not colour-only',
      (tester) async {
    await pump(
      tester,
      AppTheme.lightTheme,
      const StatusChip(
        label: 'Rework Required',
        tone: GssmsTone.danger,
        icon: Icons.replay,
        semanticPrefix: 'Status',
      ),
    );

    expect(find.byIcon(Icons.replay), findsOneWidget);
    expect(find.bySemanticsLabel('Status: Rework Required'), findsOneWidget);
  });

  testWidgets('filled StatusChip uses the solid/onSolid pair', (tester) async {
    await pump(
      tester,
      AppTheme.lightTheme,
      const StatusChip(label: 'Open', tone: GssmsTone.warning, filled: true),
    );

    final text = tester.widget<Text>(find.text('Open'));
    expect(text.style?.color, GssmsColors.light.warning.onSolid);
  });
}
