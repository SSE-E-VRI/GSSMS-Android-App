import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';

void main() {
  testWidgets('StatusChip renders label with the success token colour',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: StatusChip(label: 'Verified', tone: GssmsStatusTone.success),
        ),
      ),
    );

    expect(find.text('Verified'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Verified'));
    expect(text.style?.color, AppTheme.statusSuccess);
  });
}
