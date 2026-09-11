import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/empty_state_view.dart';

void main() {
  testWidgets('EmptyStateView shows icon, title, body and action',
      (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: EmptyStateView(
            icon: const Icon(Icons.inbox_outlined, size: 48),
            title: 'No complaints found matching criteria.',
            body: 'Try clearing filters or widening the date range.',
            action: ElevatedButton(
              onPressed: () => tapped = true,
              child: const Text('Clear filters'),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('No complaints found matching criteria.'), findsOneWidget);
    expect(
      find.text('Try clearing filters or widening the date range.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Clear filters'));
    expect(tapped, isTrue);
  });

  testWidgets('EmptyStateView body stays readable in the dark theme',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: EmptyStateView(
            icon: Icon(Icons.inbox_outlined, size: 48),
            title: 'No complaints found matching criteria.',
            body: 'Try clearing filters or widening the date range.',
          ),
        ),
      ),
    );

    final body = tester.widget<Text>(
      find.text('Try clearing filters or widening the date range.'),
    );
    expect(body.style?.color, AppTheme.textMutedDark);
  });
}
