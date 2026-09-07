import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/verification_workspace_controller.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/verification_workspace_state.dart';
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

    test('setDateRange re-fetches with date_from/date_to and keeps status filter', () async {
      when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => testOrders);
      when(
        () => mockRepo.fetchWorkOrders(
          dateFrom: '2026-09-01',
          dateTo: '2026-09-07',
        ),
      ).thenAnswer((_) async => [testOrders[0]]);

      final controller = container.read(workOrderListControllerProvider.notifier);
      await controller.fetchWorkOrders();
      controller.setStatusFilter(WorkOrderStatus.assigned);

      await controller.setDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 7));

      verify(
        () => mockRepo.fetchWorkOrders(
          dateFrom: '2026-09-01',
          dateTo: '2026-09-07',
        ),
      ).called(1);
      final state = container.read(workOrderListControllerProvider) as WorkOrderListLoaded;
      expect(state.dateFrom, DateTime(2026, 9, 1));
      expect(state.dateTo, DateTime(2026, 9, 7));
      expect(state.selectedStatusFilter, WorkOrderStatus.assigned);
      expect(state.workOrders.length, 1);
    });

    // Regression: WorkOrderViewSet.get_queryset reads zone_id/division_id/
    // depot_id/station_id WITH the `_id` suffix — unlike Complaints/
    // Inspections, which use bare depot/division/zone. Pins the distinction.
    test('setOrgScope sends zone_id/division_id/depot_id/station_id', () async {
      when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => testOrders);
      when(
        () => mockRepo.fetchWorkOrders(zoneId: 1, divisionId: 2, depotId: 9, stationId: 4),
      ).thenAnswer((_) async => [testOrders[0]]);

      final controller = container.read(workOrderListControllerProvider.notifier);
      await controller.fetchWorkOrders();
      await controller.setOrgScope(
        const OrgScopeSelection(zoneId: 1, divisionId: 2, depotId: 9, stationId: 4),
      );

      verify(
        () => mockRepo.fetchWorkOrders(zoneId: 1, divisionId: 2, depotId: 9, stationId: 4),
      ).called(1);
      final state = container.read(workOrderListControllerProvider) as WorkOrderListLoaded;
      expect(state.orgScope, const OrgScopeSelection(zoneId: 1, divisionId: 2, depotId: 9, stationId: 4));
    });

    // Regression: retrying/changing filters after a failure used to read
    // `previous` only from a *Loaded state — an *Error state has no such
    // filters, so a retry after a transient failure silently reset date
    // range and org scope back to defaults with no indication.
    test('filters survive a retry issued from an error state', () async {
      when(() => mockRepo.fetchWorkOrders(depotId: 9)).thenAnswer((_) async => testOrders);
      when(() => mockRepo.fetchWorkOrders(
            depotId: 9,
            dateFrom: '2026-09-01',
            dateTo: '2026-09-07',
          )).thenAnswer((_) async => testOrders);

      final controller = container.read(workOrderListControllerProvider.notifier);
      await controller.setOrgScope(const OrgScopeSelection(depotId: 9));
      await controller.setDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 7));

      final loaded = container.read(workOrderListControllerProvider) as WorkOrderListLoaded;
      expect(loaded.orgScope.depotId, 9);
      expect(loaded.dateFrom, DateTime(2026, 9, 1));

      // A transient failure on the next fetch (e.g. a pull-to-refresh
      // hitting a network blip) must not lose those already-applied filters.
      when(() => mockRepo.fetchWorkOrders(
            depotId: 9,
            dateFrom: '2026-09-01',
            dateTo: '2026-09-07',
          )).thenThrow(Exception('network blip'));
      await controller.fetchWorkOrders(forceRefresh: true);
      expect(container.read(workOrderListControllerProvider), isA<WorkOrderListError>());

      when(() => mockRepo.fetchWorkOrders(
            depotId: 9,
            dateFrom: '2026-09-01',
            dateTo: '2026-09-07',
          )).thenAnswer((_) async => testOrders);
      await controller.fetchWorkOrders(forceRefresh: true);

      final state = container.read(workOrderListControllerProvider) as WorkOrderListLoaded;
      expect(state.orgScope.depotId, 9);
      expect(state.dateFrom, DateTime(2026, 9, 1));
      expect(state.dateTo, DateTime(2026, 9, 7));
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

    test('a slower save for one line does not clobber a faster save for another',
        () async {
      const twoLineRecord = MaintenanceRecord(
        id: 50,
        workOrderId: 1,
        lines: [
          MaintenanceRecordLine(
            id: 101,
            itemName: 'Check Voltage',
            assetCategory: 'Electrical',
          ),
          MaintenanceRecordLine(
            id: 102,
            itemName: 'Check Current',
            assetCategory: 'Electrical',
          ),
        ],
      );
      when(() => mockRepo.fetchMaintenanceRecord(50))
          .thenAnswer((_) async => twoLineRecord);

      // Line 101's request resolves only after line 102's does, simulating
      // two lines saved close together where the responses arrive out of order.
      final line101Completer = Completer<void>();
      when(() => mockRepo.submitChecklistLine(50, any(that: containsPair('line_id', 101))))
          .thenAnswer((_) => line101Completer.future);
      when(() => mockRepo.submitChecklistLine(50, any(that: containsPair('line_id', 102))))
          .thenAnswer((_) async {});

      final controller = container.read(checklistControllerProvider(50).notifier);
      await controller.loadRecord();

      final line101Save =
          controller.submitLineObservation(lineId: 101, value: '240V');
      final line102Save =
          controller.submitLineObservation(lineId: 102, value: '5A');

      // Line 102's save completes first and lands in state...
      await line102Save;
      // ...then line 101's save, which started earlier, finally resolves.
      line101Completer.complete();
      await line101Save;

      final state = container.read(checklistControllerProvider(50)) as ChecklistLoaded;
      expect(state.record.lines.firstWhere((l) => l.id == 101).recordedValue, '240V');
      expect(state.record.lines.firstWhere((l) => l.id == 102).recordedValue, '5A',
          reason: 'the later-completing save for line 101 must not discard '
              "line 102's already-applied update");
    });
  });

  group('WorkOrderDetailController assign and verify', () {
    late MockWorkOrderRepository mockRepo;
    late ProviderContainer container;

    const newOrder = WorkOrder(
      id: 1,
      status: WorkOrderStatus.newOrder,
      type: WorkOrderType.preventive,
      title: 'Transformer',
    );
    const assignedOrder = WorkOrder(
      id: 1,
      status: WorkOrderStatus.assigned,
      type: WorkOrderType.preventive,
      title: 'Transformer',
      assignedToId: 4,
      assignedToName: 'tech_ramesh',
    );
    const techCompleted = WorkOrder(
      id: 1,
      status: WorkOrderStatus.techCompleted,
      type: WorkOrderType.preventive,
      title: 'Transformer',
    );
    const verifiedOrder = WorkOrder(
      id: 1,
      status: WorkOrderStatus.verified,
      type: WorkOrderType.preventive,
      title: 'Transformer',
      verifiedByName: 'incharge_kumar',
    );

    setUp(() {
      mockRepo = MockWorkOrderRepository();
      when(() => mockRepo.fetchAllowedActions(1)).thenAnswer(
        (_) async => const WorkOrderActionSet(workOrderId: 1),
      );
      when(() => mockRepo.fetchAudit(1)).thenAnswer(
        (_) async => const WorkOrderAudit(workOrderId: 1),
      );
      when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => [assignedOrder]);
      container = ProviderContainer(
        overrides: [workOrderRepositoryProvider.overrideWithValue(mockRepo)],
      );
    });

    tearDown(() => container.dispose());

    Future<void> loadAs(WorkOrder order) async {
      when(() => mockRepo.fetchWorkOrderById(1)).thenAnswer((_) async => order);
      await container.read(workOrderDetailControllerProvider(1).notifier).loadDetail();
    }

    test('assignAndActivate PATCHes then transitions to ASSIGNED', () async {
      await loadAs(newOrder);
      when(() => mockRepo.assignTechnician(1, 4))
          .thenAnswer((_) async => assignedOrder);
      when(() => mockRepo.transitionStatus(1, status: 'ASSIGNED'))
          .thenAnswer((_) async => assignedOrder);

      final ok = await container
          .read(workOrderDetailControllerProvider(1).notifier)
          .assignAndActivate(4);

      expect(ok, isTrue);
      verify(() => mockRepo.assignTechnician(1, 4)).called(1);
      verify(() => mockRepo.transitionStatus(1, status: 'ASSIGNED')).called(1);
      final state = container.read(workOrderDetailControllerProvider(1));
      expect(state, isA<WorkOrderDetailLoaded>());
      expect((state as WorkOrderDetailLoaded).workOrder.status, WorkOrderStatus.assigned);
    });

    test('assignAndActivate does not change-status when the PATCH fails', () async {
      await loadAs(newOrder);
      when(() => mockRepo.assignTechnician(1, 4))
          .thenThrow(Exception('A technician must be assigned'));

      final ok = await container
          .read(workOrderDetailControllerProvider(1).notifier)
          .assignAndActivate(4);

      expect(ok, isFalse);
      verifyNever(() => mockRepo.transitionStatus(any(), status: any(named: 'status')));
      expect(
        container.read(workOrderDetailControllerProvider(1)),
        isA<WorkOrderDetailError>(),
      );
    });

    test('verifyWorkOrder uses the dedicated verify path', () async {
      await loadAs(techCompleted);
      when(() => mockRepo.verifyWorkOrder(1, remarks: 'OK'))
          .thenAnswer((_) async => verifiedOrder);

      final ok = await container
          .read(workOrderDetailControllerProvider(1).notifier)
          .verifyWorkOrder(remarks: 'OK');

      expect(ok, isTrue);
      verify(() => mockRepo.verifyWorkOrder(1, remarks: 'OK')).called(1);
      verifyNever(() => mockRepo.transitionStatus(any(), status: any(named: 'status')));
      final state = container.read(workOrderDetailControllerProvider(1))
          as WorkOrderDetailLoaded;
      expect(state.workOrder.verifiedByName, 'incharge_kumar');
    });

    test('verifyWorkOrder surfaces a WorkOrderDetailError on failure', () async {
      await loadAs(techCompleted);
      when(() => mockRepo.verifyWorkOrder(1, remarks: any(named: 'remarks')))
          .thenThrow(Exception('cannot verify'));

      final ok = await container
          .read(workOrderDetailControllerProvider(1).notifier)
          .verifyWorkOrder(remarks: 'OK');

      expect(ok, isFalse);
      expect(
        container.read(workOrderDetailControllerProvider(1)),
        isA<WorkOrderDetailError>(),
      );
    });
  });

  group('VerificationWorkspaceController', () {
    late MockWorkOrderRepository mockRepo;
    late ProviderContainer container;

    setUp(() {
      mockRepo = MockWorkOrderRepository();
      container = ProviderContainer(
        overrides: [workOrderRepositoryProvider.overrideWithValue(mockRepo)],
      );
    });

    tearDown(() => container.dispose());

    test('load populates the workspace', () async {
      when(() => mockRepo.fetchVerificationWorkspace(1)).thenAnswer(
        (_) async => const VerificationWorkspace(canVerify: true),
      );

      await container
          .read(verificationWorkspaceControllerProvider(1).notifier)
          .load();

      final state = container.read(verificationWorkspaceControllerProvider(1));
      expect(state, isA<VerificationWorkspaceLoaded>());
      expect((state as VerificationWorkspaceLoaded).workspace.canVerify, isTrue);
    });

    test('load surfaces an error without a cache fallback', () async {
      when(() => mockRepo.fetchVerificationWorkspace(1))
          .thenThrow(Exception('forbidden'));

      await container
          .read(verificationWorkspaceControllerProvider(1).notifier)
          .load();

      expect(
        container.read(verificationWorkspaceControllerProvider(1)),
        isA<VerificationWorkspaceError>(),
      );
    });
  });
}
