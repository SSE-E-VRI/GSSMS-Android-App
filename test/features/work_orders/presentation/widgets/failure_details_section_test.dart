import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/failure_details_section.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

void main() {
  group('FailureDetailsSection', () {
    const options = [
      FailureCodeOption(id: 1, code: 'MECH-01', description: 'Bearing seizure'),
      FailureCodeOption(id: 2, code: 'ELEC-02', description: 'Coil burnout'),
    ];

    testWidgets('renders Optional badge when requiresFailureDetails is false',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          const FailureDetailsSection(
            requiresFailureDetails: false,
            assetCriticality: 'LOW',
            failureCodeOptions: options,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Optional'), findsOneWidget);
      expect(find.text('LOW'), findsOneWidget);
      expect(find.byKey(const Key('iso55000_mandatory_badge')), findsNothing);
      expect(find.textContaining('ISO 55000 compliance requires'), findsNothing);
      expect(find.text('Failure Code'), findsOneWidget);
      expect(find.text('RESTORED TIME'), findsOneWidget);
    });

    testWidgets(
        'renders ISO 55000 Mandatory badge, info banner and required asterisks',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          const FailureDetailsSection(
            requiresFailureDetails: true,
            assetCriticality: 'CRITICAL',
            failureCodeOptions: options,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('iso55000_mandatory_badge')), findsOneWidget);
      expect(find.text('ISO 55000 Mandatory'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(
        find.textContaining('ISO 55000 compliance requires'),
        findsOneWidget,
      );
      expect(find.text('Failure Code *'), findsOneWidget);
      expect(find.text('RESTORED TIME *'), findsOneWidget);
    });

    testWidgets('triggers onFailureCodeChanged when dropdown option selected',
        (tester) async {
      int? selected;
      await tester.pumpWidget(
        _harness(
          FailureDetailsSection(
            requiresFailureDetails: true,
            assetCriticality: 'CRITICAL',
            failureCodeOptions: options,
            onFailureCodeChanged: (val) => selected = val,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dropdown = find.byKey(const Key('failure_code_dropdown'));
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      final option = find.text('ELEC-02: Coil burnout').last;
      await tester.tap(option, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(selected, 2);
    });

    testWidgets('triggers onRestoredTimeChanged with current time on Set to Now',
        (tester) async {
      DateTime? restored;
      await tester.pumpWidget(
        _harness(
          FailureDetailsSection(
            requiresFailureDetails: true,
            assetCriticality: 'HIGH',
            failureCodeOptions: options,
            onRestoredTimeChanged: (dt) => restored = dt,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final setToNow = find.byKey(const Key('set_to_now_button'));
      expect(setToNow, findsOneWidget);
      await tester.tap(setToNow);
      await tester.pumpAndSettle();

      expect(restored, isNotNull);
      expect(
        DateTime.now().difference(restored!).inSeconds.abs(),
        lessThan(5),
      );
    });

    testWidgets('displays error messages when provided', (tester) async {
      await tester.pumpWidget(
        _harness(
          const FailureDetailsSection(
            requiresFailureDetails: true,
            assetCriticality: 'CRITICAL',
            failureCodeOptions: options,
            failureCodeError: 'Failure Code is mandatory.',
            restoredTimeError: 'Restored Time is mandatory.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Failure Code is mandatory.'), findsOneWidget);
      expect(find.text('Restored Time is mandatory.'), findsOneWidget);
    });
  });
}
