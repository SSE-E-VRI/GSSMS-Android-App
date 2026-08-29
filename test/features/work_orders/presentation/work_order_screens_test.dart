import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

    testWidgets('WorkOrderListScreen renders work order card and filter chips', (tester) async {
      when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => testOrders);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: WorkOrderListScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Work Orders'), findsOneWidget);
      expect(find.byKey(const Key('filter_chip_assigned')), findsOneWidget);
      expect(find.text('WO #101'), findsOneWidget);
      expect(find.text('Monthly Transformer Inspection'), findsOneWidget);
      expect(find.text('tech_ramesh'), findsOneWidget);
    });

    testWidgets('WorkOrderDetailScreen renders details and action button', (tester) async {
      when(() => mockRepo.fetchWorkOrderById(101)).thenAnswer((_) async => testOrders[0]);
      when(() => mockRepo.fetchAllowedActions(101)).thenAnswer(
        (_) async => const WorkOrderActionSet(
          workOrderId: 101,
          currentStatus: 'ASSIGNED',
          allowed: [
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
          ],
          child: const MaterialApp(
            home: WorkOrderDetailScreen(workOrderId: 101),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Work Order #101'), findsOneWidget);
      expect(find.text('Asset & Location Details'), findsOneWidget);
      expect(find.text('TR-01'), findsOneWidget);
      expect(find.byKey(const Key('action_start_execution')), findsOneWidget);
      // The transition offered comes from the server, not from the viewer's role.
      expect(find.byKey(const Key('action_on_hold')), findsOneWidget);
      expect(find.byKey(const Key('work_order_audit_timeline')), findsOneWidget);
      expect(find.text('New → Assigned'), findsOneWidget);
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
          ],
          child: const MaterialApp(
            home: ChecklistScreen(recordId: 55),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Checklist #55'), findsOneWidget);
      expect(find.text('Check Transformer Oil Level'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.byKey(const Key('complete_checklist_button')), findsOneWidget);
    });
  });
}
