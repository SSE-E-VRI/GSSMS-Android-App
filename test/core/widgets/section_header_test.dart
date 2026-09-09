import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/section_header.dart';

void main() {
  testWidgets('SectionHeader shows title and trailing action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SectionHeader(
            title: 'Operational Modules',
            trailing: Text('See all'),
          ),
        ),
      ),
    );

    expect(find.text('Operational Modules'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Operational Modules'));
    expect(text.style?.fontSize, 16);
    expect(text.style?.fontWeight, FontWeight.w600);
  });
}
