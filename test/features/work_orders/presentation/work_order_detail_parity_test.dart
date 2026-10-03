import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/job_work_report_repository.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/job_work_report_screen.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fake_auth.dart';

class _MockRepo extends Mock implements IWorkOrderRepository {}

class _MockReportRepo extends Mock implements JobWorkReportRepository {}

Future<void> _pump(
  WidgetTester tester,
  WorkOrder wo,
  UserSession session, {
  List<Override> extraOverrides = const [],
}) async {
  final repo = _MockRepo();
  when(() => repo.fetchWorkOrderById(wo.id)).thenAnswer((_) async => wo);
  when(() => repo.fetchAllowedActions(wo.id)).thenAnswer(
    (_) async => WorkOrderActionSet(
      workOrderId: wo.id,
      currentStatus: 'ASSIGNED',
      allowed: const [],
    ),
  );
  when(() => repo.fetchAudit(wo.id))
      .thenAnswer((_) async => WorkOrderAudit(workOrderId: wo.id));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workOrderRepositoryProvider.overrideWithValue(repo),
        authControllerProvider
            .overrideWith(() => FakeAuthenticatedController(session)),
        ...extraOverrides,
      ],
      child: MaterialApp(home: WorkOrderDetailScreen(workOrderId: wo.id)),
    ),
  );
  await tester.pumpAndSettle();
}

WorkOrder _wo({
  WorkOrderStatus status = WorkOrderStatus.assigned,
  int? scheduleId = 5,
  String? executionMode,
}) =>
    WorkOrder(
      id: 101,
      status: status,
      type: WorkOrderType.preventive,
      title: 'Monthly PM',
      assignedToId: 9,
      assignedToName: 'tech_ramesh',
      originalScheduleId: scheduleId,
      executionMode: executionMode,
    );

void main() {
  setUpAll(() => registerFallbackValue(_wo()));

  testWidgets('assigned PM Job Work shows reassign + request items',
      (tester) async {
    await _pump(tester, _wo(), fakeSession());
    await tester.tap(find.byKey(const Key('work_order_overflow_menu')));
    await tester.pumpAndSettle();
    expect(find.text('Reassign technician'), findsOneWidget);
    expect(find.text('Request PM skip'), findsOneWidget);
    expect(find.text('Request checklist change'), findsOneWidget);
    expect(find.byKey(const Key('pre_start_panel')), findsOneWidget);
  });

  testWidgets('in-progress Job Work has no overflow menu', (tester) async {
    await _pump(tester, _wo(status: WorkOrderStatus.inProgress), fakeSession());
    expect(find.byKey(const Key('work_order_overflow_menu')), findsNothing);
    expect(find.byKey(const Key('pre_start_panel')), findsNothing);
  });

  testWidgets('technician sees no overflow menu', (tester) async {
    await _pump(
      tester,
      _wo(),
      fakeSession(role: AuthRole.maintenanceStaff),
    );
    expect(find.byKey(const Key('work_order_overflow_menu')), findsNothing);
    expect(find.byKey(const Key('pre_start_panel')), findsNothing);
  });

  testWidgets('complaint-mode Job Work does not show the pre-START panel',
      (tester) async {
    await _pump(tester, _wo(executionMode: 'COMPLAINT'), fakeSession());
    expect(find.byKey(const Key('pre_start_panel')), findsNothing);
  });

  group('View Report entry', () {
    UserSession tech() => fakeSession(
          role: AuthRole.maintenanceStaff,
          userId: 9,
        );

    testWidgets('assigned technician sees View Report and it opens the report',
        (tester) async {
      final reportRepo = _MockReportRepo();
      when(() => reportRepo.load(any())).thenAnswer(
        (_) async => LoadedJobWorkReport(
          report: ChecklistJobWorkReport.empty(
              _wo(status: WorkOrderStatus.techCompleted)),
          photos: const {},
        ),
      );
      await _pump(
        tester,
        _wo(status: WorkOrderStatus.techCompleted),
        tech(),
        extraOverrides: [
          jobWorkReportRepositoryProvider.overrideWithValue(reportRepo),
        ],
      );
      expect(find.byKey(const Key('action_view_report')), findsOneWidget);
      await tester.tap(find.byKey(const Key('action_view_report')));
      await tester.pumpAndSettle();
      expect(find.byType(JobWorkReportScreen), findsOneWidget);
    });

    testWidgets('depot incharge does not see View Report', (tester) async {
      await _pump(
        tester,
        _wo(status: WorkOrderStatus.techCompleted),
        fakeSession(userId: 9),
      );
      expect(find.byKey(const Key('action_view_report')), findsNothing);
    });

    testWidgets('in-progress Job Work has no View Report for the technician',
        (tester) async {
      await _pump(tester, _wo(status: WorkOrderStatus.inProgress), tech());
      expect(find.byKey(const Key('action_view_report')), findsNothing);
    });
  });
}
