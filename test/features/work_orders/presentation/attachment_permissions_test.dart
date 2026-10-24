import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/fake_auth.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/group_evidence_strip.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_line_card.dart';

class _Repo extends Mock implements IWorkOrderRepository {}

class _Evidence extends Mock implements EvidenceService {}

class _ChangingAuth extends AuthController {
  _ChangingAuth(this.session);
  final UserSession session;
  @override
  AuthState build() => Authenticated(session);
  void replace(UserSession value) {
    state = Authenticated(value);
  }
}

const _add = 'maintenance.attachment_add';
const _delete = 'maintenance.attachment_delete';
const _photo =
    LineAttachment(id: 9, kind: 'BEFORE', idempotencyKey: 'server-photo');
const _line =
    MaintenanceRecordLine(id: 11, itemName: 'EB Bunk', attachments: [_photo]);
const _record = MaintenanceRecord(
    id: 55, workOrderId: 12, status: 'IN_PROGRESS', lines: [_line]);

void main() {
  group('Attachment permission contract', () {
    test('maintenance.edit is never a substitute for attachment permission',
        () {
      final session =
          fakeSession(permissions: ['maintenance.view', 'maintenance.edit']);
      expect(canAddChecklistAttachment(session), isFalse);
      expect(canDeleteChecklistAttachment(session), isFalse);
      expect(canAddChecklistAttachment(null), isFalse);
      expect(canDeleteChecklistAttachment(null), isFalse);
    });
    test('upload and delete are independent and match allowed backend roles',
        () {
      const accepted = {
        AuthRole.superAdmin,
        AuthRole.zrAdmin,
        AuthRole.divAdmin,
        AuthRole.depotIncharge,
        AuthRole.depotUser,
        AuthRole.divHqUser,
        AuthRole.maintenanceStaff
      };
      for (final role in AuthRole.values) {
        final addOnly = fakeSession(role: role, permissions: [_add]);
        final deleteOnly = fakeSession(role: role, permissions: [_delete]);
        expect(canAddChecklistAttachment(addOnly), accepted.contains(role),
            reason: role.name);
        expect(canDeleteChecklistAttachment(addOnly), isFalse);
        expect(
            canDeleteChecklistAttachment(deleteOnly), accepted.contains(role),
            reason: role.name);
        expect(canAddChecklistAttachment(deleteOnly), isFalse);
      }
    });
  });

  Future<ProviderContainer> pumpPhotos(
    WidgetTester tester, {
    required List<String> permissions,
    bool grouped = true,
    bool locked = false,
  }) async {
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(
          () => _ChangingAuth(fakeSession(permissions: permissions))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
                child: grouped
                    ? GroupEvidenceStrip(
                        recordId: 55,
                        holder: _line,
                        isPastTechCompleted: locked)
                    : ChecklistLineCard(
                        line: _line,
                        isPastTechCompleted: locked,
                        onSave: (_) {})),
          )),
    ));
    await tester.pumpAndSettle();
    if (!grouped) {
      await tester.tap(find.byKey(const Key('line_11_attachments_toggle')));
      await tester.pumpAndSettle();
    }
    return container;
  }

  for (final grouped in [true, false]) {
    final label = grouped ? 'asset-group evidence' : 'per-line evidence';
    final camera =
        Key(grouped ? 'group_11_camera_before' : 'line_11_camera_before');
    final gallery =
        Key(grouped ? 'group_11_gallery_before' : 'line_11_gallery_before');
    testWidgets(
        '$label disables capture without attachment permission and keeps viewing',
        (tester) async {
      await pumpPhotos(tester,
          permissions: ['maintenance.view', 'maintenance.edit'],
          grouped: grouped);
      expect(tester.widget<IconButton>(find.byKey(camera)).onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(gallery)).onPressed, isNull);
      expect(find.byKey(const Key('delete_attachment_server-photo')),
          findsNothing);
      expect(find.byKey(const Key('line_attachment_thumb_server-photo')),
          findsOneWidget);
      expect(find.text('Photo upload is unavailable with your current access.'),
          findsOneWidget);
    });
    testWidgets('$label upload permission does not grant deletion',
        (tester) async {
      await pumpPhotos(tester, permissions: [_add], grouped: grouped);
      expect(
          tester.widget<IconButton>(find.byKey(camera)).onPressed, isNotNull);
      expect(find.byKey(const Key('delete_attachment_server-photo')),
          findsNothing);
    });
    testWidgets('$label delete permission does not grant upload',
        (tester) async {
      await pumpPhotos(tester, permissions: [_delete], grouped: grouped);
      expect(tester.widget<IconButton>(find.byKey(camera)).onPressed, isNull);
      expect(find.byKey(const Key('delete_attachment_server-photo')),
          findsOneWidget);
    });
    testWidgets('$label responds to refreshed and revoked claims',
        (tester) async {
      final container =
          await pumpPhotos(tester, permissions: [], grouped: grouped);
      final auth =
          container.read(authControllerProvider.notifier) as _ChangingAuth;
      auth.replace(fakeSession(permissions: [_add, _delete]));
      await tester.pumpAndSettle();
      expect(
          tester.widget<IconButton>(find.byKey(camera)).onPressed, isNotNull);
      expect(find.byKey(const Key('delete_attachment_server-photo')),
          findsOneWidget);
      auth.replace(fakeSession(permissions: []));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(find.byKey(camera)).onPressed, isNull);
      expect(find.byKey(const Key('delete_attachment_server-photo')),
          findsNothing);
    });
    testWidgets('$label completion lock overrides granted photo permissions',
        (tester) async {
      await pumpPhotos(tester,
          permissions: [_add, _delete], grouped: grouped, locked: true);
      expect(tester.widget<IconButton>(find.byKey(camera)).onPressed, isNull);
      expect(find.byKey(const Key('delete_attachment_server-photo')),
          findsNothing);
    });
  }

  group('Controller upload safety', () {
    late _Repo repo;
    late _Evidence evidence;
    late ProviderContainer container;
    late ChecklistController controller;
    void start(
        {List<String> permissions = const [_add, _delete],
        MaintenanceRecord record = _record}) {
      repo = _Repo();
      evidence = _Evidence();
      when(() => repo.fetchMaintenanceRecord(55))
          .thenAnswer((_) async => record);
      container = ProviderContainer(overrides: [
        workOrderRepositoryProvider.overrideWithValue(repo),
        localCacheServiceProvider
            .overrideWithValue(InMemoryLocalCacheService()),
        evidenceServiceProvider.overrideWithValue(evidence),
        authControllerProvider.overrideWith(() =>
            FakeAuthenticatedController(fakeSession(permissions: permissions))),
      ]);
      addTearDown(container.dispose);
      container.listen(checklistControllerProvider(55), (_, __) {});
      controller = container.read(checklistControllerProvider(55).notifier);
      controller.state = ChecklistLoaded(record: record);
    }

    test('missing photo permission rejects upload before calling repository',
        () async {
      start(permissions: ['maintenance.edit']);
      expect(
          await controller.uploadLineAttachment(
              lineId: 11, kind: 'BEFORE', imagePath: '/photo.jpg'),
          isFalse);
      verifyNever(() => repo.uploadLineAttachment(any(),
          lineId: any(named: 'lineId'),
          kind: any(named: 'kind'),
          imagePath: any(named: 'imagePath')));
    });
    test('wrong record line is rejected before sending an upload', () async {
      start();
      expect(
          await controller.uploadLineAttachment(
              lineId: 999, kind: 'BEFORE', imagePath: '/photo.jpg'),
          isFalse);
      expect((controller.state as ChecklistLoaded).errorMessage,
          contains('does not belong'));
      verifyNever(() => repo.uploadLineAttachment(any(),
          lineId: any(named: 'lineId'),
          kind: any(named: 'kind'),
          imagePath: any(named: 'imagePath')));
    });
    test(
        'server 403 preserves existing photos and local proof with actionable error',
        () async {
      start();
      when(() => repo.uploadLineAttachment(55,
          lineId: 11, kind: 'BEFORE', imagePath: '/photo.jpg')).thenThrow(
        DioException(
            requestOptions:
                RequestOptions(path: '/records/55/lines/11/attachments/'),
            response: Response(
                requestOptions: RequestOptions(path: ''),
                statusCode: 403,
                data: {
                  'detail': 'You do not have permission to perform this action.'
                })),
      );
      expect(
          await controller.uploadLineAttachment(
              lineId: 11, kind: 'BEFORE', imagePath: '/photo.jpg'),
          isFalse);
      final state = controller.state as ChecklistLoaded;
      expect(state.record.lines.single.attachments, [_photo]);
      expect(
          state.errorMessage,
          'Photo upload denied (403). You do not have permission to perform this action.');
      verifyNever(() => evidence.discard(any()));
    });
    test('second upload preserves the specific backend denial', () async {
      start();
      when(() => repo.uploadLineAttachment(55,
          lineId: 11, kind: 'BEFORE', imagePath: '/second.jpg')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/records/55/lines/11/attachments/'),
          response: Response(requestOptions: RequestOptions(path: ''),
            statusCode: 403, data: {'detail': 'This Job Work is assigned to another technician.'}),
        ),
      );
      expect(await controller.uploadLineAttachment(
          lineId: 11, kind: 'BEFORE', imagePath: '/second.jpg'), isFalse);
      final current = controller.state as ChecklistLoaded;
      expect(current.errorMessage,
          'Photo upload denied (403). This Job Work is assigned to another technician.');
      expect(current.record.lines.single.attachments, [_photo]);
      verifyNever(() => evidence.discard(any()));
    });
    test('multiple photos append independently and later rejection preserves them', () async {
      start();
      for (final pair in [(10, 'BEFORE'), (11, 'BEFORE'), (12, 'AFTER'), (13, 'AFTER')]) {
        final path = '/photo_${pair.$1}.jpg';
        when(() => repo.uploadLineAttachment(55,
            lineId: 11, kind: pair.$2, imagePath: path))
            .thenAnswer((_) async => LineAttachment(id: pair.$1, kind: pair.$2));
        expect(await controller.uploadLineAttachment(
            lineId: 11, kind: pair.$2, imagePath: path), isTrue);
      }
      final saved = (controller.state as ChecklistLoaded).record.lines.single.attachments;
      expect(saved.map((a) => a.id), [9, 10, 11, 12, 13]);
      expect(saved.where((a) => a.kind == 'BEFORE').length, 3);
      expect(saved.where((a) => a.kind == 'AFTER').length, 2);
      when(() => repo.uploadLineAttachment(55,
          lineId: 11, kind: 'AFTER', imagePath: '/rejected.jpg')).thenThrow(
        DioException(requestOptions: RequestOptions(path: ''),
          response: Response(requestOptions: RequestOptions(path: ''),
            statusCode: 403, data: '<html>Internal proxy response</html>')),
      );
      expect(await controller.uploadLineAttachment(
          lineId: 11, kind: 'AFTER', imagePath: '/rejected.jpg'), isFalse);
      final current = controller.state as ChecklistLoaded;
      expect(current.record.lines.single.attachments, saved);
      expect(current.errorMessage,
          'Photo upload denied (403). The upload service returned no readable reason.');
      expect(current.errorMessage, isNot(contains('<html>')));
    });
    test('authorized upload sends the open record and correct holder line',
        () async {
      start();
      when(() => repo.uploadLineAttachment(55,
              lineId: 11, kind: 'BEFORE', imagePath: '/photo.jpg'))
          .thenAnswer(
              (_) async => const LineAttachment(id: 10, kind: 'BEFORE'));
      expect(
          await controller.uploadLineAttachment(
              lineId: 11, kind: 'BEFORE', imagePath: '/photo.jpg'),
          isTrue);
      verify(() => repo.uploadLineAttachment(55,
          lineId: 11, kind: 'BEFORE', imagePath: '/photo.jpg')).called(1);
    });
    test('server denial during deletion preserves the local proof file',
        () async {
      start();
      when(() => repo.deleteLineAttachment(55, lineId: 11, attachmentId: 9))
          .thenThrow(
        DioException(
            requestOptions: RequestOptions(path: '/attachments/9/'),
            response: Response(
                requestOptions: RequestOptions(path: ''), statusCode: 403)),
      );
      expect(
          await controller.deleteLineAttachment(
              lineId: 11, attachmentId: 9, localPath: '/photo.jpg'),
          isFalse);
      verifyNever(() => evidence.discard(any()));
      expect(
          (controller.state as ChecklistLoaded).record.lines.single.attachments,
          [_photo]);
    });
    test('mismatched record ID is rejected before uploading', () async {
      start(record: const MaintenanceRecord(id: 56, lines: [_line]));
      expect(
          await controller.uploadLineAttachment(
              lineId: 11, kind: 'BEFORE', imagePath: '/photo.jpg'),
          isFalse);
      verifyNever(() => repo.uploadLineAttachment(any(),
          lineId: any(named: 'lineId'),
          kind: any(named: 'kind'),
          imagePath: any(named: 'imagePath')));
    });
    test('completed records cannot upload despite attachment permission',
        () async {
      start(
          record: const MaintenanceRecord(
              id: 55, status: 'TECH_COMPLETED', lines: [_line]));
      expect(
          await controller.uploadLineAttachment(
              lineId: 11, kind: 'BEFORE', imagePath: '/photo.jpg'),
          isFalse);
      verifyNever(() => repo.uploadLineAttachment(any(),
          lineId: any(named: 'lineId'),
          kind: any(named: 'kind'),
          imagePath: any(named: 'imagePath')));
    });
    test('denied deletion leaves local proof intact', () async {
      start(permissions: [_add]);
      expect(
          await controller.deleteLineAttachment(
              lineId: 11, attachmentId: 9, localPath: '/photo.jpg'),
          isFalse);
      verifyNever(() => repo.deleteLineAttachment(any(),
          lineId: any(named: 'lineId'),
          attachmentId: any(named: 'attachmentId')));
      verifyNever(() => evidence.discard(any()));
    });
  });
}
