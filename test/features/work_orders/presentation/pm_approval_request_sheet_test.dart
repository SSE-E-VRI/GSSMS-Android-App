import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/pm_approval_request.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/pm_approval_request_sheet.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements IWorkOrderRepository {}

const _wo = WorkOrder(
  id: 7,
  status: WorkOrderStatus.assigned,
  type: WorkOrderType.preventive,
  originalScheduleId: 55,
);

const _depotSession = UserSession(
  accessToken: 't',
  username: 'u',
  firstName: 'A',
  lastName: '',
  primaryRole: AuthRole.depotIncharge,
  roles: [AuthRole.depotIncharge],
  permissions: ['maintenance.view', 'maintenance.edit'],
);

Future<void> _pump(
  WidgetTester tester,
  IWorkOrderRepository repo,
  PmApprovalRequestMode mode, {
  List<bool?>? results,
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              final r = await showModalBottomSheet<bool>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => PmApprovalRequestSheet(
                  workOrder: _wo,
                  mode: mode,
                  repository: repo,
                ),
              );
              results?.add(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  late _MockRepo repo;
  setUp(() {
    repo = _MockRepo();
    when(() => repo.getScheduleApprovalState(any())).thenAnswer((_) async => {
      'skip_supported': true, 'obligation_master': 1, 'status': 'IN_PROGRESS',
      'template_locked': false, 'has_pending_approval': false,
    });
  });

  test('canShow gates on role, type, schedule id and status', () {
    expect(PmApprovalRequestSheet.canShow(_wo, _depotSession), isTrue);
    expect(PmApprovalRequestSheet.canShow(_wo, null), isFalse);
    expect(
      PmApprovalRequestSheet.canShow(
        const WorkOrder(
          id: 1,
          status: WorkOrderStatus.inProgress,
          type: WorkOrderType.preventive,
          originalScheduleId: 5,
        ),
        _depotSession,
      ),
      isFalse,
    );
    expect(
      PmApprovalRequestSheet.canShow(
        const WorkOrder(
          id: 1,
          status: WorkOrderStatus.assigned,
          type: WorkOrderType.preventive,
        ),
        _depotSession,
      ),
      isFalse,
    );
    expect(
      PmApprovalRequestSheet.canShow(
        const WorkOrder(
          id: 1,
          status: WorkOrderStatus.assigned,
          type: WorkOrderType.corrective,
          originalScheduleId: 5,
        ),
        _depotSession,
      ),
      isFalse,
    );
  });

  testWidgets('skip: OTHER needs 20 characters, then submits with args',
      (tester) async {
    when(() => repo.requestPmSkip(any(),
            reasonCode: any(named: 'reasonCode'),
            remarks: any(named: 'remarks')))
        .thenAnswer((_) async => const ApprovalRequestSummary(id: 1));
    final results = <bool?>[];
    await _pump(tester, repo, PmApprovalRequestMode.skip, results: results);

    expect(find.text('Skip this due period'), findsOneWidget);
    expect(find.text(PmApprovalRequestSheet.skipInfo), findsOneWidget);

    await tester.tap(find.byKey(const Key('pm_skip_reason')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Other (requires').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('pm_request_remarks')), 'too short');
    await tester.tap(find.byKey(const Key('pm_request_submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 20 characters'), findsOneWidget);
    verifyNever(() => repo.requestPmSkip(any(),
        reasonCode: any(named: 'reasonCode'), remarks: any(named: 'remarks')));

    const long = 'Asset is under overhaul at the workshop';
    await tester.enterText(find.byKey(const Key('pm_request_remarks')), long);
    await tester.tap(find.byKey(const Key('pm_request_submit')));
    await tester.pumpAndSettle();

    verify(() => repo.requestPmSkip(55, reasonCode: 'OTHER', remarks: long))
        .called(1);
    expect(results, [true]);
  });

  testWidgets('skip: default reason needs only non-empty remarks',
      (tester) async {
    when(() => repo.requestPmSkip(any(),
            reasonCode: any(named: 'reasonCode'),
            remarks: any(named: 'remarks')))
        .thenAnswer((_) async => const ApprovalRequestSummary(id: 1));
    await _pump(tester, repo, PmApprovalRequestMode.skip);

    await tester.tap(find.byKey(const Key('pm_request_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Remarks are required'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pm_request_remarks')), 'short');
    await tester.tap(find.byKey(const Key('pm_request_submit')));
    await tester.pumpAndSettle();
    verify(() => repo.requestPmSkip(55,
        reasonCode: 'ASSET_UNAVAILABLE', remarks: 'short')).called(1);
  });

  testWidgets('change: empty alternatives disables submit', (tester) async {
    when(() => repo.getScheduleAlternatives(55))
        .thenAnswer((_) async => const <ScheduleAlternative>[]);
    await _pump(tester, repo, PmApprovalRequestMode.checklistChange);

    expect(find.text('Request Checklist Change'), findsOneWidget);
    expect(find.text(PmApprovalRequestSheet.noAlternatives), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.byKey(const Key('pm_request_submit')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('change: preselects first alternative and submits it',
      (tester) async {
    when(() => repo.getScheduleAlternatives(55)).thenAnswer((_) async => const [
          ScheduleAlternative(id: 11, name: 'Checklist A', scheduleType: 'MONTHLY'),
          ScheduleAlternative(id: 12, name: 'Checklist B', scheduleType: 'MONTHLY'),
        ]);
    when(() => repo.requestChecklistChange(any(),
            maintenanceMasterId: any(named: 'maintenanceMasterId'),
            remarks: any(named: 'remarks')))
        .thenAnswer((_) async => const ApprovalRequestSummary(id: 2));
    final results = <bool?>[];
    await _pump(tester, repo, PmApprovalRequestMode.checklistChange,
        results: results);

    await tester.enterText(find.byKey(const Key('pm_request_remarks')), 'Use B');
    await tester.tap(find.byKey(const Key('pm_request_submit')));
    await tester.pumpAndSettle();

    verify(() => repo.requestChecklistChange(55,
        maintenanceMasterId: 11, remarks: 'Use B')).called(1);
    expect(results, [true]);
  });

  testWidgets('submit error is shown inline and the sheet stays open',
      (tester) async {
    when(() => repo.requestPmSkip(any(),
            reasonCode: any(named: 'reasonCode'),
            remarks: any(named: 'remarks')))
        .thenThrow(Exception('An approval request is already pending.'));
    await _pump(tester, repo, PmApprovalRequestMode.skip);

    await tester.enterText(find.byKey(const Key('pm_request_remarks')), 'x');
    await tester.tap(find.byKey(const Key('pm_request_submit')));
    await tester.pumpAndSettle();

    expect(find.text('An approval request is already pending.'), findsOneWidget);
    expect(find.text('Skip this due period'), findsOneWidget);
  });
  for (final scenario in <String, Map<String, dynamic>>{
    'recorded work': {'template_locked': true},
    'pending approval': {'has_pending_approval': true},
    'unsupported legacy due': {'skip_supported': false},
    'closed due': {'status': 'SKIPPED'},
  }.entries) {
    testWidgets('skip blocked by ${scenario.key}', (tester) async {
      when(() => repo.getScheduleApprovalState(any())).thenAnswer((_) async => {
        'skip_supported': true, 'status': 'OVERDUE',
        ...scenario.value,
      });
      await _pump(tester, repo, PmApprovalRequestMode.skip);
      expect(find.byKey(const Key('pm_schedule_block')), findsOneWidget);
      final submit = tester.widget<FilledButton>(
          find.byKey(const Key('pm_request_submit')));
      expect(submit.onPressed, isNull);
      verifyNever(() => repo.requestPmSkip(any(),
          reasonCode: any(named: 'reasonCode'), remarks: any(named: 'remarks')));
    });
  }
  testWidgets('legacy due is supported without an obligation master', (tester) async {
    when(() => repo.getScheduleApprovalState(any())).thenAnswer((_) async => {
      'skip_supported': true, 'status': 'OVERDUE',
    });
    when(() => repo.requestPmSkip(any(), reasonCode: any(named: 'reasonCode'),
        remarks: any(named: 'remarks')))
        .thenAnswer((_) async => const ApprovalRequestSummary(id: 2));
    await _pump(tester, repo, PmApprovalRequestMode.skip);
    await tester.enterText(find.byKey(const Key('pm_request_remarks')), 'Skip selected period');
    await tester.tap(find.byKey(const Key('pm_request_submit')));
    await tester.pumpAndSettle();
    verify(() => repo.requestPmSkip(55, reasonCode: 'ASSET_UNAVAILABLE',
        remarks: 'Skip selected period')).called(1);
  });
  testWidgets('failed eligibility lookup disables requests', (tester) async {
    when(() => repo.getScheduleApprovalState(any())).thenThrow(Exception('Offline'));
    await _pump(tester, repo, PmApprovalRequestMode.skip);
    expect(find.textContaining('Could not check this due period'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('pm_request_submit'))).onPressed, isNull);
  });

  testWidgets('dark theme shows distinct skip explanation and locked reason', (tester) async {
    when(() => repo.getScheduleApprovalState(any())).thenAnswer((_) async => {
      'skip_supported': true, 'status': 'OVERDUE', 'template_locked': true,
    });
    await _pump(tester, repo, PmApprovalRequestMode.skip, dark: true);
    expect(find.text(PmApprovalRequestSheet.skipInfo), findsOneWidget);
    expect(find.textContaining('retained earlier attempts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
