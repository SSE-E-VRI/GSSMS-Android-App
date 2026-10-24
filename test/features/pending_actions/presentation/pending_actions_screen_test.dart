import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/maintenance_schedules/domain/models/maintenance_schedule.dart';
import 'package:gssms_mobile/features/pending_actions/presentation/controllers/pending_actions_controllers.dart';
import 'package:gssms_mobile/features/pending_actions/presentation/screens/pending_actions_screen.dart';

import '../../../helpers/fake_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

class _Repo extends Mock implements IWorkOrderRepository {}

/// Serves a fixed, already-loaded state and never hits the network.
class _FakePendingActionsController extends PendingActionsController {
  _FakePendingActionsController(this._initial);
  final PendingActionsState _initial;

  @override
  PendingActionsState build() => _initial;

  @override
  Future<void> load() async {}
}

Widget _app(PendingActionsState state, {IWorkOrderRepository? repo}) => ProviderScope(
      overrides: [
        if (repo != null) workOrderRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(
          () => FakeAuthenticatedController(
              fakeSession(permissions: repo == null ? const ['maintenance.view'] : const ['maintenance.view', 'maintenance.edit'])),
        ),
        pendingActionsControllerProvider
            .overrideWith(() => _FakePendingActionsController(state)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const PendingActionsScreen(),
      ),
    );

MaintenanceSchedule _schedule(int id, String name, {bool isBreakdown = false}) =>
    MaintenanceSchedule.fromJson({
      'id': id,
      'template_name': name,
      'status': 'PENDING',
      'station_name': 'Station $id',
      'is_breakdown': isBreakdown,
    });

void main() {
  testWidgets('legacy due opens skip request without creating a Job Work', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    when(() => repo.getScheduleApprovalState(55)).thenAnswer((_) async => {
      'skip_supported': true, 'status': 'OVERDUE',
    });
    await tester.pumpWidget(_app(PendingActionsState(loading: false, schedules: [
      MaintenanceSchedule.fromJson({'id': 55, 'template_name': 'Legacy PM',
        'status': 'OVERDUE', 'skip_supported': true}),
    ]), repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Skip this due period'));
    await tester.pumpAndSettle();
    expect(find.text('Skip this due period'), findsOneWidget);
    expect(find.byKey(const Key('pm_request_submit')), findsOneWidget);
    verify(() => repo.getScheduleApprovalState(55)).called(1);
    verifyNever(() => repo.requestPmSkip(any(), reasonCode: any(named: 'reasonCode'),
        remarks: any(named: 'remarks')));
  });
  group('Pending Actions Schedules tab', () {
    testWidgets('excludes is_breakdown rows and the badge count matches',
        (tester) async {
      final state = PendingActionsState(
        loading: false,
        schedules: [
          _schedule(1, 'Monthly PM'),
          _schedule(2, 'Breakdown backing', isBreakdown: true),
          _schedule(3, 'Quarterly PM'),
        ],
      );
      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();

      expect(find.text('Schedules (2)'), findsOneWidget);
      expect(find.text('Monthly PM'), findsOneWidget);
      expect(find.text('Quarterly PM'), findsOneWidget);
      expect(find.text('Breakdown backing'), findsNothing);
      expect(find.byKey(const Key('schedule_pending_card_2')), findsNothing);
    });
  });

  group('Pending Actions status chips', () {
    testWidgets('a converted breakdown with wo_status NEW shows Unassigned',
        (tester) async {
      final state = PendingActionsState(
        loading: false,
        complaints: [
          Complaint.fromJson(const {
            'id': 7,
            'title': 'Fan failure',
            'status': 'OPEN',
            'is_converted': true,
            'wo_id': 70,
            'wo_status': 'NEW',
          }),
        ],
      );
      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Breakdowns'));
      await tester.pumpAndSettle();

      expect(find.text('Unassigned'), findsOneWidget);
      expect(find.text('New'), findsNothing);
    });
  });

  group('Pending Actions assignee chips', () {
    testWidgets('converted complaint shows "In Progress (krishna)"',
        (tester) async {
      final state = PendingActionsState(
        loading: false,
        complaints: [
          Complaint.fromJson(const {
            'id': 8,
            'title': 'Pump noise',
            'status': 'OPEN',
            'is_converted': true,
            'wo_id': 80,
            'wo_status': 'IN_PROGRESS',
            'wo_assigned_to_name': 'krishna',
          }),
        ],
      );
      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Breakdowns'));
      await tester.pumpAndSettle();

      expect(find.text('In Progress (krishna)'), findsOneWidget);
    });

    testWidgets('converted complaint without a name keeps the old label',
        (tester) async {
      final state = PendingActionsState(
        loading: false,
        complaints: [
          Complaint.fromJson(const {
            'id': 9,
            'title': 'Pump noise',
            'status': 'OPEN',
            'is_converted': true,
            'wo_id': 81,
            'wo_status': 'IN_PROGRESS',
          }),
        ],
      );
      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Breakdowns'));
      await tester.pumpAndSettle();

      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('In Progress (krishna)'), findsNothing);
    });

    testWidgets('legacy inspection shows "Assigned (krishna)"',
        (tester) async {
      final state = PendingActionsState(
        loading: false,
        inspections: [
          Inspection.fromJson(const {
            'id': 10,
            'title': 'EB Bunk check',
            'status': 'OPEN',
            'is_converted': true,
            'wo_id': 90,
            'wo_status': 'ASSIGNED',
            'wo_assigned_to_name': 'krishna',
            'points_count': 0,
          }),
        ],
      );
      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Inspections'));
      await tester.pumpAndSettle();

      expect(find.text('Assigned (krishna)'), findsOneWidget);
    });

    testWidgets('deficiency with an active remedial shows "Assigned (krishna)"',
        (tester) async {
      final state = PendingActionsState(
        loading: false,
        deficiencies: [
          Deficiency.fromJson(const {
            'id': 11,
            'description': 'Crack on mount',
            'status': 'OPEN',
            'active_remedial_work_order': {
              'id': 91,
              'status': 'ASSIGNED',
              'assigned_to_name': 'krishna',
            },
          }),
        ],
      );
      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Deficiencies'));
      await tester.pumpAndSettle();

      expect(find.text('Assigned (krishna)'), findsOneWidget);
    });
  });
}
