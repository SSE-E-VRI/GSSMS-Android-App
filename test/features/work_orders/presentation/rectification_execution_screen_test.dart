import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/narrative_execution_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/narrative_execution.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/rectification_execution_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fake_auth.dart';

class MockNarrativeApi extends Mock implements NarrativeExecutionApiService {}

class MockEvidence extends Mock implements EvidenceService {}

const _context = NarrativeContext(
  workOrderId: 120,
  executionMode: 'RECTIFICATION',
  lineCount: 0,
  ticketNumber: 'TLNR-202610-0015',
  stationName: 'Thalanallur',
  status: 'IN_PROGRESS',
);

const _before = NarrativePhoto(id: 1, kind: 'BEFORE', url: '');
const _after = NarrativePhoto(id: 2, kind: 'AFTER', url: '');

RectificationExecution _execution({
  String outcomeOne = '',
  List<NarrativePhoto> photosOne = const [],
}) =>
    RectificationExecution(
      finalRemarks: '',
      items: [
        RectificationItem(
          id: 11,
          asset: 'EB Bunk',
          checkpoint: 'Check wires',
          finding: 'Discoloured',
          severity: 'Medium',
          sourceTicket: 'TLNR-202608-0015',
          outcome: outcomeOne,
          photos: photosOne,
        ),
        const RectificationItem(id: 12, asset: 'Switch Room', checkpoint: 'Numbering', finding: 'Not available'),
      ],
    );

void main() {
  late MockNarrativeApi api;

  setUpAll(() {
    registerFallbackValue(NarrativePhotoKind.before);
  });

  setUp(() {
    api = MockNarrativeApi();
    when(() => api.getRectification(any())).thenAnswer((_) async => _execution());
    when(() => api.saveRectification(any(), finalRemarks: any(named: 'finalRemarks'), items: any(named: 'items')))
        .thenAnswer((_) async {});
  });

  Future<void> pump(WidgetTester tester, {NarrativeContext context = _context}) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          narrativeExecutionApiServiceProvider.overrideWithValue(api),
          evidenceServiceProvider.overrideWithValue(MockEvidence()),
          authControllerProvider.overrideWith(
            () => FakeAuthenticatedController(fakeSession(role: AuthRole.maintenanceStaff)),
          ),
        ],
        child: MaterialApp(home: RectificationExecutionScreen(recordId: 80, context: context)),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('model: per-item blockers follow the backend rules', () {
    const empty = RectificationItem(id: 1, asset: 'A', checkpoint: 'C');
    expect(empty.blockers(), hasLength(3)); // action, outcome, Before photo

    const notRectified = RectificationItem(
      id: 1, asset: 'A', checkpoint: 'C', actionTaken: 'Checked', outcome: 'NOT_RECTIFIED', photos: [_before],
    );
    expect(notRectified.blockers().single, contains('reason'));

    const rectifiedNoAfter = RectificationItem(
      id: 1, asset: 'A', checkpoint: 'C', actionTaken: 'Fixed', outcome: 'RECTIFIED', photos: [_before],
    );
    expect(rectifiedNoAfter.blockers().single, contains('After photo'));

    const done = RectificationItem(
      id: 1, asset: 'A', checkpoint: 'C', actionTaken: 'Fixed', outcome: 'RECTIFIED', photos: [_before, _after],
    );
    expect(done.blockers(), isEmpty);
  });

  test('context chooses the rectification form only without checklist lines', () {
    expect(_context.usesRectificationForm, isTrue);
    expect(_context.usesNarrativeForm, isFalse);
  });

  testWidgets('shows one card per deficiency and the reason field only when not rectified', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('rect-item-11')), findsOneWidget);
    expect(find.byKey(const Key('rect-item-12')), findsOneWidget);
    expect(find.text('EB Bunk — Check wires'), findsOneWidget);
    expect(find.byKey(const Key('rect-reason-11')), findsNothing);

    await tester.tap(find.descendant(
      of: find.byKey(const Key('rect-outcome-11')),
      matching: find.text('Not rectified'),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rect-reason-11')), findsOneWidget);
    expect(find.byKey(const Key('rect-reason-12')), findsNothing);
  });

  testWidgets('autosaves every item after a pause in typing', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('rect-action-11')), 'Replaced wires');
    await tester.pump(const Duration(seconds: 1));
    verifyNever(() => api.saveRectification(any(), finalRemarks: any(named: 'finalRemarks'), items: any(named: 'items')));
    await tester.pump(const Duration(seconds: 2));
    final captured = verify(() => api.saveRectification(
          120,
          finalRemarks: any(named: 'finalRemarks'),
          items: captureAny(named: 'items'),
        )).captured.single as List<Map<String, dynamic>>;
    expect(captured.firstWhere((r) => r['id'] == 11)['action_taken'], 'Replaced wires');
    expect(captured, hasLength(2));
  });

  testWidgets('blocks submit and names the first missing item', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('rect-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('EB Bunk — Check wires: write the action taken.'), findsOneWidget);
    verifyNever(() => api.submitRectification(any(),
        remarks: any(named: 'remarks'), technicianName: any(named: 'technicianName')));
  });

  testWidgets('is read-only once the Job Work is no longer in progress', (tester) async {
    const submitted = NarrativeContext(
      workOrderId: 120,
      executionMode: 'RECTIFICATION',
      lineCount: 0,
      ticketNumber: 'TLNR-202610-0015',
      status: 'TECH_COMPLETED',
    );
    await pump(tester, context: submitted);
    expect(find.byKey(const Key('rect-submit')), findsNothing);
    expect(find.textContaining('can be read but not edited'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('rect-action-11')));
    expect(field.enabled, isFalse);
  });
}
