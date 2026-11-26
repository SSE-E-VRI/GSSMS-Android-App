import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/storage/secure_storage_service.dart';
import 'package:gssms_mobile/core/storage/offline_session_store.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/auth/data/auth_api_service.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_tokens.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/downloaded_checklist_access.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthApiService extends Mock implements AuthApiService {}

class _MockSecureStorage extends Mock implements SecureStorageService {}

class _MockWorkOrderApiService extends Mock implements WorkOrderApiService {}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);
  final AuthState _initial;
  @override
  AuthState build() => _initial;
}

class _InMemoryOfflineSessionStore implements IOfflineSessionStore {
  OfflineSessionSnapshot? stored;
  bool clearCalled = false;

  @override
  Future<OfflineSessionSnapshot?> read() async => stored;

  @override
  Future<void> write(OfflineSessionSnapshot snapshot) async {
    stored = snapshot;
  }

  @override
  Future<void> clear() async {
    clearCalled = true;
    stored = null;
  }
}

String _jwt({required bool cs, int userId = 13}) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = b64({'alg': 'HS256', 'typ': 'JWT'});
  final payload = b64({
    'user_id': userId,
    'username': cs ? 'cs_tech' : 'dept_tech',
    'roles': ['MAINTENANCE_STAFF'],
    'permissions': ['maintenance.view', 'maintenance.edit'],
    'scope': {'level': 'DEPOT'},
    'cs': cs,
    'exp': 4102444800,
  });
  return '$header.$payload.sig';
}

UserSession _session({required bool cs, int userId = 13}) => UserSession(
      accessToken: 'tok',
      userId: userId,
      username: cs ? 'cs_tech' : 'dept_tech',
      primaryRole: AuthRole.maintenanceStaff,
      roles: const [AuthRole.maintenanceStaff],
      permissions: const ['maintenance.view', 'maintenance.edit'],
      scope: const OrgScope(level: OrgScopeLevel.depot),
      isContractStaff: cs,
    );

DioException _networkErr() => DioException(
      requestOptions: RequestOptions(path: '/api/v1/test/'),
      type: DioExceptionType.connectionError,
    );

void main() {
  const expectedOnlineMsg =
      'Internet connection is required. Contract staff cannot work offline.';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SyncManager makeSync(InMemoryLocalCacheService cache) {
    final c = ProviderContainer(
        overrides: [localCacheServiceProvider.overrideWithValue(cache)]);
    addTearDown(c.dispose);
    return c.read(syncManagerProvider.notifier);
  }

  group('S8-3b D116 Online-only contract staff', () {
    test('(1) restoreSession with NetworkAuthException and cs=true snapshot returns null',
        () async {
      final api = _MockAuthApiService();
      final storage = _MockSecureStorage();
      final cache = InMemoryLocalCacheService();
      await cache.setCacheOwnerUserId(13);
      final store = _InMemoryOfflineSessionStore()
        ..stored = OfflineSessionSnapshot(
          _jwt(cs: true, userId: 13),
          13,
          DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
          DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        );
      when(() => storage.getRefreshToken()).thenAnswer((_) async => 'ref_tok');
      when(() => api.refreshToken('ref_tok'))
          .thenThrow(const NetworkAuthException('offline'));

      final repo = AuthRepository(
        apiService: api,
        secureStorage: storage,
        cacheService: cache,
        offlineSessionStore: store,
      );
      final restored = await repo.restoreSession();
      expect(restored, isNull);
    });

    test('(2) restoreSession with NetworkAuthException and cs=false snapshot returns offline session',
        () async {
      final api = _MockAuthApiService();
      final storage = _MockSecureStorage();
      final cache = InMemoryLocalCacheService();
      await cache.setCacheOwnerUserId(13);
      final store = _InMemoryOfflineSessionStore()
        ..stored = OfflineSessionSnapshot(
          _jwt(cs: false, userId: 13),
          13,
          DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
          DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        );
      when(() => storage.getRefreshToken()).thenAnswer((_) async => 'ref_tok');
      when(() => api.refreshToken('ref_tok'))
          .thenThrow(const NetworkAuthException('offline'));

      final repo = AuthRepository(
        apiService: api,
        secureStorage: storage,
        cacheService: cache,
        offlineSessionStore: store,
      );
      final restored = await repo.restoreSession();
      expect(restored, isNotNull);
      expect(restored!.isOffline, isTrue);
    });

    test('(3) committing a cs=true session writes no offline snapshot and clears existing',
        () async {
      final api = _MockAuthApiService();
      final storage = _MockSecureStorage();
      final cache = InMemoryLocalCacheService();
      final store = _InMemoryOfflineSessionStore()
        ..stored = OfflineSessionSnapshot(
          _jwt(cs: false, userId: 99),
          99,
          DateTime.now().toUtc(),
          DateTime.now().toUtc(),
        );
      when(() => storage.saveRefreshToken(any())).thenAnswer((_) async {});
      when(() => api.login(username: 'cs_tech', password: 'pw', otp: null))
          .thenAnswer((_) async => AuthTokens(
                accessToken: _jwt(cs: true, userId: 13),
                refreshToken: 'ref',
              ));

      final repo = AuthRepository(
        apiService: api,
        secureStorage: storage,
        cacheService: cache,
        offlineSessionStore: store,
      );
      await repo.login(username: 'cs_tech', password: 'pw');
      expect(store.stored, isNull);
      expect(store.clearCalled, isTrue);
    });

    test('(4a) cs=true startExecution on network error enqueues nothing and throws OnlineRequiredException',
        () async {
      final api = _MockWorkOrderApiService();
      final cache = InMemoryLocalCacheService();
      final sync = makeSync(cache);
      when(() => api.startExecution(77, idempotencyKey: any(named: 'idempotencyKey')))
          .thenThrow(_networkErr());

      final repo = WorkOrderRepository(
        api,
        cacheService: cache,
        syncManager: sync,
        sessionProvider: () => _session(cs: true),
      );
      await expectLater(
        repo.startExecution(77),
        throwsA(isA<OnlineRequiredException>()
            .having((e) => e.message, 'message', expectedOnlineMsg)),
      );
      expect(await cache.getOutboxCommands(), isEmpty);
    });

    test('(4b) cs=true submitChecklistLine on network error enqueues nothing and throws OnlineRequiredException',
        () async {
      final api = _MockWorkOrderApiService();
      final cache = InMemoryLocalCacheService();
      final sync = makeSync(cache);
      when(() => api.submitLine(5, any(), idempotencyKey: any(named: 'idempotencyKey')))
          .thenThrow(_networkErr());

      final repo = WorkOrderRepository(
        api,
        cacheService: cache,
        syncManager: sync,
        sessionProvider: () => _session(cs: true),
      );
      await expectLater(
        repo.submitChecklistLine(5, {'line_id': 1, 'status': 'OK'}),
        throwsA(isA<OnlineRequiredException>()
            .having((e) => e.message, 'message', expectedOnlineMsg)),
      );
      expect(await cache.getOutboxCommands(), isEmpty);
    });

    test('(4c) cs=true completeMaintenanceRecord on network error enqueues nothing and throws OnlineRequiredException',
        () async {
      final api = _MockWorkOrderApiService();
      final cache = InMemoryLocalCacheService();
      final sync = makeSync(cache);
      when(() => api.completeRecord(
            5,
            technicianName: any(named: 'technicianName'),
            remarks: any(named: 'remarks'),
            supervisorName: any(named: 'supervisorName'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenThrow(_networkErr());

      final repo = WorkOrderRepository(
        api,
        cacheService: cache,
        syncManager: sync,
        sessionProvider: () => _session(cs: true),
      );
      await expectLater(
        repo.completeMaintenanceRecord(5, technicianName: 'CS', remarks: 'Done'),
        throwsA(isA<OnlineRequiredException>()
            .having((e) => e.message, 'message', expectedOnlineMsg)),
      );
      expect(await cache.getOutboxCommands(), isEmpty);
    });

    test('(4d) cs=true uploadLineAttachment on network error enqueues nothing and throws OnlineRequiredException',
        () async {
      final api = _MockWorkOrderApiService();
      final cache = InMemoryLocalCacheService();
      final sync = makeSync(cache);
      when(() => api.uploadLineAttachment(
            5,
            lineId: any(named: 'lineId'),
            kind: any(named: 'kind'),
            imagePath: any(named: 'imagePath'),
            capturedAt: any(named: 'capturedAt'),
            source: any(named: 'source'),
            latitude: any(named: 'latitude'),
            longitude: any(named: 'longitude'),
            locationAccuracyM: any(named: 'locationAccuracyM'),
            locationRecordedAt: any(named: 'locationRecordedAt'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenThrow(_networkErr());

      final repo = WorkOrderRepository(
        api,
        cacheService: cache,
        syncManager: sync,
        sessionProvider: () => _session(cs: true),
      );
      await expectLater(
        repo.uploadLineAttachment(5, lineId: 1, kind: 'BEFORE', imagePath: '/tmp/a.jpg'),
        throwsA(isA<OnlineRequiredException>()
            .having((e) => e.message, 'message', expectedOnlineMsg)),
      );
      expect(await cache.getOutboxCommands(), isEmpty);
    });

    test('(4e) cs=true uploadEvidence on network error enqueues nothing and throws OnlineRequiredException',
        () async {
      final api = _MockWorkOrderApiService();
      final cache = InMemoryLocalCacheService();
      final sync = makeSync(cache);
      when(() => api.uploadRecordEvidence(
            5,
            proofJpegPath: any(named: 'proofJpegPath'),
            remarks: any(named: 'remarks'),
            otherStaff: any(named: 'otherStaff'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenThrow(_networkErr());

      final repo = WorkOrderRepository(
        api,
        cacheService: cache,
        syncManager: sync,
        sessionProvider: () => _session(cs: true),
      );
      await expectLater(
        repo.uploadEvidence(5, remarks: 'Done'),
        throwsA(isA<OnlineRequiredException>()
            .having((e) => e.message, 'message', expectedOnlineMsg)),
      );
      expect(await cache.getOutboxCommands(), isEmpty);
    });

    test('(5) cs=false startExecution/submitChecklistLine/completeMaintenanceRecord still enqueue',
        () async {
      final api = _MockWorkOrderApiService();
      final cache = InMemoryLocalCacheService();
      final sync = makeSync(cache);
      when(() => api.startExecution(77, idempotencyKey: any(named: 'idempotencyKey')))
          .thenThrow(_networkErr());
      when(() => api.submitLine(5, any(), idempotencyKey: any(named: 'idempotencyKey')))
          .thenThrow(_networkErr());
      when(() => api.completeRecord(
            5,
            technicianName: any(named: 'technicianName'),
            remarks: any(named: 'remarks'),
            supervisorName: any(named: 'supervisorName'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenThrow(_networkErr());

      final repo = WorkOrderRepository(
        api,
        cacheService: cache,
        syncManager: sync,
        sessionProvider: () => _session(cs: false),
      );
      await expectLater(repo.startExecution(77), throwsA(isA<StartExecutionQueuedOffline>()));
      await repo.submitChecklistLine(5, {'line_id': 1, 'status': 'OK'});
      await repo.completeMaintenanceRecord(5, technicianName: 'Dept', remarks: 'Done');
      expect((await cache.getOutboxCommands()).length, 3);
    });

    test('(6a) cs=true fetchWorkOrderById on network error does not return cached data',
        () async {
      final api = _MockWorkOrderApiService();
      final cache = InMemoryLocalCacheService();
      await cache.cacheWorkOrderDetail(WorkOrder(
        id: 77,
        title: 'Cached',
        status: WorkOrderStatus.inProgress,
        priority: WorkOrderPriority.medium,
        type: WorkOrderType.preventive,
        linkedRecordId: 5,
      ));
      when(() => api.getWorkOrder(77)).thenThrow(_networkErr());

      final repo = WorkOrderRepository(
        api,
        cacheService: cache,
        sessionProvider: () => _session(cs: true),
      );
      await expectLater(
        repo.fetchWorkOrderById(77),
        throwsA(isA<OnlineRequiredException>()),
      );
    });

    test('(6b) cs=true fetchMaintenanceRecord on network error does not return cached data',
        () async {
      final api = _MockWorkOrderApiService();
      final cache = InMemoryLocalCacheService();
      await cache.cacheMaintenanceRecord(MaintenanceRecord(
        id: 5,
        workOrderId: 77,
        status: 'IN_PROGRESS',
        lines: const [],
      ));
      when(() => api.getMaintenanceRecord(5)).thenThrow(_networkErr());

      final repo = WorkOrderRepository(
        api,
        cacheService: cache,
        sessionProvider: () => _session(cs: true),
      );
      await expectLater(
        repo.fetchMaintenanceRecord(5),
        throwsA(isA<OnlineRequiredException>()),
      );
    });

    test('(7) downloadedChecklistAccessProvider is false for cs=true and true for cs=false',
        () async {
      final cache = InMemoryLocalCacheService();
      await cache.setCacheOwnerUserId(13);
      await cache.cacheMaintenanceRecord(MaintenanceRecord(
        id: 5,
        workOrderId: 77,
        status: 'IN_PROGRESS',
        lines: const [],
      ));
      final wo = WorkOrder(
        id: 77,
        title: 'AMC Job',
        status: WorkOrderStatus.inProgress,
        priority: WorkOrderPriority.medium,
        type: WorkOrderType.preventive,
        assignedToId: 13,
        linkedRecordId: 5,
      );

      final csContainer = ProviderContainer(overrides: [
        localCacheServiceProvider.overrideWithValue(cache),
        authControllerProvider.overrideWith(
          () => _FakeAuthController(Authenticated(_session(cs: true, userId: 13))),
        ),
      ]);
      addTearDown(csContainer.dispose);
      expect(
        await csContainer.read(downloadedChecklistAccessProvider(wo).future),
        isFalse,
      );

      final deptContainer = ProviderContainer(overrides: [
        localCacheServiceProvider.overrideWithValue(cache),
        authControllerProvider.overrideWith(
          () => _FakeAuthController(Authenticated(_session(cs: false, userId: 13))),
        ),
      ]);
      addTearDown(deptContainer.dispose);
      expect(
        await deptContainer.read(downloadedChecklistAccessProvider(wo).future),
        isTrue,
      );
    });
  });
}
