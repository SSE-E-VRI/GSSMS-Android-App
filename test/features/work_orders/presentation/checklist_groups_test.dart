import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/mutation_outcome.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/utils/gallery_permission.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/group_inclusion_result.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_line_card.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/group_evidence_strip.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fake_auth.dart';

class _MockRepo extends Mock implements IWorkOrderRepository {}

class _MockEvidence extends Mock implements EvidenceService {}

MaintenanceRecordLine _line(
  int id, {
  bool? checkedOut,
  String source = '',
  List<LineAttachment> attachments = const [],
  String? applicability,
  bool isRequired = false,
  String? uniqueId,
}) =>
    MaintenanceRecordLine(
      id: id,
      itemName: 'Battery Bank',
      inspectionPoint: 'Point $id',
      assetCategory: 'Power',
      assetCategoryId: 7,
      assetUniqueId: uniqueId,
      checkedOut: checkedOut,
      checkoutSource: source,
      applicability: applicability,
      isRequired: isRequired,
      attachments: attachments,
    );

MaintenanceRecord _record(List<MaintenanceRecordLine> lines,
        {String status = 'IN_PROGRESS'}) =>
    MaintenanceRecord(id: 55, lines: lines, status: status);

/// Bypasses the real permission_handler platform channel (unmocked in
/// widget tests) — gallery access is always granted here.
class _AlwaysGrantedGalleryPermission extends GalleryPermissionService {
  const _AlwaysGrantedGalleryPermission();

  @override
  Future<bool> request(BuildContext context) async => true;
}

Future<void> _pump(
  WidgetTester tester,
  IWorkOrderRepository repo, {
  List<String> permissions = const [
    'maintenance.view',
    'maintenance.edit',
    'maintenance.attachment_add',
    'maintenance.attachment_delete'
  ],
  EvidenceService? evidence,
  bool pushed = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2412);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheServiceProvider
            .overrideWithValue(InMemoryLocalCacheService()),
        workOrderRepositoryProvider.overrideWithValue(repo),
        if (evidence != null)
          evidenceServiceProvider.overrideWithValue(evidence),
        galleryPermissionServiceProvider
            .overrideWithValue(const _AlwaysGrantedGalleryPermission()),
        authControllerProvider.overrideWith(
          () => FakeAuthenticatedController(
            fakeSession(
                role: AuthRole.maintenanceStaff, permissions: permissions),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: pushed
            ? Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      key: const Key('open_checklist'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ChecklistScreen(recordId: 55),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              )
            : const ChecklistScreen(recordId: 55),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (pushed) {
    await tester.tap(find.byKey(const Key('open_checklist')));
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(EvidenceKind.before);
    registerFallbackValue(ImageSource.camera);
  });

  const groupKey = '7::battery bank';

  testWidgets('one switch covers physical assets and preserves line sources',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async => _record([
          _line(1, checkedOut: true, source: 'SUPERVISOR', uniqueId: 'LIFT-1'),
          _line(2, checkedOut: false, uniqueId: 'LIFT-2'),
        ]));
    when(() => repo.setGroupInclusion(
          55,
          assetCategoryId: any(named: 'assetCategoryId'),
          assetName: any(named: 'assetName'),
          included: any(named: 'included'),
          reason: any(named: 'reason'),
        )).thenAnswer((_) async => const GroupInclusionResult(
          included: true, checkedOut: true, checkoutSource: 'TECHNICIAN',
        ));
    await _pump(tester, repo);
    expect(find.byKey(const Key('group_checkout_$groupKey')), findsOneWidget);
    await tester.tap(find.byKey(const Key('group_checkout_$groupKey')));
    await tester.pumpAndSettle();
    expect(find.text('Checked out'), findsOneWidget);
    expect(find.byType(ChecklistLineCard), findsNWidgets(2));
    expect(find.text('LIFT-1'), findsOneWidget);
    expect(find.text('LIFT-2'), findsOneWidget);
    expect(find.byType(GroupEvidenceStrip), findsNWidgets(2));
  });

  testWidgets('unchecked group hides its lines and explains why',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async =>
        _record([_line(1, checkedOut: false), _line(2, checkedOut: false)]));
    await _pump(tester, repo);

    expect(find.byType(ChecklistLineCard), findsNothing);
    expect(find.textContaining('Not yet checked out'), findsOneWidget);
    expect(find.byKey(const Key('group_checkout_$groupKey')), findsOneWidget);
  });

  testWidgets('checking out calls the API and reveals the lines',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async =>
        _record([_line(1, checkedOut: false), _line(2, checkedOut: false)]));
    when(() => repo.setGroupInclusion(
          55,
          assetCategoryId: any(named: 'assetCategoryId'),
          assetName: any(named: 'assetName'),
          included: any(named: 'included'),
          reason: any(named: 'reason'),
        )).thenAnswer((_) async => const GroupInclusionResult(
          included: true,
          checkedOut: true,
          checkoutSource: 'TECHNICIAN',
        ));
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('group_checkout_$groupKey')));
    await tester.pumpAndSettle();

    verify(() => repo.setGroupInclusion(
          55,
          assetCategoryId: 7,
          assetName: 'Battery Bank',
          included: true,
          reason: null,
        )).called(1);
    expect(find.byType(ChecklistLineCard), findsNWidgets(2));
    expect(find.text('Checked out by technician'), findsOneWidget);
    // Photos are per group, not per line.
    expect(find.byKey(const Key('line_1_attachments_toggle')), findsNothing);
    expect(find.textContaining('Photo Evidence'), findsOneWidget);
  });

  DioException alreadyCheckedOut() => DioException(
        requestOptions: RequestOptions(path: '/group-inclusion/'),
        response: Response(
          requestOptions: RequestOptions(path: '/group-inclusion/'),
          statusCode: 400,
          data: {'error': 'Asset group is already checked out.'},
        ),
        type: DioExceptionType.badResponse,
      );

  testWidgets(
      '"already checked out" re-reads the record and shows the group checked out',
      (tester) async {
    final repo = _MockRepo();
    var reads = 0;
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async {
      reads++;
      return reads == 1
          ? _record([_line(1, checkedOut: false)])
          : _record([_line(1, checkedOut: true, source: 'SUPERVISOR')]);
    });
    when(() => repo.setGroupInclusion(
          55,
          assetCategoryId: any(named: 'assetCategoryId'),
          assetName: any(named: 'assetName'),
          included: any(named: 'included'),
          reason: any(named: 'reason'),
        )).thenThrow(alreadyCheckedOut());
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('group_checkout_$groupKey')));
    await tester.pumpAndSettle();

    expect(find.byType(ChecklistLineCard), findsOneWidget);
    expect(find.textContaining('Could not change group'), findsNothing);
  });

  testWidgets(
      'a partly checked-out group the server still rejects explains what to do',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async =>
        _record([_line(1, checkedOut: false), _line(2, checkedOut: false)]));
    when(() => repo.setGroupInclusion(
          55,
          assetCategoryId: any(named: 'assetCategoryId'),
          assetName: any(named: 'assetName'),
          included: any(named: 'included'),
          reason: any(named: 'reason'),
        )).thenThrow(alreadyCheckedOut());
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('group_checkout_$groupKey')));
    await tester.pumpAndSettle();

    expect(find.byType(ChecklistLineCard), findsNothing);
    expect(find.textContaining('only partly checked out'), findsOneWidget);
  });

  testWidgets('required rows carry no red label; only optional rows are tagged',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async => _record([
          _line(1, checkedOut: true, source: 'SUPERVISOR', isRequired: true),
          _line(2, checkedOut: true, source: 'SUPERVISOR', isRequired: true),
          _line(3, checkedOut: true, source: 'SUPERVISOR'),
        ]));
    await _pump(tester, repo);

    expect(find.byType(ChecklistLineCard), findsNWidgets(3));
    expect(find.text('Required'), findsNothing);
    expect(find.text('Optional'), findsOneWidget);
  });

  testWidgets('no optional tag when no row is explicitly required',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async => _record([
          _line(1, checkedOut: true, source: 'SUPERVISOR'),
          _line(2, checkedOut: true, source: 'SUPERVISOR'),
        ]));
    await _pump(tester, repo);

    expect(find.text('Required'), findsNothing);
    expect(find.text('Optional'), findsNothing);
  });

  testWidgets('Save progress confirms and leaves the checklist',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async =>
        _record([_line(1, checkedOut: true, source: 'SUPERVISOR')]));
    await _pump(tester, repo, pushed: true);

    expect(find.byKey(const Key('save_progress_button')), findsOneWidget);
    expect(find.byKey(const Key('complete_checklist_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('save_progress_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ChecklistScreen), findsNothing);
    expect(find.textContaining('Progress saved'), findsOneWidget);
  });

  testWidgets('Save progress saves a typed edit that is still debouncing',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async =>
        _record([_line(1, checkedOut: true, source: 'SUPERVISOR')]));
    when(() => repo.submitChecklistLine(55, any()))
        .thenAnswer((_) async => MutationOutcome.synced);
    await _pump(tester, repo, pushed: true);

    await tester.enterText(find.byType(TextField).first, 'typed note');
    // Well inside the 800 ms typing delay: nothing saved yet.
    await tester.pump(const Duration(milliseconds: 100));
    verifyNever(() => repo.submitChecklistLine(55, any()));

    await tester.tap(find.byKey(const Key('save_progress_button')));
    await tester.pumpAndSettle();

    verify(() => repo.submitChecklistLine(55, any())).called(1);
    expect(find.byType(ChecklistScreen), findsNothing);
  });

  testWidgets('Save progress stays on the screen when a save fails',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async =>
        _record([_line(1, checkedOut: true, source: 'SUPERVISOR')]));
    when(() => repo.submitChecklistLine(55, any()))
        .thenThrow(Exception('boom'));
    await _pump(tester, repo, pushed: true);

    await tester.enterText(find.byType(TextField).first, 'typed note');
    await tester.tap(find.byKey(const Key('save_progress_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ChecklistScreen), findsOneWidget);
    expect(find.textContaining('could not be saved'), findsOneWidget);
  });

  testWidgets('un-check control is disabled without group_uncheckout',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async =>
        _record([_line(1, checkedOut: true, source: 'TECHNICIAN')]));
    await _pump(tester, repo);

    final sw = tester
        .widget<Switch>(find.byKey(const Key('group_checkout_$groupKey')));
    expect(sw.onChanged, isNull);
  });

  testWidgets('un-check control is enabled with group_uncheckout',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async =>
        _record([_line(1, checkedOut: true, source: 'TECHNICIAN')]));
    await _pump(tester, repo, permissions: const [
      'maintenance.view',
      'maintenance.edit',
      'maintenance.group_uncheckout',
    ]);

    final sw = tester
        .widget<Switch>(find.byKey(const Key('group_checkout_$groupKey')));
    expect(sw.onChanged, isNotNull);
  });

  testWidgets('legacy lines without checked_out render as before',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55))
        .thenAnswer((_) async => _record([_line(1), _line(2)]));
    await _pump(tester, repo);

    expect(find.byType(ChecklistLineCard), findsNWidgets(2));
    expect(find.textContaining('Not yet checked out'), findsNothing);
  });

  testWidgets('group photo strip shows (0/5) and uploads to the first line',
      (tester) async {
    final repo = _MockRepo();
    final evidence = _MockEvidence();
    when(() => repo.fetchMaintenanceRecord(55))
        .thenAnswer((_) async => _record([
              _line(11, checkedOut: true, source: 'TECHNICIAN'),
              _line(12, checkedOut: true, source: 'TECHNICIAN')
            ]));
    when(() => evidence.isStorageNearCap()).thenAnswer((_) async => false);
    when(() => evidence.capture(
          kind: any(named: 'kind'),
          source: any(named: 'source'),
          captureLocation: any(named: 'captureLocation'),
        )).thenAnswer((inv) async => EvidenceFile(
          path: '/tmp/x.jpg',
          sizeBytes: 10,
          kind: inv.namedArguments[#kind] as EvidenceKind,
        ));
    when(() => evidence.discard(any())).thenAnswer((_) async {});
    when(() => repo.uploadLineAttachment(
          55,
          lineId: any(named: 'lineId'),
          kind: any(named: 'kind'),
          imagePath: any(named: 'imagePath'),
          capturedAt: any(named: 'capturedAt'),
          source: any(named: 'source'),
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
          locationAccuracyM: any(named: 'locationAccuracyM'),
          locationRecordedAt: any(named: 'locationRecordedAt'),
        )).thenAnswer((_) async => const LineAttachment(
          id: 900,
          kind: 'BEFORE',
          url: 'https://example.test/x.jpg',
        ));
    await _pump(tester, repo, evidence: evidence);

    await tester.tap(find.byKey(const Key('group_evidence_toggle_11')));
    await tester.pumpAndSettle();
    expect(find.text('Before Photos (0/5)'), findsOneWidget);
    expect(find.text('After Photos (0/5)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('group_11_gallery_before')));
    await tester.pumpAndSettle();

    verify(() => repo.uploadLineAttachment(
          55,
          lineId: 11,
          kind: 'BEFORE',
          imagePath: '/tmp/x.jpg',
          capturedAt: any(named: 'capturedAt'),
          source: 'UNKNOWN',
          latitude: null,
          longitude: null,
          locationAccuracyM: null,
          locationRecordedAt: null,
        )).called(1);
  });

  testWidgets('completion sends remarks as a numbered list', (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55))
        .thenAnswer((_) async => _record([
              const MaintenanceRecordLine(
                id: 1,
                itemName: 'Battery Bank',
                assetCategory: 'Power',
                recordedValue: 'ok',
              ),
            ]));
    when(() => repo.completeMaintenanceRecord(
          55,
          technicianName: any(named: 'technicianName'),
          remarks: any(named: 'remarks'),
          supervisorName: any(named: 'supervisorName'),
          queueOnly: any(named: 'queueOnly'),
        )).thenAnswer((_) async => MutationOutcome.synced);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('complete_checklist_button')));
    await tester.pumpAndSettle();

    // Empty remarks are rejected before any request.
    await tester.tap(find.byKey(const Key('completion_confirm_button')));
    await tester.pumpAndSettle();
    expect(
        find.text('Add at least one remark (10+ characters).'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('completion_remarks_field')), 'alpha');
    await tester.tap(find.byKey(const Key('completion_remarks_add')));
    await tester.pump();
    // The second entry is typed but not added: submit must still include it.
    await tester.enterText(
        find.byKey(const Key('completion_remarks_field')), 'beta');
    await tester.tap(find.byKey(const Key('completion_confirm_button')));
    await tester.pumpAndSettle();

    verify(() => repo.completeMaintenanceRecord(
          55,
          technicianName: any(named: 'technicianName'),
          remarks: '1. alpha\n2. beta',
          supervisorName: any(named: 'supervisorName'),
          queueOnly: false,
        )).called(1);
  });
}
