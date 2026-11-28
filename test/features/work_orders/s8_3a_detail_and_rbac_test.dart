import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthRepository extends Mock implements IAuthRepository {}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);
  final AuthState _initial;
  @override
  AuthState build() => _initial;
}

class _RecordingAdapter implements HttpClientAdapter {
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    if (options.path.contains('schedules/attention/')) {
      return _json({'overdue': [], 'due_soon': []});
    }
    if (options.path.contains('dashboard/summary/')) {
      return _json({'stats': {}});
    }
    if (options.path.contains('staff-workorders/') ||
        options.path.contains('/work-orders/')) {
      if (options.path.endsWith('allowed-actions/')) {
        return _json({
          'allowed': [
            {'target_status': 'IN_PROGRESS', 'label': 'Start'}
          ],
        });
      }
      if (options.path.endsWith('audit/')) {
        return _json({
          'events': [
            {
              'id': 1,
              'action': 'ASSIGNED',
              'actor_name': 'Div Admin',
              'timestamp': '2026-11-25T10:00:00Z',
            }
          ],
        });
      }
      if (RegExp(r'/work-orders/\d+/$').hasMatch(options.path)) {
        return _json({
          'id': 77,
          'work_order_number': 'WO-2026-0077',
          'title': 'AMC Traction Check',
          'status': 'ASSIGNED',
          'priority': 'MEDIUM',
          'work_type': 'PM',
          'station_name': 'MAS',
          'original_schedule': 5,
        });
      }
      return _json({'count': 0, 'results': []});
    }
    return _json({'detail': 'unexpected ${options.path}'}, status: 403);
  }

  ResponseBody _json(Map<String, dynamic> body, {int status = 200}) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

UserSession _session({
  required bool isContractStaff,
  required List<AuthRole> roles,
  required List<String> permissions,
}) {
  return UserSession(
    accessToken: 'tok',
    userId: 13,
    username: isContractStaff ? 'cs_tech' : 'dept_user',
    firstName: 'Test',
    lastName: 'User',
    primaryRole: roles.first,
    roles: roles,
    permissions: permissions,
    scope: const OrgScope(level: OrgScopeLevel.depot),
    isContractStaff: isContractStaff,
  );
}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRepo = _MockAuthRepository();
  });

  group('S8-3a F1 + G1 + G2', () {
    testWidgets(
        '(1) F1: dashboard.view-only departmental session makes NO dashboard calls on Home',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;
      final session = _session(
        isContractStaff: false,
        roles: const [AuthRole.divHqUser],
        permissions: const ['dashboard.view'],
      );
      when(() => mockRepo.currentSession).thenReturn(session);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider
                .overrideWith(() => _FakeAuthController(Authenticated(session))),
            authenticatedDioProvider.overrideWithValue(dio),
          ],
          child: MaterialApp(home: HomeScreen(session: session, autoLoadData: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        adapter.paths.where((p) =>
            p.contains('dashboard/summary/') ||
            p.contains('schedules/attention/')),
        isEmpty,
      );
    });

    testWidgets(
        '(2) F1: maintenance.view departmental session still calls dashboard/summary/ and schedules/attention/',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;
      final session = _session(
        isContractStaff: false,
        roles: const [AuthRole.maintenanceStaff],
        permissions: const ['maintenance.view'],
      );
      when(() => mockRepo.currentSession).thenReturn(session);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider
                .overrideWith(() => _FakeAuthController(Authenticated(session))),
            authenticatedDioProvider.overrideWithValue(dio),
          ],
          child: MaterialApp(home: HomeScreen(session: session, autoLoadData: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        adapter.paths.where((p) => p.contains('schedules/attention/')),
        isNotEmpty,
      );
      expect(
        adapter.paths.where((p) => p.contains('dashboard/summary/')),
        isNotEmpty,
      );
    });

    testWidgets(
        '(3) G1: cs=true WorkOrderDetailScreen makes 0 calls to audit/ and supervisor-mandate/ and shows detail',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;
      final session = _session(
        isContractStaff: true,
        roles: const [AuthRole.maintenanceStaff, AuthRole.depotIncharge],
        permissions: const ['maintenance.view', 'maintenance.edit'],
      );
      when(() => mockRepo.currentSession).thenReturn(session);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider
                .overrideWith(() => _FakeAuthController(Authenticated(session))),
            authenticatedDioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: WorkOrderDetailScreen(workOrderId: 77)),
        ),
      );
      await tester.pumpAndSettle();

      expect(adapter.paths.where((p) => p.contains('audit/')), isEmpty);
      expect(
          adapter.paths.where((p) => p.contains('supervisor-mandate/')), isEmpty);
      expect(find.text('AMC Traction Check'), findsOneWidget);
      expect(find.text('Div Admin'), findsNothing);
    });

    testWidgets('(4) G1: cs=false WorkOrderDetailScreen still calls audit/',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;
      final session = _session(
        isContractStaff: false,
        roles: const [AuthRole.maintenanceStaff],
        permissions: const ['maintenance.view', 'maintenance.edit'],
      );
      when(() => mockRepo.currentSession).thenReturn(session);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider
                .overrideWith(() => _FakeAuthController(Authenticated(session))),
            authenticatedDioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: WorkOrderDetailScreen(workOrderId: 77)),
        ),
      );
      await tester.pumpAndSettle();

      expect(adapter.paths.where((p) => p.contains('audit/')), isNotEmpty);
    });

    test(
        '(5) G2: canManagePreStartMandates and canReassignWorkOrder are false for cs=true even with depotIncharge role',
        () {
      final csWithDepotRole = _session(
        isContractStaff: true,
        roles: const [AuthRole.depotIncharge, AuthRole.depotUser],
        permissions: const ['maintenance.view', 'maintenance.edit'],
      );
      final deptDepot = _session(
        isContractStaff: false,
        roles: const [AuthRole.depotIncharge],
        permissions: const ['maintenance.view', 'maintenance.edit'],
      );

      expect(canManagePreStartMandates(csWithDepotRole), isFalse);
      expect(canReassignWorkOrder(csWithDepotRole), isFalse);
      expect(canManagePreStartMandates(deptDepot), isTrue);
      expect(canReassignWorkOrder(deptDepot), isTrue);
    });
  });
}
