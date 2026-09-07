import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:mocktail/mocktail.dart';

class MockWorkOrderApiService extends Mock implements WorkOrderApiService {}
class MockSyncManager extends Mock implements SyncManager {}
class FakeOutboxCommand extends Fake implements OutboxCommand {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeOutboxCommand());
  });

  group('WorkOrderRepository Offline Fallback Tests', () {
    late MockWorkOrderApiService mockApiService;
    late ILocalCacheService cacheService;
    late MockSyncManager mockSyncManager;
    late WorkOrderRepository repository;

    const testOrders = [
      WorkOrder(
        id: 101,
        status: WorkOrderStatus.assigned,
        type: WorkOrderType.preventive,
        title: 'Monthly Transformer Inspection',
      ),
    ];

    setUp(() {
      mockApiService = MockWorkOrderApiService();
      cacheService = InMemoryLocalCacheService();
      mockSyncManager = MockSyncManager();

      repository = WorkOrderRepository(
        mockApiService,
        cacheService: cacheService,
        syncManager: mockSyncManager,
      );
    });

    test('fetchWorkOrders falls back to local cache when network is offline', () async {
      // Seed local cache
      await cacheService.cacheWorkOrders(testOrders);

      // Simulate network connection failure
      when(() => mockApiService.getWorkOrders()).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/work-orders/'),
          type: DioExceptionType.connectionError,
        ),
      );

      final result = await repository.fetchWorkOrders();

      expect(result.length, 1);
      expect(result[0].id, 101);
      expect(result[0].title, 'Monthly Transformer Inspection');
    });

    test('fetchWorkOrderById falls back to cached detail on network timeout', () async {
      await cacheService.cacheWorkOrderDetail(testOrders[0]);

      when(() => mockApiService.getWorkOrder(101)).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/work-orders/101/'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      final result = await repository.fetchWorkOrderById(101);

      expect(result.id, 101);
      expect(result.status, WorkOrderStatus.assigned);
    });

    test('submitChecklistLine enqueues OutboxCommand and succeeds when offline', () async {
      when(() => mockApiService.submitLine(55, any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );

      when(() => mockSyncManager.enqueueCommand(any())).thenAnswer((_) async {});

      await repository.submitChecklistLine(55, {'line_id': 12, 'value': '240V'});

      verify(() => mockSyncManager.enqueueCommand(any())).called(1);
    });

    // Regression: the single cache key only ever holds the last *unfiltered*
    // fetch. Offline-falling-back to it for a filtered request would show
    // stale, wrongly-scoped data with no indication the filters never
    // actually applied.
    test('fetchWorkOrders does NOT fall back to cache when filters are active', () async {
      await cacheService.cacheWorkOrders(testOrders);

      when(() => mockApiService.getWorkOrders(depotId: 9)).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/work-orders/'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.fetchWorkOrders(depotId: 9),
        throwsA(isA<DioException>()),
      );
    });

    // Regression: startExecution used to return workOrderId as a fake
    // record id when queued offline, sending the caller to
    // ChecklistScreen(recordId: workOrderId) against the wrong entity.
    test('startExecution throws StartExecutionQueuedOffline instead of a fake record id', () async {
      when(() => mockApiService.startExecution(101)).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/staff-workorders/101/execute/'),
          type: DioExceptionType.connectionError,
        ),
      );
      when(() => mockSyncManager.enqueueCommand(any())).thenAnswer((_) async {});

      await expectLater(
        repository.startExecution(101),
        throwsA(isA<StartExecutionQueuedOffline>()),
      );
      verify(() => mockSyncManager.enqueueCommand(any())).called(1);
    });

    // Regression: the optimistic offline cache update copyWith'd `remarks`
    // (the transition note) into `description`, overwriting the real one.
    test('transitionStatus offline cache update does not overwrite description', () async {
      const original = WorkOrder(
        id: 101,
        status: WorkOrderStatus.techCompleted,
        type: WorkOrderType.preventive,
        title: 'Monthly Transformer Inspection',
        description: 'Real work order description',
      );
      await cacheService.cacheWorkOrderDetail(original);

      when(() => mockApiService.changeStatus(
            101,
            status: 'REWORK_REQUIRED',
            remarks: 'Oil level was not topped up',
            checklist: any(named: 'checklist'),
            evidence: any(named: 'evidence'),
          )).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );
      when(() => mockSyncManager.enqueueCommand(any())).thenAnswer((_) async {});

      final updated = await repository.transitionStatus(
        101,
        status: 'REWORK_REQUIRED',
        remarks: 'Oil level was not topped up',
      );

      expect(updated.description, 'Real work order description');
      expect(updated.status, WorkOrderStatus.reworkRequired);
    });
  });
}
