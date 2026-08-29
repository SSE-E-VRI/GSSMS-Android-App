import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:mocktail/mocktail.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

void main() {
  group('WorkOrderListController Tests', () {
    late MockWorkOrderRepository mockRepo;
    late ProviderContainer container;

    const testOrders = [
      WorkOrder(
        id: 1,
        status: WorkOrderStatus.assigned,
        type: WorkOrderType.preventive,
        title: 'Transformer Maintenance',
        assetName: 'TR-01',
        stationName: 'VRI',
      ),
      WorkOrder(
        id: 2,
        status: WorkOrderStatus.inProgress,
        type: WorkOrderType.breakdown,
        title: 'Signal Failure Repair',
        assetName: 'SIG-02',
        stationName: 'TPJ',
      ),
    ];

    setUp(() {
      mockRepo = MockWorkOrderRepository();
      container = ProviderContainer(
        overrides: [
          workOrderRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('fetchWorkOrders populates loaded state with work orders', () async {
      when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => testOrders);

      final controller = container.read(workOrderListControllerProvider.notifier);
      await controller.fetchWorkOrders();

      final state = container.read(workOrderListControllerProvider);
      expect(state, isA<WorkOrderListLoaded>());
      final loaded = state as WorkOrderListLoaded;
      expect(loaded.workOrders.length, 2);
      expect(loaded.filteredOrders.length, 2);
    });

    test('filter by status correctly reduces filteredOrders', () async {
      when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => testOrders);

      final controller = container.read(workOrderListControllerProvider.notifier);
      await controller.fetchWorkOrders();
      controller.setStatusFilter(WorkOrderStatus.inProgress);

      final state = container.read(workOrderListControllerProvider) as WorkOrderListLoaded;
      expect(state.selectedStatusFilter, WorkOrderStatus.inProgress);
      expect(state.filteredOrders.length, 1);
      expect(state.filteredOrders[0].id, 2);
    });

    test('search query filters work orders by title, asset, and station', () async {
      when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => testOrders);

      final controller = container.read(workOrderListControllerProvider.notifier);
      await controller.fetchWorkOrders();
      controller.setSearchQuery('VRI');

      final state = container.read(workOrderListControllerProvider) as WorkOrderListLoaded;
      expect(state.filteredOrders.length, 1);
      expect(state.filteredOrders[0].stationName, 'VRI');
    });

    test('a forced refresh keeps the active status filter and search query', () async {
      when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => testOrders);

      final controller = container.read(workOrderListControllerProvider.notifier);
      await controller.fetchWorkOrders();
      controller.setStatusFilter(WorkOrderStatus.inProgress);
      controller.setSearchQuery('TPJ');

      await controller.fetchWorkOrders(forceRefresh: true);

      final state = container.read(workOrderListControllerProvider) as WorkOrderListLoaded;
      expect(
        state.selectedStatusFilter,
        WorkOrderStatus.inProgress,
        reason: 'the on-screen filter chip must still match the list',
      );
      expect(state.searchQuery, 'TPJ');
      expect(state.filteredOrders.length, 1);
      expect(state.filteredOrders[0].id, 2);
    });
  });

  group('ChecklistController Tests', () {
    late MockWorkOrderRepository mockRepo;
    late ProviderContainer container;

    const testRecord = MaintenanceRecord(
      id: 50,
      workOrderId: 1,
      lines: [
        MaintenanceRecordLine(
          id: 101,
          itemName: 'Check Voltage',
          assetCategory: 'Electrical',
          recordedValue: '230V',
        ),
      ],
    );

    setUp(() {
      mockRepo = MockWorkOrderRepository();
      container = ProviderContainer(
        overrides: [
          workOrderRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('loadRecord loads lines and subcategories properly', () async {
      when(() => mockRepo.fetchMaintenanceRecord(50)).thenAnswer((_) async => testRecord);

      final controller = container.read(checklistControllerProvider(50).notifier);
      await controller.loadRecord();

      final state = container.read(checklistControllerProvider(50));
      expect(state, isA<ChecklistLoaded>());
      final loaded = state as ChecklistLoaded;
      expect(loaded.record.id, 50);
      expect(loaded.subCategories, ['Electrical']);
    });

    test('submitLineObservation updates line state and calls repository', () async {
      when(() => mockRepo.fetchMaintenanceRecord(50)).thenAnswer((_) async => testRecord);
      when(() => mockRepo.submitChecklistLine(50, any())).thenAnswer((_) async {});

      final controller = container.read(checklistControllerProvider(50).notifier);
      await controller.loadRecord();

      final success = await controller.submitLineObservation(
        lineId: 101,
        value: '240V',
        status: 'OK',
      );

      expect(success, isTrue);
      final state = container.read(checklistControllerProvider(50)) as ChecklistLoaded;
      expect(state.record.lines[0].recordedValue, '240V');
      verify(() => mockRepo.submitChecklistLine(50, any())).called(1);
    });
  });
}
