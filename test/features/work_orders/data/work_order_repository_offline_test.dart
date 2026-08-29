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
  });
}
