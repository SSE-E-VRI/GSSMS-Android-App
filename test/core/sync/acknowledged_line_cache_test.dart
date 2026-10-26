import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';

class _Api extends Mock implements WorkOrderApiService {}

class _Cache extends InMemoryLocalCacheService {
  bool failRecordWrite = false;
  @override
  Future<void> cacheMaintenanceRecord(MaintenanceRecord record) async {
    if (failRecordWrite) throw StateError('disk full');
    await super.cacheMaintenanceRecord(record);
  }
}

/// F-001: once the server acknowledges a queued checklist line, the saved
/// offline copy of the record must show that value, not the one downloaded
/// before the edit.
void main() {
  late _Api api;
  late _Cache cache;
  late ProviderContainer container;
  late SyncManager sync;

  const downloaded = MaintenanceRecord(
    id: 55,
    workOrderId: 9,
    lines: [
      MaintenanceRecordLine(
        id: 12,
        itemName: 'Earth pit',
        recordedValue: '0',
        statusOptionId: 3,
        actionOptionId: 4,
        observationAction: 'old remarks',
      ),
      MaintenanceRecordLine(id: 13, itemName: 'Fuse', recordedValue: 'Good'),
    ],
  );

  OutboxCommand command(Map<String, dynamic> payload, {int owner = 7}) =>
      OutboxCommand(
        idempotencyKey: 'line_12_${payload.hashCode}',
        type: OutboxCommandType.submitLine,
        entityId: 55,
        ownerUserId: owner,
        payload: {'line_id': 12, ...payload},
        createdAt: DateTime.now(),
      );

  Future<MaintenanceRecordLine> cachedLine(int id) async =>
      (await cache.getCachedMaintenanceRecord(55))!
          .lines
          .singleWhere((l) => l.id == id);

  setUp(() async {
    api = _Api();
    cache = _Cache();
    await cache.setCacheOwnerUserId(7);
    await cache.cacheMaintenanceRecord(downloaded);
    when(() => api.submitLine(55, any(),
        idempotencyKey: any(named: 'idempotencyKey'))).thenAnswer((_) async {});
    container = ProviderContainer(overrides: [
      localCacheServiceProvider.overrideWithValue(cache),
      workOrderApiServiceProvider.overrideWithValue(api),
    ]);
    sync = container.read(syncManagerProvider.notifier);
  });
  tearDown(() => container.dispose());

  test('a synced line updates the offline record and leaves the queue',
      () async {
    await cache.saveOutboxCommands([
      command({
        'value': '5',
        'status': 'OK',
        'status_option': 8,
        'action_option': null,
        'remarks': 'tightened',
      }),
    ]);

    await sync.drainOutbox();

    final line = await cachedLine(12);
    expect(line.recordedValue, '5');
    expect(line.status, 'OK');
    expect(line.statusOptionId, 8);
    expect(line.actionOptionId, isNull);
    expect(line.observationAction, 'tightened');
    expect(line.isSaved, isTrue);
    expect(line.localSyncStatus, isNull);
    expect((await cachedLine(13)).recordedValue, 'Good',
        reason: 'other lines untouched');
    expect(await cache.getOutboxCommands(), isEmpty);
  });

  test('fields the save did not carry keep their downloaded values', () async {
    await cache.saveOutboxCommands([
      command({'value': '5'})
    ]);

    await sync.drainOutbox();

    final line = await cachedLine(12);
    expect(line.recordedValue, '5');
    expect(line.statusOptionId, 3);
    expect(line.actionOptionId, 4);
    expect(line.observationAction, 'old remarks');
  });

  test('another user\'s acknowledged command never touches this cache',
      () async {
    await cache.saveOutboxCommands([
      command({'value': '5'}, owner: 8)
    ]);

    await sync.drainOutbox();

    expect((await cachedLine(12)).recordedValue, '0');
  });

  test('a failed cache write keeps the command queued, not failed', () async {
    await cache.saveOutboxCommands([
      command({'value': '5'})
    ]);
    cache.failRecordWrite = true;

    await sync.drainOutbox();

    final queued = (await cache.getOutboxCommands()).single;
    expect(queued.status, OutboxCommandStatus.pending);
    expect((await cachedLine(12)).recordedValue, '0');

    // The next drain replays it under the same key and updates the cache.
    cache.failRecordWrite = false;
    await sync.drainOutbox();
    expect((await cachedLine(12)).recordedValue, '5');
    expect(await cache.getOutboxCommands(), isEmpty);
    verify(() =>
            api.submitLine(55, any(), idempotencyKey: queued.idempotencyKey))
        .called(2);
  });
}
