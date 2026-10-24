import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';

class _Api extends Mock implements WorkOrderApiService {}

class _FailingCache extends InMemoryLocalCacheService {
  bool fail = false;
  @override
  Future<void> saveOutboxCommands(List<OutboxCommand> commands) async {
    if (fail) throw StateError('disk full');
    await super.saveOutboxCommands(commands);
  }
}

void main() {
  late _Api api;
  late _FailingCache cache;
  late ProviderContainer container;
  late SyncManager sync;

  OutboxCommand command(String key, String value, {int owner = 7}) =>
      OutboxCommand(
        idempotencyKey: key,
        type: OutboxCommandType.submitLine,
        entityId: 55,
        ownerUserId: owner,
        payload: {'line_id': 12, 'value': value},
        createdAt: DateTime.now(),
      );

  Future<bool> enqueue(OutboxCommand cmd) => sync.enqueueDeduped(cmd,
      autoDrain: false,
      isDuplicate: (c) =>
          c.type == cmd.type &&
          c.entityId == cmd.entityId &&
          c.payload['line_id'] == 12);

  setUp(() async {
    api = _Api();
    cache = _FailingCache();
    await cache.setCacheOwnerUserId(7);
    container = ProviderContainer(overrides: [
      localCacheServiceProvider.overrideWithValue(cache),
      workOrderApiServiceProvider.overrideWithValue(api),
    ]);
    sync = container.read(syncManagerProvider.notifier);
  });
  tearDown(() => container.dispose());

  test('A13/A14: autosaves coalesce to final value and replay that value',
      () async {
    for (final value in ['1', '12', '12.', '12.5']) {
      expect(await enqueue(command('key_$value', value)), isTrue);
    }
    final queued = await cache.getOutboxCommands();
    expect(queued.single.payload['value'], '12.5');
    expect(queued.single.idempotencyKey, 'key_12.5');
    when(() => api.submitLine(55, any(),
        idempotencyKey: any(named: 'idempotencyKey'))).thenAnswer((_) async {});
    await sync.drainOutbox();
    final sent = verify(
            () => api.submitLine(55, captureAny(), idempotencyKey: 'key_12.5'))
        .captured
        .single as Map;
    expect(sent['value'], '12.5');
    expect(await cache.getOutboxCommands(), isEmpty);
  });

  test('replacement does not change another owner or failed command', () async {
    final failed =
        command('failed', 'old').copyWith(status: OutboxCommandStatus.failed);
    await cache.saveOutboxCommands([command('foreign', '9', owner: 8), failed]);
    await enqueue(command('new', '12.5'));
    expect((await cache.getOutboxCommands()).map((c) => c.idempotencyKey),
        ['foreign', 'failed', 'new']);
  });

  test('failed replacement is not acknowledged and keeps prior save', () async {
    await enqueue(command('old', '1'));
    cache.fail = true;
    await expectLater(enqueue(command('new', '12.5')), throwsStateError);
    expect((await cache.getOutboxCommands()).single.payload['value'], '1');
  });

  test('reconnected save cannot be overwritten by older queued value',
      () async {
    await enqueue(command('old', '1'));
    when(() => api.submitLine(55, any(),
        idempotencyKey: any(named: 'idempotencyKey'))).thenAnswer((_) async {});
    final repo =
        WorkOrderRepository(api, cacheService: cache, syncManager: sync);
    await repo.submitChecklistLine(55, {'line_id': 12, 'value': '12.5'});
    final values = verify(() => api.submitLine(55, captureAny(),
        idempotencyKey: any(named: 'idempotencyKey'))).captured.cast<Map>();
    expect(values.map((v) => v['value']), ['12.5']);
    expect(await cache.getOutboxCommands(), isEmpty);
  });

  test('older in-flight acknowledgment cannot remove newer edit', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    when(() => api.submitLine(55, any(),
        idempotencyKey: any(named: 'idempotencyKey'))).thenAnswer((_) async {
      started.complete();
      await release.future;
    });
    await enqueue(command('old', '1'));
    final drain = sync.drainOutbox();
    await started.future;
    final next = enqueue(command('new', '12.5'));
    release.complete();
    await drain;
    await next;
    expect((await cache.getOutboxCommands()).single.payload['value'], '12.5');
  });

  test('overlapping repository autosaves preserve invocation order', () async {
    final firstStarted = Completer<void>();
    final release = Completer<void>();
    var attempts = 0;
    when(() => api.submitLine(55, any(),
        idempotencyKey: any(named: 'idempotencyKey'))).thenAnswer((_) async {
      if (attempts++ == 0) {
        firstStarted.complete();
        await release.future;
      }
      throw DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError);
    });
    final repo =
        WorkOrderRepository(api, cacheService: cache, syncManager: sync);
    final first = repo.submitChecklistLine(55, {'line_id': 12, 'value': '1'});
    await firstStarted.future;
    final last = repo.submitChecklistLine(55, {'line_id': 12, 'value': '12.5'});
    release.complete();
    await Future.wait([first, last]);
    expect((await cache.getOutboxCommands()).single.payload['value'], '12.5');
  });
}
