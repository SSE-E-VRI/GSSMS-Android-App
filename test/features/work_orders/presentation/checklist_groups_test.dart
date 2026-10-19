import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/mutation_outcome.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/group_inclusion_result.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_line_card.dart';
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
}) =>
    MaintenanceRecordLine(
      id: id,
      itemName: 'Battery Bank',
      inspectionPoint: 'Point $id',
      assetCategory: 'Power',
      assetCategoryId: 7,
      checkedOut: checkedOut,
      checkoutSource: source,
      applicability: applicability,
      attachments: attachments,
    );

MaintenanceRecord _record(List<MaintenanceRecordLine> lines,
        {String status = 'IN_PROGRESS'}) =>
    MaintenanceRecord(id: 55, lines: lines, status: status);

Future<void> _pump(
  WidgetTester tester,
  IWorkOrderRepository repo, {
  List<String> permissions = const ['maintenance.view', 'maintenance.edit'],
  EvidenceService? evidence,
}) async {
  tester.view.physicalSize = const Size(1080, 2412);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheServiceProvider.overrideWithValue(InMemoryLocalCacheService()),
        workOrderRepositoryProvider.overrideWithValue(repo),
        if (evidence != null) evidenceServiceProvider.overrideWithValue(evidence),
        authControllerProvider.overrideWith(
          () => FakeAuthenticatedController(
            fakeSession(
                role: AuthRole.maintenanceStaff, permissions: permissions),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ChecklistScreen(recordId: 55),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(EvidenceKind.before);
    registerFallbackValue(ImageSource.camera);
  });

  const groupKey = '7::battery bank';

  testWidgets('unchecked group hides its lines and explains why',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer(
        (_) async => _record([_line(1, checkedOut: false), _line(2, checkedOut: false)]));
    await _pump(tester, repo);

    expect(find.byType(ChecklistLineCard), findsNothing);
    expect(find.textContaining('Not yet checked out'), findsOneWidget);
    expect(find.byKey(const Key('group_checkout_$groupKey')), findsOneWidget);
  });

  testWidgets('checking out calls the API and reveals the lines',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer(
        (_) async => _record([_line(1, checkedOut: false), _line(2, checkedOut: false)]));
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

  testWidgets('un-check control is disabled without group_uncheckout',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer(
        (_) async => _record([_line(1, checkedOut: true, source: 'TECHNICIAN')]));
    await _pump(tester, repo);

    final sw = tester
        .widget<Switch>(find.byKey(const Key('group_checkout_$groupKey')));
    expect(sw.onChanged, isNull);
  });

  testWidgets('un-check control is enabled with group_uncheckout',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer(
        (_) async => _record([_line(1, checkedOut: true, source: 'TECHNICIAN')]));
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
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async =>
        _record([_line(11, checkedOut: true, source: 'TECHNICIAN'), _line(12, checkedOut: true, source: 'TECHNICIAN')]));
    when(() => evidence.isStorageNearCap()).thenAnswer((_) async => false);
    when(() => evidence.capture(
          kind: any(named: 'kind'),
          source: any(named: 'source'),
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
        )).called(1);
  });

  testWidgets('completion sends remarks as a numbered list', (tester) async {
    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(55)).thenAnswer((_) async =>
        _record([
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
    expect(find.text('Add at least one remark (10+ characters).'),
        findsOneWidget);

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
