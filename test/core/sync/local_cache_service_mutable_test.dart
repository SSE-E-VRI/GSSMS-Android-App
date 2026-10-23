import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApi extends Mock implements WorkOrderApiService {}

class _MockEvidence extends Mock implements EvidenceService {}

OutboxCommand _cmd(String key, {int entityId = 1}) => OutboxCommand(
      idempotencyKey: key,
      type: OutboxCommandType.submitLine,
      entityId: entityId,
      payload: const {'line_id': 1},
      createdAt: DateTime.now(),
    );

void main() {
  late LocalCacheService service;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = LocalCacheService(prefs);
    // _lastGoodOutbox is static: reset between tests.
    await service.clearAllCache();
  });

  group('LocalCacheService returns growable outbox lists', () {
    test('empty store returns a growable list', () async {
      final list = await service.getOutboxCommands();
      expect(list, isEmpty);
      list.add(_cmd('a')); // would throw UnsupportedError on a const list
      expect(list, hasLength(1));
    });

    test('corrupt top-level JSON without backup returns a growable list',
        () async {
      await prefs.setString('gssms_cache_outbox_commands', '{not a list');
      final list = await service.getOutboxCommands();
      expect(list, isEmpty);
      list.add(_cmd('a'));
      expect(list, hasLength(1));
    });
  });

  group('SyncManager on a fresh real LocalCacheService', () {
    late ProviderContainer container;
    late SyncManager manager;

    setUp(() {
      container = ProviderContainer(overrides: [
        localCacheServiceProvider.overrideWithValue(service),
        workOrderApiServiceProvider.overrideWithValue(_MockApi()),
        evidenceServiceProvider.overrideWithValue(_MockEvidence()),
      ]);
      manager = container.read(syncManagerProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('enqueueCommand persists one command', () async {
      await manager.enqueueCommand(_cmd('a'), autoDrain: false);
      expect(await service.getOutboxCommands(), hasLength(1));
    });

    test('enqueueDeduped persists one command', () async {
      final enqueued = await manager.enqueueDeduped(
        _cmd('a'),
        isDuplicate: (_) => false,
        autoDrain: false,
      );
      expect(enqueued, isTrue);
      expect(await service.getOutboxCommands(), hasLength(1));
    });

    test('removeCommand on an empty store does not throw', () async {
      await manager.removeCommand('missing');
      expect(await service.getOutboxCommands(), isEmpty);
    });
  });

  group('clearReadCache', () {
    test('keeps outbox and owner but drops cached read data', () async {
      await service.saveOutboxCommands([_cmd('keep')]);
      await service.setCacheOwnerUserId(5);
      await prefs.setString('gssms_cache_work_orders_list', '[]');
      await prefs.setString('gssms_cache_wo_detail_1', '{}');
      await prefs.setString('gssms_cache_record_1', '{}');

      await service.clearReadCache();

      expect(prefs.getString('gssms_cache_work_orders_list'), isNull);
      expect(prefs.getString('gssms_cache_wo_detail_1'), isNull);
      expect(prefs.getString('gssms_cache_record_1'), isNull);
      expect(await service.getCachedWorkOrders(), isEmpty);
      expect(await service.getCacheOwnerUserId(), 5);
      expect(prefs.getString('gssms_cache_outbox_commands'), isNotNull);
      expect(prefs.getString('gssms_cache_outbox_commands_bak'), isNotNull);
      final outbox = await service.getOutboxCommands();
      expect(outbox.map((c) => c.idempotencyKey), ['keep']);
    });

    test('in-memory implementation keeps outbox and owner', () async {
      final mem = InMemoryLocalCacheService();
      await mem.saveOutboxCommands([_cmd('keep')]);
      await mem.setCacheOwnerUserId(9);
      await mem.clearReadCache();
      expect(await mem.getOutboxCommands(), hasLength(1));
      expect(await mem.getCacheOwnerUserId(), 9);
    });
  });
}
