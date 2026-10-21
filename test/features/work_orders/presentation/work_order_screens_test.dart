import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_list_screen.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/fake_auth.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

void main() {
  group('WorkOrder Screens Widget Tests', () {
    late MockWorkOrderRepository mockRepo;

    const testOrders = [
      WorkOrder(
        id: 101,
        status: WorkOrderStatus.assigned,
        type: WorkOrderType.preventive,
        title: 'Monthly Transformer Inspection',
        assetName: 'TR-01',
        stationName: 'VRI',
        assignedToName: 'tech_ramesh',
      ),
    ];

    const testRecord = MaintenanceRecord(
      id: 55,
      workOrderId: 101,
      lines: [
        MaintenanceRecordLine(
          id: 301,
          itemName: 'Check Transformer Oil Level',
          assetCategory: 'Substation',
          recordedValue: 'Normal',
        ),
      ],
    );

    setUp(() {
      mockRepo = MockWorkOrderRepository();
    });

    testWidgets('WorkOrderListScreen renders work order card and filter sheet', (tester) async {
      when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => testOrders);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const WorkOrderListScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Job Works'), findsOneWidget);
      expect(find.byKey(const Key('filters_button')), findsOneWidget);
      expect(find.text('Search ticket, title, asset'), findsOneWidget);
      expect(find.text('1 Job Work'), findsOneWidget);
      expect(find.text('WO #101'), findsOneWidget);
      expect(find.text('Monthly Transformer Inspection'), findsOneWidget);
      expect(find.text('tech_ramesh'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Job Work WO #101, status: Assigned, VRI, Monthly Transformer Inspection, assigned to tech_ramesh'),
        findsOneWidget,
      );

      // Open filter bottom sheet
      await tester.tap(find.byKey(const Key('filters_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('date_range_from')), findsOneWidget);
      expect(find.byKey(const Key('date_range_to')), findsOneWidget);
      expect(find.byKey(const Key('wo_status_filter_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('wo_type_filter_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('wo_infra_type_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('wo_infra_name_dropdown')), findsOneWidget);
    });

    testWidgets('WorkOrderListScreen type + infra filters narrow the list via sheet', (tester) async {
      const orders = [
        WorkOrder(
          id: 1,
          status: WorkOrderStatus.assigned,
          type: WorkOrderType.preventive,
          title: 'Station PM',
          stationName: 'VRI',
          infrastructureName: 'VRI Station',
          infrastructureType: 'STATION',
        ),
        WorkOrder(
          id: 2,
          status: WorkOrderStatus.assigned,
          type: WorkOrderType.corrective,
          title: 'LC Gate repair',
          stationName: 'TPJ',
          infrastructureName: 'Gate 12',
          infrastructureType: 'LC_GATE',
        ),
      ];
      when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => orders);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const WorkOrderListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 Job Works'), findsOneWidget);

      // Open filter sheet and select Corrective
      await tester.tap(find.byKey(const Key('filters_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wo_type_filter_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Corrective').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply_filters_button')));
      await tester.pumpAndSettle();

      expect(find.text('WO #2'), findsOneWidget);
      expect(find.text('WO #1'), findsNothing);
      expect(find.text('1 of 2 Job Works'), findsOneWidget);
      expect(find.byKey(const Key('chip_type_filter')), findsOneWidget);

      // Remove type filter chip via its delete icon
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('chip_type_filter')),
          matching: find.byType(Icon),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('WO #1'), findsOneWidget);
      expect(find.text('WO #2'), findsOneWidget);
    });

    testWidgets('WorkOrderListScreen displays overdue styling for past due PM and Unassigned for unassigned', (tester) async {
      final pastDue = DateTime.now().subtract(const Duration(days: 3));
      final orders = [
        WorkOrder(
          id: 10,
          status: WorkOrderStatus.inProgress,
          type: WorkOrderType.preventive,
          title: 'Overdue PM Transformer',
          stationName: 'VRI',
          dueDate: pastDue,
        ),
        WorkOrder(
          id: 20,
          status: WorkOrderStatus.inProgress,
          type: WorkOrderType.corrective,
          title: 'Breakdown Job Work Past Due',
          stationName: 'VRI',
          originalComplaintId: 99,
          dueDate: pastDue,
        ),
      ];
      when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => orders);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const WorkOrderListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Card 10 is overdue PM: shows Overdue text and Unassigned
      expect(find.textContaining('Overdue · due'), findsOneWidget);
      expect(find.text('Unassigned'), findsWidgets);
      // Card 20 is Breakdown: never overdue even if dueDate in past
      expect(find.textContaining('Due '), findsOneWidget);
    });

    testWidgets('WorkOrderDetailScreen renders details and action button', (tester) async {
      when(() => mockRepo.fetchWorkOrderById(101)).thenAnswer((_) async => testOrders[0]);
      when(() => mockRepo.fetchAllowedActions(101)).thenAnswer(
        (_) async => const WorkOrderActionSet(
          workOrderId: 101,
          currentStatus: 'ASSIGNED',
          allowed: [
            WorkOrderAction(
              targetStatus: 'IN_PROGRESS',
              label: 'Start',
              enabled: true,
            ),
            WorkOrderAction(
              targetStatus: 'ON_HOLD',
              label: 'On Hold',
              enabled: true,
              requiresReason: true,
            ),
          ],
        ),
      );
      when(() => mockRepo.fetchAudit(101)).thenAnswer(
        (_) async => const WorkOrderAudit(
          workOrderId: 101,
          ticketNumber: 'VRI-202608-0001',
          events: [
            WorkOrderAuditEvent(
              eventId: 'e1',
              eventType: 'STATUS_CHANGE',
              fromState: 'NEW',
              toState: 'ASSIGNED',
              actor: 'incharge_kumar',
              actorRole: 'DEPOT_INCHARGE',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession()),
            ),
          ],
          child: const MaterialApp(
            home: WorkOrderDetailScreen(workOrderId: 101),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Job Work'), findsOneWidget);
      expect(find.text('WO #101'), findsOneWidget);
      expect(find.text('Asset & Location Details'), findsOneWidget);
      expect(find.text('TR-01'), findsOneWidget);
      expect(find.byKey(const Key('action_start_execution')), findsOneWidget);
      // Start Execution performs IN_PROGRESS via the execute endpoint (which
      // creates the maintenance record); the raw server transition must not
      // be offered as a second, record-less "Start" path.
      expect(find.byKey(const Key('action_in_progress')), findsNothing);
      // The transition offered comes from the server, not from the viewer's role.
      expect(find.byKey(const Key('action_on_hold')), findsOneWidget);
      expect(find.byKey(const Key('work_order_audit_timeline')), findsOneWidget);
      expect(find.text('New → Assigned'), findsOneWidget);
    });

    testWidgets('audit timeline names reassigned technicians and reason',
        (tester) async {
      when(() => mockRepo.fetchWorkOrderById(101)).thenAnswer((_) async => testOrders[0]);
      when(() => mockRepo.fetchAllowedActions(101)).thenAnswer(
        (_) async => const WorkOrderActionSet(
          workOrderId: 101,
          currentStatus: 'ASSIGNED',
          allowed: [],
        ),
      );
      when(() => mockRepo.fetchAudit(101)).thenAnswer(
        (_) async => WorkOrderAudit(
          workOrderId: 101,
          events: [
            WorkOrderAuditEvent.fromJson(const {
              'event_id': 'e2',
              'event_type': 'REASSIGNED',
              'actor': 'incharge_kumar',
              'reason': 'Wrongly assigned',
              'details': {'from_user': 'Alice', 'to_user': 'Bob'},
            }),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession()),
            ),
          ],
          child: const MaterialApp(
            home: WorkOrderDetailScreen(workOrderId: 101),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reassigned'), findsOneWidget);
      expect(find.text('Alice → Bob'), findsOneWidget);
      expect(find.text('Reason: Wrongly assigned'), findsOneWidget);
    });

    testWidgets('WorkOrderDetailScreen offers no transition the server withheld',
        (tester) async {
      when(() => mockRepo.fetchWorkOrderById(101)).thenAnswer((_) async => testOrders[0]);
      when(() => mockRepo.fetchAllowedActions(101)).thenAnswer(
        (_) async => const WorkOrderActionSet(
          workOrderId: 101,
          currentStatus: 'ASSIGNED',
          allowed: [],
          blocked: [
            WorkOrderAction(
              targetStatus: 'VERIFIED',
              label: 'Verify',
              disabledReason: 'Not authorized or conditions not met',
            ),
          ],
        ),
      );
      when(() => mockRepo.fetchAudit(101))
          .thenAnswer((_) async => const WorkOrderAudit(workOrderId: 101));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession()),
            ),
          ],
          child: const MaterialApp(
            home: WorkOrderDetailScreen(workOrderId: 101),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('action_verified')),
        findsNothing,
        reason: 'a blocked transition must not be offered as a button',
      );
    });

    testWidgets('ChecklistScreen renders progress and line observation fields', (tester) async {
      when(() => mockRepo.fetchMaintenanceRecord(55)).thenAnswer((_) async => testRecord);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(
                fakeSession(role: AuthRole.maintenanceStaff),
              ),
            ),
          ],
          child: const MaterialApp(
            home: ChecklistScreen(recordId: 55),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('checklist_overflow_menu')), findsOneWidget);
      expect(find.text('Check Transformer Oil Level'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.byKey(const Key('complete_checklist_button')), findsOneWidget);
    });
  });
}
