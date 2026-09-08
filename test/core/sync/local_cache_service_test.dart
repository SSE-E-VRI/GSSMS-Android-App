import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

void main() {
  group('LocalCacheService Tests', () {
    late ILocalCacheService cacheService;

    setUp(() {
      cacheService = InMemoryLocalCacheService();
    });

    test('caches and retrieves work orders list', () async {
      const orders = [
        WorkOrder(
          id: 1,
          status: WorkOrderStatus.assigned,
          type: WorkOrderType.preventive,
          title: 'Transformer Inspection',
        ),
      ];

      await cacheService.cacheWorkOrders(orders);
      final retrieved = await cacheService.getCachedWorkOrders();

      expect(retrieved.length, 1);
      expect(retrieved[0].id, 1);
      expect(retrieved[0].title, 'Transformer Inspection');
    });

    test('caches and retrieves single work order detail', () async {
      const order = WorkOrder(
        id: 42,
        status: WorkOrderStatus.inProgress,
        type: WorkOrderType.breakdown,
        title: 'Signal Repair',
        assetName: 'SIG-42',
      );

      await cacheService.cacheWorkOrderDetail(order);
      final retrieved = await cacheService.getCachedWorkOrderDetail(42);

      expect(retrieved, isNotNull);
      expect(retrieved?.id, 42);
      expect(retrieved?.assetName, 'SIG-42');
    });

    test('caches and retrieves maintenance record', () async {
      const record = MaintenanceRecord(
        id: 99,
        workOrderId: 42,
        lines: [
          MaintenanceRecordLine(
            id: 1,
            itemName: 'Check Fuse',
            recordedValue: 'Good',
          ),
        ],
      );

      await cacheService.cacheMaintenanceRecord(record);
      final retrieved = await cacheService.getCachedMaintenanceRecord(99);

      expect(retrieved, isNotNull);
      expect(retrieved?.id, 99);
      expect(retrieved?.lines.length, 1);
      expect(retrieved?.lines[0].recordedValue, 'Good');
    });

    test('saves and retrieves outbox commands', () async {
      final cmd = OutboxCommand(
        idempotencyKey: 'cmd_123',
        type: OutboxCommandType.submitLine,
        entityId: 99,
        payload: const {'line_id': 1, 'value': '230V'},
        createdAt: DateTime.now(),
      );

      await cacheService.saveOutboxCommands([cmd]);
      final retrieved = await cacheService.getOutboxCommands();

      expect(retrieved.length, 1);
      expect(retrieved[0].idempotencyKey, 'cmd_123');
      expect(retrieved[0].type, OutboxCommandType.submitLine);
      expect(retrieved[0].payload['value'], '230V');
    });

    test('stores cache owner user id', () async {
      await cacheService.setCacheOwnerUserId(42);
      expect(await cacheService.getCacheOwnerUserId(), 42);
      await cacheService.clearAllCache();
      expect(await cacheService.getCacheOwnerUserId(), isNull);
    });

    test('clearAllCache removes all stored data', () async {
      const order = WorkOrder(id: 1, status: WorkOrderStatus.newOrder, type: WorkOrderType.preventive);
      await cacheService.cacheWorkOrders([order]);
      await cacheService.clearAllCache();

      final retrieved = await cacheService.getCachedWorkOrders();
      expect(retrieved, isEmpty);
    });
  });
}
