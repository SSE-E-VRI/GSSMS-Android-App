import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/narrative_execution_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/narrative_execution.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/narrative_execution_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fake_auth.dart';

class MockNarrativeApi extends Mock implements NarrativeExecutionApiService {}

class MockEvidence extends Mock implements EvidenceService {}

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

const _editable = NarrativeContext(
  workOrderId: 105,
  executionMode: 'COMPLAINT',
  lineCount: 0,
  ticketNumber: 'PNDM-202610-0001',
  title: 'Repair the waiting hall fan',
  description: 'Fan guard loose',
  stationName: 'Pennadam',
  status: 'IN_PROGRESS',
);

const _rectification = NarrativeContext(
  workOrderId: 106,
  executionMode: 'COMPLAINT',
  lineCount: 0,
  ticketNumber: 'TLNR-202610-0003',
  stationName: 'Thalanallur',
  status: 'IN_PROGRESS',
  deficiency: NarrativeDeficiency(
    finding: 'not available / Pending',
    equipment: 'EB Bunk',
    checkpoint: 'Check whether 2 earth pits are available',
    severity: 'Medium',
    sourceTicket: 'TLNR-202608-0015',
    stationName: 'Thalanallur',
  ),
);

/// The checklist the entry point falls back to needs a repository to load from.
MockWorkOrderRepository _repoReturningEmptyRecord() {
  final repo = MockWorkOrderRepository();
  when(() => repo.fetchMaintenanceRecord(80))
      .thenAnswer((_) async => const MaintenanceRecord(id: 80, workOrderId: 105, lines: []));
  return repo;
}

const _photoBefore = NarrativePhoto(id: 1, kind: 'BEFORE', url: '');
const _photoAfter = NarrativePhoto(id: 2, kind: 'AFTER', url: '');

void main() {
  late MockNarrativeApi api;
  late MockEvidence evidence;

  setUpAll(() {
    registerFallbackValue(NarrativePhotoKind.before);
    registerFallbackValue(EvidenceKind.before);
  });

  setUp(() {
    api = MockNarrativeApi();
    evidence = MockEvidence();
    when(() => api.getExecution(any())).thenAnswer((_) async => const NarrativeExecution());
    when(() => api.saveDraft(any(), any())).thenAnswer((_) async => const NarrativeExecution());
  });

  Future<void> pump(WidgetTester tester, NarrativeContext context) async {
    // A tall window so every section of the (lazily built) list is on screen.
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          narrativeExecutionApiServiceProvider.overrideWithValue(api),
          evidenceServiceProvider.overrideWithValue(evidence),
          authControllerProvider.overrideWith(
            () => FakeAuthenticatedController(fakeSession(role: AuthRole.maintenanceStaff)),
          ),
        ],
        child: MaterialApp(home: NarrativeExecutionScreen(recordId: 80, context: context)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('NarrativeExecutionScreen', () {
    testWidgets('shows Job Work details for fix-it work with no deficiency', (tester) async {
      await pump(tester, _editable);
      expect(find.byKey(const Key('job-work-details')), findsOneWidget);
      expect(find.text('Repair the waiting hall fan'), findsOneWidget);
      expect(find.text('Pennadam'), findsOneWidget);
      expect(find.byKey(const Key('deficiency-details')), findsNothing);
    });

    testWidgets('shows the read-only deficiency block for a rectification', (tester) async {
      await pump(tester, _rectification);
      expect(find.byKey(const Key('deficiency-details')), findsOneWidget);
      expect(find.text('not available / Pending'), findsOneWidget);
      expect(find.text('TLNR-202608-0015'), findsOneWidget);
      expect(find.text('Check whether 2 earth pits are available'), findsOneWidget);
      expect(find.text('Deficiency Rectification'), findsOneWidget);
    });

    testWidgets('loads the stored draft into the fields', (tester) async {
      when(() => api.getExecution(105)).thenAnswer((_) async => const NarrativeExecution(
            initialFindings: 'Guard loose',
            actionTaken: 'Re-fixed',
            finalRemarks: 'Done',
            parameters: [NarrativeParameter(parameter: 'Torque', value: '4', unit: 'Nm')],
          ));
      await pump(tester, _editable);
      expect(find.text('Guard loose'), findsOneWidget);
      expect(find.text('Re-fixed'), findsOneWidget);
      expect(find.text('Torque'), findsOneWidget);
    });

    testWidgets('autosaves once after a pause in typing, not per keystroke', (tester) async {
      await pump(tester, _editable);
      await tester.enterText(find.byKey(const Key('narrative-findings')), 'G');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byKey(const Key('narrative-findings')), 'Guard loose');
      verifyNever(() => api.saveDraft(any(), any()));

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      final captured = verify(() => api.saveDraft(105, captureAny())).captured;
      expect(captured, hasLength(1));
      expect((captured.single as Map)['initial_findings'], 'Guard loose');
    });

    testWidgets('does not save on load', (tester) async {
      await pump(tester, _editable);
      await tester.pump(const Duration(seconds: 5));
      verifyNever(() => api.saveDraft(any(), any()));
    });

    testWidgets('an incomplete parameter row is not sent', (tester) async {
      await pump(tester, _editable);
      await tester.ensureVisible(find.byKey(const Key('param-add')));
      await tester.tap(find.byKey(const Key('param-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('param-name-0')), 'Voltage');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      final saved = verify(() => api.saveDraft(105, captureAny())).captured.last as Map;
      expect(saved['parameters'], isEmpty);
      expect(find.textContaining('incomplete rows not saved'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('param-value-0')), '230');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final complete = verify(() => api.saveDraft(105, captureAny())).captured.last as Map;
      expect((complete['parameters'] as List).single, {'parameter': 'Voltage', 'value': '230', 'unit': ''});
    });

    testWidgets('Save progress saves immediately', (tester) async {
      await pump(tester, _editable);
      await tester.enterText(find.byKey(const Key('narrative-action')), 'Re-fixed the guard');
      await tester.tap(find.byKey(const Key('narrative-save')));
      await tester.pumpAndSettle();
      final saved = verify(() => api.saveDraft(105, captureAny())).captured.last as Map;
      expect(saved['action_taken'], 'Re-fixed the guard');
    });

    testWidgets('a failed save shows the error and keeps the typed text', (tester) async {
      when(() => api.saveDraft(any(), any())).thenThrow(Exception('Server said no'));
      await pump(tester, _editable);
      await tester.enterText(find.byKey(const Key('narrative-findings')), 'Guard loose');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('Save failed'), findsOneWidget);
      expect(find.text('Guard loose'), findsOneWidget);
    });

    testWidgets('Sign & submit is blocked until findings, action, photos and outcome exist', (tester) async {
      await pump(tester, _editable);
      await tester.tap(find.byKey(const Key('narrative-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Write the initial assessment and findings.'), findsOneWidget);
      verifyNever(() => api.submit(any(), remarks: any(named: 'remarks'), technicianName: any(named: 'technicianName')));
    });

    testWidgets('submits after saving the final text, then closes', (tester) async {
      when(() => api.getExecution(105)).thenAnswer((_) async => const NarrativeExecution(
            initialFindings: 'Guard loose',
            actionTaken: 'Re-fixed',
            finalRemarks: 'Restored',
            photos: [_photoBefore, _photoAfter],
          ));
      when(() => api.submit(any(), remarks: any(named: 'remarks'), technicianName: any(named: 'technicianName')))
          .thenAnswer((_) async {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            narrativeExecutionApiServiceProvider.overrideWithValue(api),
            evidenceServiceProvider.overrideWithValue(evidence),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(role: AuthRole.maintenanceStaff)),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NarrativeExecutionScreen(recordId: 80, context: _editable),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('narrative-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Submit for verification?'), findsOneWidget);
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      verifyInOrder([
        () => api.saveDraft(105, any()),
        () => api.submit(105, remarks: 'Restored', technicianName: 'Test User'),
      ]);
      // Back on the launching screen.
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('adds a Before photo through the camera and the API', (tester) async {
      when(() => evidence.capture(kind: any(named: 'kind')))
          .thenAnswer((_) async => const EvidenceFile(path: '/tmp/x.jpg', sizeBytes: 1000, kind: EvidenceKind.before));
      when(() => api.uploadPhoto(any(), any(), any())).thenAnswer((_) async => _photoBefore);

      await pump(tester, _editable);
      await tester.ensureVisible(find.byKey(const Key('photo-add-before')));
      await tester.tap(find.byKey(const Key('photo-add-before')));
      await tester.pumpAndSettle();

      verify(() => api.uploadPhoto(105, NarrativePhotoKind.before, '/tmp/x.jpg')).called(1);
    });

    testWidgets('a locked photo has no remove button', (tester) async {
      when(() => api.getExecution(105)).thenAnswer((_) async => const NarrativeExecution(
            photos: [NarrativePhoto(id: 7, kind: 'BEFORE', url: '', locked: true)],
          ));
      await pump(tester, _editable);
      expect(find.byKey(const Key('photo-remove-7')), findsNothing);
    });

    testWidgets('is read-only once the Job Work is no longer in progress', (tester) async {
      await pump(
        tester,
        const NarrativeContext(
          workOrderId: 105,
          executionMode: 'COMPLAINT',
          lineCount: 0,
          ticketNumber: 'PNDM-202610-0001',
          status: 'TECH_COMPLETED',
        ),
      );
      expect(find.byKey(const Key('narrative-submit')), findsNothing);
      expect(find.byKey(const Key('narrative-save')), findsNothing);
      expect(find.textContaining('can be read but not edited'), findsOneWidget);
    });

    testWidgets('shows a retry when the execution cannot be loaded', (tester) async {
      when(() => api.getExecution(any())).thenThrow(Exception('offline'));
      await pump(tester, _editable);
      expect(find.text('Retry'), findsOneWidget);
      when(() => api.getExecution(any())).thenAnswer((_) async => const NarrativeExecution());
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('narrative-findings')), findsOneWidget);
    });
  });

  group('ChecklistScreen entry point', () {
    testWidgets('opens the narrative form for a narrative-mode record', (tester) async {
      when(() => api.getContext(80)).thenAnswer((_) async => _editable);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            narrativeExecutionApiServiceProvider.overrideWithValue(api),
            evidenceServiceProvider.overrideWithValue(evidence),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(role: AuthRole.maintenanceStaff)),
            ),
          ],
          child: const MaterialApp(home: ChecklistScreen(recordId: 80)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NarrativeExecutionScreen), findsOneWidget);
      expect(find.byType(ChecklistFormScreen), findsNothing);
    });

    testWidgets('keeps the checklist when the record already has lines', (tester) async {
      when(() => api.getContext(80)).thenAnswer((_) async => const NarrativeContext(
            workOrderId: 105,
            executionMode: 'COMPLAINT',
            lineCount: 3,
            status: 'IN_PROGRESS',
          ));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            narrativeExecutionApiServiceProvider.overrideWithValue(api),
            workOrderRepositoryProvider.overrideWithValue(_repoReturningEmptyRecord()),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(role: AuthRole.maintenanceStaff)),
            ),
          ],
          child: const MaterialApp(home: ChecklistScreen(recordId: 80)),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(NarrativeExecutionScreen), findsNothing);
      expect(find.byType(ChecklistFormScreen), findsOneWidget);
    });

    testWidgets('falls back to the checklist when the mode cannot be read', (tester) async {
      when(() => api.getContext(80)).thenThrow(Exception('offline'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            narrativeExecutionApiServiceProvider.overrideWithValue(api),
            workOrderRepositoryProvider.overrideWithValue(_repoReturningEmptyRecord()),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(role: AuthRole.maintenanceStaff)),
            ),
          ],
          child: const MaterialApp(home: ChecklistScreen(recordId: 80)),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(NarrativeExecutionScreen), findsNothing);
      expect(find.byType(ChecklistFormScreen), findsOneWidget);
    });
  });
}
