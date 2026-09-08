import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/notifications/domain/models/notification_item.dart';
import 'package:gssms_mobile/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/fake_auth.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

void main() {
  group('Notification derivation', () {
    test('an assigned work order raises an assignment alert', () {
      final items = NotificationItem.fromWorkOrder(
        WorkOrder(
          id: 101,
          status: WorkOrderStatus.assigned,
          type: WorkOrderType.preventive,
          ticketNumber: 'VRI-202608-0001',
          title: 'Station Monthly Maintenance',
          stationName: 'Thalanallur',
          dueDate: DateTime(2999, 1, 1),
        ),
        now: DateTime(2026, 8, 22),
      );

      expect(items.length, 1);
      expect(items.single.type, NotificationType.assignment);
      expect(items.single.targetEntityId, 101);
      expect(items.single.message, contains('VRI-202608-0001'));
    });

    test('a returned work order raises rework rather than assignment', () {
      final items = NotificationItem.fromWorkOrder(
        WorkOrder(
          id: 102,
          status: WorkOrderStatus.reworkRequired,
          type: WorkOrderType.corrective,
          ticketNumber: 'VRI-202608-0002',
          dueDate: DateTime(2999, 1, 1),
        ),
        now: DateTime(2026, 8, 22),
      );

      expect(items.map((i) => i.type), [NotificationType.rework]);
    });

    test('a past due date on open work raises an overdue alert', () {
      final items = NotificationItem.fromWorkOrder(
        WorkOrder(
          id: 103,
          status: WorkOrderStatus.inProgress,
          type: WorkOrderType.preventive,
          ticketNumber: 'VRI-202608-0003',
          dueDate: DateTime(2026, 8, 1),
        ),
        now: DateTime(2026, 8, 22),
      );

      expect(items.map((i) => i.type), contains(NotificationType.overdue));
    });

    test('closed work raises nothing, however overdue', () {
      final items = NotificationItem.fromWorkOrder(
        WorkOrder(
          id: 104,
          status: WorkOrderStatus.closed,
          type: WorkOrderType.preventive,
          dueDate: DateTime(2026, 1, 1),
          slaStatus: 'BREACHED',
        ),
        now: DateTime(2026, 8, 22),
      );

      expect(items, isEmpty);
    });

    test('alert ids are stable so read state survives a refresh', () {
      WorkOrder wo() => WorkOrder(
            id: 105,
            status: WorkOrderStatus.assigned,
            type: WorkOrderType.preventive,
            dueDate: DateTime(2999, 1, 1),
          );

      expect(
        NotificationItem.fromWorkOrder(wo(), now: DateTime(2026, 8, 22)).single.id,
        NotificationItem.fromWorkOrder(wo(), now: DateTime(2026, 8, 23)).single.id,
      );
    });
  });

  group('NotificationsScreen Widget Tests', () {
    late MockWorkOrderRepository mockRepo;

    setUp(() {
      mockRepo = MockWorkOrderRepository();
      when(() => mockRepo.fetchWorkOrders()).thenAnswer(
        (_) async => [
          WorkOrder(
            id: 101,
            status: WorkOrderStatus.assigned,
            type: WorkOrderType.preventive,
            ticketNumber: 'VRI-202608-0001',
            title: 'Station Monthly Maintenance',
            dueDate: DateTime(2999, 1, 1),
          ),
          WorkOrder(
            id: 102,
            status: WorkOrderStatus.reworkRequired,
            type: WorkOrderType.corrective,
            ticketNumber: 'VRI-202608-0002',
            title: 'Panel Repair',
            dueDate: DateTime(2999, 1, 1),
          ),
        ],
      );
    });

    testWidgets('renders alerts derived from real work orders', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession()),
            ),
          ],
          child: const MaterialApp(home: NotificationsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Work Order Assigned'), findsOneWidget);
      expect(find.text('Rework Required'), findsOneWidget);
      expect(find.byKey(const Key('notification_item_ASSIGNMENT_101')), findsOneWidget);
      expect(find.byKey(const Key('notification_item_REWORK_102')), findsOneWidget);
    });

    testWidgets('mark all as read updates every alert', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession()),
            ),
          ],
          child: const MaterialApp(home: NotificationsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mark all as read'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotificationsScreen)),
      );
      expect(
        container.read(notificationsListProvider).every((n) => n.isRead),
        isTrue,
      );
    });

    testWidgets('shows an empty state when nothing needs attention',
        (tester) async {
      when(() => mockRepo.fetchWorkOrders()).thenAnswer(
        (_) async => [
          const WorkOrder(
            id: 200,
            status: WorkOrderStatus.closed,
            type: WorkOrderType.preventive,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession()),
            ),
          ],
          child: const MaterialApp(home: NotificationsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No active notifications.'), findsOneWidget);
    });
  });
}
