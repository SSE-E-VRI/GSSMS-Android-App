import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/offline_work_screen.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/fake_auth.dart';

class _Api extends Mock implements WorkOrderApiService {}

void main() {
  late _Api api;
  late InMemoryLocalCacheService cache;
  late ProviderContainer container;
  late UserSession session;
  late WorkOrderRepository repository;
  const order = WorkOrder(
      id: 1,
      type: WorkOrderType.preventive,
      status: WorkOrderStatus.inProgress,
      title: 'Downloaded',
      assignedToId: 1,
      linkedRecordId: 55);
  const record = MaintenanceRecord(id: 55, workOrderId: 1, lines: [
    MaintenanceRecordLine(
        id: 12, itemName: 'Reading', recordedValue: '0', checkedOut: true),
  ]);

  setUp(() async {
    api = _Api();
    cache = InMemoryLocalCacheService();
    session = fakeSession(
            role: AuthRole.maintenanceStaff, userId: 1, permissions: ['*'])
        .copyWith(
            isOffline: true,
            offlineUntil: DateTime.now().toUtc().add(const Duration(hours: 8)));
    await cache.setCacheOwnerUserId(1);
    await cache.cacheWorkOrders([order]);
    await cache.cacheWorkOrderDetail(order);
    await cache.cacheMaintenanceRecord(record);
    container = ProviderContainer(overrides: [
      localCacheServiceProvider.overrideWithValue(cache),
      workOrderApiServiceProvider.overrideWithValue(api),
      authControllerProvider
          .overrideWith(() => FakeAuthenticatedController(session)),
    ]);
    repository = WorkOrderRepository(api,
        cacheService: cache,
        syncManager: container.read(syncManagerProvider.notifier),
        sessionProvider: () => session);
  });
  tearDown(() => container.dispose());

  test('offline read/save never attempts network and retains latest payload',
      () async {
    expect(
        (await repository.fetchMaintenanceRecord(55)).lines.first.recordedValue,
        '0');
    await repository.submitChecklistLine(55, {'line_id': 12, 'value': '1'});
    await repository.submitChecklistLine(55, {'line_id': 12, 'value': '12.5'});
    expect(
        (await repository.fetchMaintenanceRecord(55)).lines.first.recordedValue,
        '12.5');
    expect((await cache.getOutboxCommands()).single.payload['value'], '12.5');
    await container.read(syncManagerProvider.notifier).drainOutbox();
    expect((await cache.getOutboxCommands()).single.payload['value'], '12.5');
    verifyZeroInteractions(api);
  });

  test('foreign owner blocks cached read and queued save', () async {
    await cache.setCacheOwnerUserId(2);
    await expectLater(repository.fetchMaintenanceRecord(55),
        throwsA(isA<OnlineRequiredException>()));
    await expectLater(
        repository.submitChecklistLine(55, {'line_id': 12, 'value': '12.5'}),
        throwsA(isA<OnlineRequiredException>()));
    expect(await cache.getOutboxCommands(), isEmpty);
    verifyZeroInteractions(api);
  });

  test('expired offline window blocks saves and permissions', () async {
    session = session.copyWith(
        offlineUntil: DateTime.now().subtract(const Duration(seconds: 1)));
    await expectLater(
        repository.submitChecklistLine(55, {'line_id': 12, 'value': '12.5'}),
        throwsA(isA<OnlineRequiredException>()));
    expect(canWriteChecklist(session), isFalse);
    expect(await cache.getOutboxCommands(), isEmpty);
  });

  test('even wildcard offline profile cannot authorize other capabilities', () {
    expect(canWriteChecklist(session), isTrue);
    expect(canAddChecklistAttachment(session), isFalse);
    expect(canUncheckoutGroup(session), isFalse);
    expect(sessionAllows(session, 'assets.replace'), isFalse);
  });

  test('offline landing lists only owned downloaded In Progress work',
      () async {
    const foreign = WorkOrder(
        id: 2,
        type: WorkOrderType.preventive,
        status: WorkOrderStatus.inProgress,
        title: 'Foreign',
        assignedToId: 2,
        linkedRecordId: 56);
    await cache.cacheWorkOrders([order, foreign]);
    await cache.cacheWorkOrderDetail(foreign);
    await cache.cacheMaintenanceRecord(
        const MaintenanceRecord(id: 56, workOrderId: 2));
    expect((await container.read(offlineWorkProvider.future)).map((o) => o.id),
        [1]);
    verifyZeroInteractions(api);
  });
}
