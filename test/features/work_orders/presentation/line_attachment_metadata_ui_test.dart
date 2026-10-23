import '../../../helpers/fake_auth.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_line_card.dart';

/// ME-06: camera rows show Camera + coordinates/accuracy or "Location
/// unavailable"; gallery rows never display a fabricated location.
/// ME-07: deletion has a visible icon while long-press remains.
void main() {
  final cameraWithFix = LineAttachment(
    id: 1,
    kind: 'BEFORE',
    source: 'CAMERA',
    localPath: '/tmp/missing_before.jpg',
    latitude: 12.345,
    longitude: 78.68,
    locationAccuracyM: 8.0,
    locationRecordedAt: DateTime(2026, 10, 20, 6, 0),
    idempotencyKey: 'key_cam_fix',
    syncStatus: OutboxCommandStatus.pending,
  );
  const cameraNoFix = LineAttachment(
    id: 2,
    kind: 'BEFORE',
    source: 'CAMERA',
    localPath: '/tmp/missing_nofix.jpg',
    idempotencyKey: 'key_cam_nofix',
    syncStatus: OutboxCommandStatus.pending,
  );
  const galleryRow = LineAttachment(
    id: 3,
    kind: 'AFTER',
    source: 'GALLERY',
    localPath: '/tmp/missing_gallery.jpg',
    idempotencyKey: 'key_gallery',
    syncStatus: OutboxCommandStatus.pending,
  );

  Future<void> pumpCard(
    WidgetTester tester,
    List<LineAttachment> attachments,
    void Function(LineAttachment att)? onDeletedPhoto,
  ) async {
    final holder = MaintenanceRecordLine(
      id: 42,
      itemName: 'Circuit Breaker',
      valueType: MaintenanceValueType.text,
      attachments: attachments,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => FakeAuthenticatedController(
                fakeSession(permissions: const [
                  'maintenance.view',
                  'maintenance.attachment_add',
                  'maintenance.attachment_delete'
                ]),
              ))
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChecklistLineCard(
                line: holder,
                onSave: (_) {},
                onDeletePhoto: (att) async {
                  onDeletedPhoto?.call(att);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('line_42_attachments_toggle')));
    await tester.pumpAndSettle();
  }

  Future<void> openViewer(WidgetTester tester, LineAttachment att) async {
    await tester
        .tap(find.byKey(Key('line_attachment_thumb_${att.idempotencyKey}')));
    await tester.pumpAndSettle();
  }

  testWidgets('camera row with a fix shows source and coordinates in viewer',
      (tester) async {
    await pumpCard(tester, [cameraWithFix], (_) {});
    await openViewer(tester, cameraWithFix);

    expect(find.textContaining('Camera · Location: 12.34500, 78.68000 (±8 m)'),
        findsOneWidget);
  });

  testWidgets('camera row without a fix shows "Location unavailable"',
      (tester) async {
    await pumpCard(tester, [cameraNoFix], (_) {});
    await openViewer(tester, cameraNoFix);

    expect(
        find.textContaining('Camera · Location unavailable'), findsOneWidget);
  });

  testWidgets('gallery row shows Gallery and no location line at all',
      (tester) async {
    await pumpCard(tester, [galleryRow], (_) {});
    await openViewer(tester, galleryRow);

    expect(find.text('Gallery'), findsOneWidget);
    expect(find.textContaining('location unavailable'), findsNothing);
    expect(find.textContaining('Location:'), findsNothing);
  });

  testWidgets('visible delete icon opens the same confirm dialog and deletes',
      (tester) async {
    LineAttachment? deleted;
    await pumpCard(tester, [cameraWithFix], (att) => deleted = att);

    final deleteButton = find.byKey(const Key('delete_attachment_key_cam_fix'));
    expect(deleteButton, findsOneWidget);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    // The existing confirmed-deletion dialog is used.
    expect(find.text('Delete Photo'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isNotNull);
    expect(deleted!.idempotencyKey, 'key_cam_fix');
  });

  testWidgets('long press still opens the confirm dialog (retained)',
      (tester) async {
    LineAttachment? deleted;
    await pumpCard(tester, [cameraWithFix], (att) => deleted = deleted ?? att);

    await tester
        .longPress(find.byKey(const Key('line_attachment_thumb_key_cam_fix')));
    await tester.pumpAndSettle();
    expect(find.text('Delete Photo'), findsOneWidget);
    expect(
        find.byKey(const Key('delete_attachment_key_cam_fix')), findsOneWidget);
  });
}
