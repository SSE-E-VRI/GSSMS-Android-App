import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';

class MockWorkOrderApiService extends Mock implements WorkOrderApiService {}

void main() {
  group('SyncManager Unit Tests', () {
    late ILocalCacheService cacheService;
    late MockWorkOrderApiService mockApiService;
    late ProviderContainer container;

    setUp(() {
      cacheService = InMemoryLocalCacheService();
      mockApiService = MockWorkOrderApiService();

      container = ProviderContainer(
        overrides: [
          localCacheServiceProvider.overrideWithValue(cacheService),
          workOrderApiServiceProvider.overrideWithValue(mockApiService),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('enqueueCommand writes command to cache and updates pending count', () async {
      final syncManager = container.read(syncManagerProvider.notifier);

      when(() => mockApiService.submitLine(
            10,
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((_) async {});

      final cmd = OutboxCommand(
        idempotencyKey: 'cmd_1',
        type: OutboxCommandType.submitLine,
        entityId: 10,
        payload: const {'line_id': 1, 'value': '230V'},
        createdAt: DateTime.now(),
      );

      await syncManager.enqueueCommand(cmd);

      final state = container.read(syncManagerProvider);
      expect(state.mode, SyncConnectivityMode.online);
      verify(() => mockApiService.submitLine(
            10,
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).called(1);
    });

    test('drainOutbox handles network error gracefully and flags offline mode', () async {
      final syncManager = container.read(syncManagerProvider.notifier);

      when(() => mockApiService.submitLine(
            10,
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );

      final cmd = OutboxCommand(
        idempotencyKey: 'cmd_offline',
        type: OutboxCommandType.submitLine,
        entityId: 10,
        payload: const {'line_id': 1, 'value': '230V'},
        createdAt: DateTime.now(),
      );

      await cacheService.saveOutboxCommands([cmd]);
      await syncManager.drainOutbox();

      final state = container.read(syncManagerProvider);
      expect(state.mode, SyncConnectivityMode.offline);
      expect(state.pendingCount, 1);

      final commands = await cacheService.getOutboxCommands();
      expect(commands.length, 1);
      expect(commands[0].status, OutboxCommandStatus.pending);
      expect(commands[0].retryCount, 1);
    });

    test('drainOutbox flags 409 conflict appropriately without blocking queue', () async {
      final syncManager = container.read(syncManagerProvider.notifier);

      when(() => mockApiService.changeStatus(
            10,
            status: any(named: 'status'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 409,
            data: {'error': 'Conflict with existing state'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final cmd = OutboxCommand(
        idempotencyKey: 'cmd_conflict',
        type: OutboxCommandType.transitionStatus,
        entityId: 10,
        payload: const {'status': 'IN_PROGRESS'},
        createdAt: DateTime.now(),
      );

      await cacheService.saveOutboxCommands([cmd]);
      await syncManager.drainOutbox();

      final commands = await cacheService.getOutboxCommands();
      expect(commands[0].status, OutboxCommandStatus.conflict);
      expect(commands[0].lastError?.contains('Conflict'), isTrue);
    });
  });
}
