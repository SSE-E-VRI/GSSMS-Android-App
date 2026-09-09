import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/severity_chip.dart';

void main() {
  testWidgets('SeverityChip maps Critical to statusCritical', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SeverityChip(severity: GssmsSeverity.critical),
        ),
      ),
    );

    expect(find.text('Critical'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Critical'));
    expect(text.style?.color, AppTheme.statusCritical);
  });
}
