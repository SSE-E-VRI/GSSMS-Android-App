import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_line_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Failed attachment renders warning badge and inline retry button triggering retry callback',
      (tester) async {
    LineAttachment? retriedAttachment;

    const failedAttachment = LineAttachment(
      id: -10,
      kind: 'BEFORE',
      localPath: '/tmp/failed_image.jpg',
      syncStatus: OutboxCommandStatus.failed,
      syncError: 'Network 503 Service Unavailable',
      idempotencyKey: 'key_line_att_fail_42',
    );

    const line = MaintenanceRecordLine(
      id: 42,
      itemName: 'Circuit Breaker',
      inspectionPoint: 'Contact Resistance',
      valueType: MaintenanceValueType.text,
      attachments: [failedAttachment],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChecklistLineCard(
                line: line,
                onSave: (_) {},
                onRetryPhoto: (att) async {
                  retriedAttachment = att;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Expand the attachments section
    await tester.tap(find.byKey(const Key('line_42_attachments_toggle')));
    await tester.pumpAndSettle();

    // Thumbnail and failed badge are displayed
    expect(find.byKey(const Key('line_attachment_thumb_key_line_att_fail_42')), findsOneWidget);
    expect(find.byTooltip('failed'), findsOneWidget);

    // Inline Retry button is rendered
    final retryFinder = find.byKey(const Key('retry_attachment_key_line_att_fail_42'));
    expect(retryFinder, findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Tap retry button
    await tester.tap(retryFinder);
    await tester.pumpAndSettle();

    expect(retriedAttachment, isNotNull);
    expect(retriedAttachment!.idempotencyKey, 'key_line_att_fail_42');
  });
}
