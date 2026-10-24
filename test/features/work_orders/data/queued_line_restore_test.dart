import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends Mock implements WorkOrderApiService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  late LocalCacheService cache;
  const record = MaintenanceRecord(id: 55, lines: [
    MaintenanceRecordLine(
        id: 12,
        itemName: 'Voltage',
        recordedValue: '0',
        statusOptionId: 3,
        actionOptionId: 4,
        observationAction: 'server'),
    MaintenanceRecordLine(
        id: 13, itemName: 'Other', recordedValue: 'unchanged'),
  ]);

  OutboxCommand command(
    String key,
    Object? value, {
    int? owner = 7,
    int recordId = 55,
    OutboxCommandType type = OutboxCommandType.submitLine,
    OutboxCommandStatus status = OutboxCommandStatus.pending,
    Map<String, dynamic>? extra,
  }) =>
      OutboxCommand(
          idempotencyKey: key,
          type: type,
          entityId: recordId,
          payload: {'line_id': 12, 'value': value, ...?extra},
          createdAt: DateTime(2026, 10, 24),
          ownerUserId: owner,
          status: status);

  WorkOrderRepository restartedRepository() =>
      WorkOrderRepository(api, cacheService: LocalCacheService());

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = LocalCacheService();
    api = _Api();
    await cache.setCacheOwnerUserId(7);
    await cache.cacheMaintenanceRecord(record);
    when(() => api.getMaintenanceRecord(55)).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionError));
  });

  test('A3: fresh repository restores latest queued value from persisted JSON',
      () async {
    await cache.saveOutboxCommands([
      command('existing-format-old', '1'),
      command('existing-format-new', '12.5'),
    ]);
    final result = await restartedRepository().fetchMaintenanceRecord(55);
    expect(result.lines.first.recordedValue, '12.5');
    expect(result.lines[1].recordedValue, 'unchanged');
    expect(result.lines.first.statusOptionId, 3);
    expect(
        (await LocalCacheService().getCachedMaintenanceRecord(55))!
            .lines
            .first
            .recordedValue,
        '0');
    expect((await cache.getOutboxCommands()).map((c) => c.idempotencyKey),
        ['existing-format-old', 'existing-format-new']);
  });

  test('pending value also overlays refreshed online server data', () async {
    when(() => api.getMaintenanceRecord(55)).thenAnswer((_) async => record);
    await cache.saveOutboxCommands([command('pending', '12.5')]);
    final repo = restartedRepository();
    expect((await repo.fetchMaintenanceRecord(55)).lines.first.recordedValue,
        '12.5');
    await cache.saveOutboxCommands([]);
    expect(
        (await repo.fetchMaintenanceRecord(55)).lines.first.recordedValue, '0');
  });

  test('overlay honors explicit clears and restores line options and remarks',
      () async {
    await cache.saveOutboxCommands([
      command('clear', null, extra: {
        'status': 'NOT_OK',
        'status_option': null,
        'action_option': null,
        'remarks': '',
      })
    ]);
    final line =
        (await restartedRepository().fetchMaintenanceRecord(55)).lines.first;
    expect(line.recordedValue, isNull);
    expect(line.status, 'NOT_OK');
    expect(line.statusOptionId, isNull);
    expect(line.actionOptionId, isNull);
    expect(line.observationAction, '');
  });

  test('foreign/unowned/unrelated/completed commands cannot overwrite values',
      () async {
    await cache.saveOutboxCommands([
      command('foreign', 'bad', owner: 8),
      command('unowned', 'bad', owner: null),
      command('other-record', 'bad', recordId: 99),
      command('photo', 'bad', type: OutboxCommandType.uploadEvidence),
      command('synced', 'bad', status: OutboxCommandStatus.synced),
      command('draft', 'bad', status: OutboxCommandStatus.draft),
    ]);
    expect(
        (await restartedRepository().fetchMaintenanceRecord(55))
            .lines
            .first
            .recordedValue,
        '0');
  });

  for (final status in [
    OutboxCommandStatus.failed,
    OutboxCommandStatus.conflict
  ]) {
    test('$status value survives restart without becoming replayable',
        () async {
      await cache
          .saveOutboxCommands([command('attention', '12.5', status: status)]);
      expect(
          (await restartedRepository().fetchMaintenanceRecord(55))
              .lines
              .first
              .recordedValue,
          '12.5');
      expect((await cache.getOutboxCommands()).single.status, status);
    });
  }

  test('no cache owner means no queued overlay', () async {
    await cache.clearAllCache();
    await cache.cacheMaintenanceRecord(record);
    await cache.saveOutboxCommands([command('unbound', 'bad')]);
    expect(
        (await restartedRepository().fetchMaintenanceRecord(55))
            .lines
            .first
            .recordedValue,
        '0');
  });
}
