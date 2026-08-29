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

OutboxCommand _lineCommand(String key, int lineId) {
  return OutboxCommand(
    idempotencyKey: key,
    type: OutboxCommandType.submitLine,
    entityId: 10,
    payload: {'line_id': lineId, 'value': '230V'},
    createdAt: DateTime.now(),
  );
}

void main() {
  group('SyncManager outbox durability', () {
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

    test('keeps commands queued behind the one that hit the network error', () async {
      // The first command syncs, the second goes offline. Everything after the
      // failure must survive in the outbox rather than being dropped.
      when(() => mockApiService.submitLine(10, any())).thenAnswer((invocation) async {
        final payload = invocation.positionalArguments[1] as Map<String, dynamic>;
        if (payload['line_id'] == 1) return;
        throw DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        );
      });

      await cacheService.saveOutboxCommands([
        _lineCommand('cmd_1', 1),
        _lineCommand('cmd_2', 2),
        _lineCommand('cmd_3', 3),
        _lineCommand('cmd_4', 4),
      ]);

      await container.read(syncManagerProvider.notifier).drainOutbox();

      final remaining = await cacheService.getOutboxCommands();
      expect(
        remaining.map((c) => c.idempotencyKey),
        ['cmd_2', 'cmd_3', 'cmd_4'],
        reason: 'the synced command is removed; nothing else may be lost',
      );
      expect(
        remaining.every((c) => c.status == OutboxCommandStatus.pending),
        isTrue,
      );

      final state = container.read(syncManagerProvider);
      expect(state.mode, SyncConnectivityMode.offline);
      expect(state.pendingCount, 3);
    });

    test('an outbox holding only failed commands still reports them as pending', () async {
      await cacheService.saveOutboxCommands([
        _lineCommand('cmd_failed', 1).copyWith(
          status: OutboxCommandStatus.failed,
          lastError: 'Validation error',
        ),
      ]);

      await container.read(syncManagerProvider.notifier).drainOutbox();

      final state = container.read(syncManagerProvider);
      expect(
        state.pendingCount,
        1,
        reason: 'unsynced work must stay visible in the badge',
      );
    });
  });
}
