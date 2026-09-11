import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_line_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestCard({
    required MaintenanceRecordLine line,
    bool isPastTechCompleted = false,
    Future<void> Function(LineAttachment)? onDeletePhoto,
    Future<void> Function(LineAttachment)? onRetryPhoto,
  }) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChecklistLineCard(
              line: line,
              isPastTechCompleted: isPastTechCompleted,
              onSave: (_) {},
              onDeletePhoto: onDeletePhoto,
              onRetryPhoto: onRetryPhoto,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('ChecklistLineCard shows collapsed attachment row and expands on tap',
      (tester) async {
    const line = MaintenanceRecordLine(
      id: 1,
      itemName: 'Transformer Bushing',
      inspectionPoint: 'Check Oil Level',
      valueType: MaintenanceValueType.text,
      attachments: [],
    );

    await tester.pumpWidget(buildTestCard(line: line));
    await tester.pumpAndSettle();

    // Verify collapsed summary row is shown
    expect(find.text('Before 0 · After 0'), findsOneWidget);
    // Before expanding, photo strips are hidden
    expect(find.text('Before Photos (0/3)'), findsNothing);
    expect(find.text('After Photos (0/3)'), findsNothing);

    // Tap to expand
    await tester.tap(find.byKey(const Key('line_1_attachments_toggle')));
    await tester.pumpAndSettle();

    // Now photo strips are visible
    expect(find.text('Before Photos (0/3)'), findsOneWidget);
    expect(find.text('After Photos (0/3)'), findsOneWidget);
  });

  testWidgets('Camera and Gallery buttons have >= 48dp touch targets',
      (tester) async {
    const line = MaintenanceRecordLine(
      id: 1,
      itemName: 'Transformer Bushing',
      inspectionPoint: 'Check Oil Level',
      valueType: MaintenanceValueType.text,
      attachments: [],
    );

    await tester.pumpWidget(buildTestCard(line: line));
    await tester.pumpAndSettle();

    // Expand
    await tester.tap(find.byKey(const Key('line_1_attachments_toggle')));
    await tester.pumpAndSettle();

    final cameraBeforeFinder = find.byKey(const Key('line_1_camera_before'));
    final galleryBeforeFinder = find.byKey(const Key('line_1_gallery_before'));
    final cameraAfterFinder = find.byKey(const Key('line_1_camera_after'));
    final galleryAfterFinder = find.byKey(const Key('line_1_gallery_after'));

    expect(cameraBeforeFinder, findsOneWidget);
    expect(galleryBeforeFinder, findsOneWidget);
    expect(cameraAfterFinder, findsOneWidget);
    expect(galleryAfterFinder, findsOneWidget);

    final camBeforeSize = tester.getSize(cameraBeforeFinder);
    final galBeforeSize = tester.getSize(galleryBeforeFinder);
    final camAfterSize = tester.getSize(cameraAfterFinder);
    final galAfterSize = tester.getSize(galleryAfterFinder);

    expect(camBeforeSize.width, greaterThanOrEqualTo(48.0));
    expect(camBeforeSize.height, greaterThanOrEqualTo(48.0));
    expect(galBeforeSize.width, greaterThanOrEqualTo(48.0));
    expect(galBeforeSize.height, greaterThanOrEqualTo(48.0));
    expect(camAfterSize.width, greaterThanOrEqualTo(48.0));
    expect(camAfterSize.height, greaterThanOrEqualTo(48.0));
    expect(galAfterSize.width, greaterThanOrEqualTo(48.0));
    expect(galAfterSize.height, greaterThanOrEqualTo(48.0));
  });

  testWidgets('Renders thumbnails with sync badges and tap opens fullscreen dialog',
      (tester) async {
    const line = MaintenanceRecordLine(
      id: 1,
      itemName: 'Transformer Bushing',
      inspectionPoint: 'Check Oil Level',
      valueType: MaintenanceValueType.text,
      attachments: [
        LineAttachment(
          id: 101,
          kind: 'BEFORE',
          url: 'https://example.com/bushing_before.jpg',
          syncStatus: OutboxCommandStatus.synced,
          uploadedBy: 'tech_alice',
        ),
        LineAttachment(
          id: -1,
          kind: 'BEFORE',
          localPath: '/tmp/pending_photo.jpg',
          syncStatus: OutboxCommandStatus.pending,
          idempotencyKey: 'key_pending_1',
        ),
        LineAttachment(
          id: -2,
          kind: 'AFTER',
          localPath: '/tmp/failed_photo.jpg',
          syncStatus: OutboxCommandStatus.failed,
          syncError: '500 Server Error',
          idempotencyKey: 'key_failed_1',
        ),
      ],
    );

    await tester.pumpWidget(buildTestCard(line: line));
    await tester.pumpAndSettle();

    // Summary has counts
    expect(find.text('Before 2 · After 1'), findsOneWidget);

    // Expand
    await tester.tap(find.byKey(const Key('line_1_attachments_toggle')));
    await tester.pumpAndSettle();

    // Verify badges (icon + tooltip, never colour alone)
    expect(find.byTooltip('uploaded'), findsOneWidget);
    expect(find.byTooltip('queued'), findsOneWidget);
    expect(find.byTooltip('failed'), findsOneWidget);

    // Verify inline retry button for the failed attachment
    expect(find.byKey(const Key('retry_attachment_key_failed_1')), findsOneWidget);

    // Tap thumbnail -> opens fullscreen dialog
    final syncedThumb = find.byKey(const Key('line_attachment_thumb_101'));
    expect(syncedThumb, findsOneWidget);
    await tester.tap(syncedThumb);
    await tester.pumpAndSettle();

    expect(find.text('BEFORE Photo'), findsOneWidget);
    expect(find.text('By: tech_alice'), findsOneWidget);

    // Close fullscreen dialog
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('By: tech_alice'), findsNothing);
  });

  testWidgets('Long-press on thumbnail triggers delete dialog when pre-TECH_COMPLETED',
      (tester) async {
    LineAttachment? deletedAttachment;
    const line = MaintenanceRecordLine(
      id: 1,
      itemName: 'Transformer Bushing',
      valueType: MaintenanceValueType.text,
      attachments: [
        LineAttachment(
          id: 101,
          kind: 'BEFORE',
          url: 'https://example.com/b1.jpg',
          syncStatus: OutboxCommandStatus.synced,
        ),
      ],
    );

    await tester.pumpWidget(buildTestCard(
      line: line,
      isPastTechCompleted: false,
      onDeletePhoto: (att) async {
        deletedAttachment = att;
      },
    ));
    await tester.pumpAndSettle();

    // Expand
    await tester.tap(find.byKey(const Key('line_1_attachments_toggle')));
    await tester.pumpAndSettle();

    // Long press thumbnail
    await tester.longPress(find.byKey(const Key('line_attachment_thumb_101')));
    await tester.pumpAndSettle();

    // Delete dialog appears
    expect(find.text('Delete Photo'), findsOneWidget);
    expect(find.textContaining('Delete this before photo?'), findsOneWidget);

    // Confirm deletion
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deletedAttachment?.id, 101);
  });

  testWidgets('Long-press on thumbnail blocks deletion when isPastTechCompleted is true',
      (tester) async {
    var deleteCalled = false;
    const line = MaintenanceRecordLine(
      id: 1,
      itemName: 'Transformer Bushing',
      valueType: MaintenanceValueType.text,
      attachments: [
        LineAttachment(
          id: 101,
          kind: 'BEFORE',
          url: 'https://example.com/b1.jpg',
          syncStatus: OutboxCommandStatus.synced,
        ),
      ],
    );

    await tester.pumpWidget(buildTestCard(
      line: line,
      isPastTechCompleted: true,
      onDeletePhoto: (att) async {
        deleteCalled = true;
      },
    ));
    await tester.pumpAndSettle();

    // Expand
    await tester.tap(find.byKey(const Key('line_1_attachments_toggle')));
    await tester.pumpAndSettle();

    // Long press thumbnail
    await tester.longPress(find.byKey(const Key('line_attachment_thumb_101')));
    await tester.pumpAndSettle();

    // Delete is hidden past TECH_COMPLETED: no dialog, no callback.
    expect(find.text('Delete Photo'), findsNothing);
    expect(deleteCalled, isFalse);
    expect(
      find.text('Cannot delete attachments after technician completion.'),
      findsNothing,
    );
  });
}
