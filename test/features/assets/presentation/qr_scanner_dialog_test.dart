import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/assets/presentation/widgets/qr_scanner_dialog.dart';

void main() {
  group('QrScannerDialog Widget Tests', () {
    testWidgets('cancels dialog returning null when close button tapped', (tester) async {
      String? returnedCode = 'initial';

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                returnedCode = await showDialog<String>(
                  context: context,
                  builder: (_) => const QrScannerDialog(startInManualMode: true),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cancel_scanner_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel_scanner_button')));
      await tester.pumpAndSettle();

      expect(returnedCode, isNull);
    });

    testWidgets('manual mode accepts typed asset code and returns it on confirm', (tester) async {
      String? returnedCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                returnedCode = await showDialog<String>(
                  context: context,
                  builder: (_) => const QrScannerDialog(startInManualMode: true),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('manual_code_input')), findsOneWidget);
      expect(find.byKey(const Key('confirm_code_lookup_button')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('manual_code_input')),
        'VRI-SS01-HTSTR-2POLE-001',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('confirm_code_lookup_button')));
      await tester.pumpAndSettle();

      expect(returnedCode, equals('VRI-SS01-HTSTR-2POLE-001'));
    });

    testWidgets('toggles between manual entry and camera modes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<String>(
                  context: context,
                  builder: (_) => const QrScannerDialog(startInManualMode: true),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // In manual mode initially
      expect(find.byKey(const Key('manual_code_input')), findsOneWidget);
      expect(find.byKey(const Key('toggle_camera_button')), findsOneWidget);

      // Tap toggle to switch to camera view
      await tester.tap(find.byKey(const Key('toggle_camera_button')));
      await tester.pumpAndSettle();

      // Now toggle manual entry button is available
      expect(find.byKey(const Key('toggle_manual_entry_button')), findsOneWidget);

      // Tap toggle to switch back to manual entry
      await tester.tap(find.byKey(const Key('toggle_manual_entry_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('manual_code_input')), findsOneWidget);
    });
  });
}
