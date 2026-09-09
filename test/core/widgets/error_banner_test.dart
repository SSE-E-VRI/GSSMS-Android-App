import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/error_banner.dart';

void main() {
  testWidgets(
      'ErrorBanner shows message and Retry (stale-data-with-banner pattern)',
      (tester) async {
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Column(
            children: [
              ErrorBanner(
                message: 'Could not refresh. Showing last loaded list.',
                onRetry: () => retried = true,
              ),
              const Expanded(child: Text('previous list')),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(
      find.text('Could not refresh. Showing last loaded list.'),
      findsOneWidget,
    );
    expect(find.text('previous list'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
