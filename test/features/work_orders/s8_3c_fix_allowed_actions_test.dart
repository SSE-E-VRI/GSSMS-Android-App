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
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
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

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({
    required this.status,
    required this.allowedActionsJson,
    this.linkedRecordId,
  });

  final String status;
  final Map<String, dynamic> allowedActionsJson;
  final int? linkedRecordId;
  final List<String> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');
    if (options.path.endsWith('allowed-actions/')) {
      return _json(allowedActionsJson);
    }
    if (options.path.endsWith('/execute/') && options.method == 'POST') {
      return _json({'record_id': 901});
    }
    if (RegExp(r'/work-orders/\d+/$').hasMatch(options.path)) {
      return _json({
        'id': 77,
        'work_order_number': 'WO-2026-0077',
        'title': 'AMC Signal Check',
        'status': status,
        'priority': 'MEDIUM',
        'work_type': 'PM',
        'execution_mode': 'CHECKLIST',
        'station_name': 'MAS',
        'original_schedule': 5,
        'linked_record_id': linkedRecordId,
      });
    }
    if (options.path.contains('records/901/')) {
      return _json({
        'id': 901,
        'work_order': 77,
        'status': 'IN_PROGRESS',
        'lines': const [],
      });
    }
    return _json({'detail': 'unexpected ${options.path}'}, statusCode: 404);
  }

  ResponseBody _json(Map<String, dynamic> body, {int statusCode = 200}) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

UserSession _csSession() => const UserSession(
      accessToken: 'tok',
      userId: 13,
      username: 'cs_tech',
      firstName: 'Test',
      lastName: 'User',
      primaryRole: AuthRole.maintenanceStaff,
      roles: [AuthRole.maintenanceStaff],
      permissions: ['maintenance.view', 'maintenance.edit'],
      scope: OrgScope(level: OrgScopeLevel.depot),
      isContractStaff: true,
    );

Future<void> _pumpDetail(
  WidgetTester tester, {
  required _StubAdapter adapter,
  required IAuthRepository authRepo,
}) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
    ..httpClientAdapter = adapter;
  final session = _csSession();
  when(() => authRepo.currentSession).thenReturn(session);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheServiceProvider
            .overrideWithValue(InMemoryLocalCacheService()),
        authRepositoryProvider.overrideWithValue(authRepo),
        authControllerProvider
            .overrideWith(() => _FakeAuthController(Authenticated(session))),
        authenticatedDioProvider.overrideWithValue(dio),
      ],
      child: const MaterialApp(
        home: WorkOrderDetailScreen(workOrderId: 77),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRepo = _MockAuthRepository();
  });

  group('S8-3c-fix WorkOrderActionSet.fromJson', () {
    test('(a) allowed_actions ["START"] -> allowsTarget("IN_PROGRESS") is true',
        () {
      final set = WorkOrderActionSet.fromJson({
        'work_order': 77,
        'current_status': 'ASSIGNED',
        'allowed_actions': ['START'],
        'blocked_actions': const [],
      });
      expect(set.allowsTarget('IN_PROGRESS'), isTrue);
    });

    test(
        '(b) allowed_actions ["CONTINUE", "COMPLETE"] -> allowsTarget("CONTINUE") and ("TECH_COMPLETED") are true',
        () {
      final set = WorkOrderActionSet.fromJson({
        'work_order': 77,
        'current_status': 'IN_PROGRESS',
        'allowed_actions': ['CONTINUE', 'COMPLETE'],
        'blocked_actions': const [],
      });
      expect(set.allowsTarget('CONTINUE'), isTrue);
      expect(set.allowsTarget('TECH_COMPLETED'), isTrue);
    });

    test(
        '(d) departmental Map payloads parse identically with targetStatus, label, enabled, and requirements',
        () {
      final set = WorkOrderActionSet.fromJson({
        'work_order': 77,
        'current_status': 'IN_PROGRESS',
        'allowed_actions': [
          {
            'target_status': 'ON_HOLD',
            'label': 'Put On Hold',
            'enabled': true,
            'requirements': {'remarks': true, 'failure_code': false},
          },
        ],
        'blocked_actions': [
          {
            'target_status': 'TECH_COMPLETED',
            'label': 'Complete',
            'enabled': false,
            'disabled_reason': 'Checklist incomplete',
          },
        ],
      });
      expect(set.allowsTarget('ON_HOLD'), isTrue);
      expect(set.allowed.single.requiresReason, isTrue);
      expect(set.allowed.single.label, 'Put On Hold');
      expect(set.blocked.single.enabled, isFalse);
      expect(set.blocked.single.disabledReason, 'Checklist incomplete');
    });
  });

  group('S8-3c-fix WorkOrderDetailScreen contract-staff actions', () {
    testWidgets(
        '(c) blocked_actions string tokens parse as disabled and are NOT rendered as enabled buttons',
        (tester) async {
      final parsed = WorkOrderActionSet.fromJson({
        'work_order': 77,
        'current_status': 'ASSIGNED',
        'allowed_actions': const [],
        'blocked_actions': ['START', 'CONTINUE'],
      });
      expect(parsed.blocked.length, 2);
      expect(parsed.blocked.every((a) => !a.enabled), isTrue);
      expect(parsed.allowsTarget('IN_PROGRESS'), isFalse);
      expect(parsed.allowsTarget('CONTINUE'), isFalse);

      final adapter = _StubAdapter(
        status: 'ASSIGNED',
        allowedActionsJson: {
          'work_order': 77,
          'current_status': 'ASSIGNED',
          'allowed_actions': const [],
          'blocked_actions': ['START', 'CONTINUE'],
        },
      );
      await _pumpDetail(tester, adapter: adapter, authRepo: mockRepo);

      expect(find.byKey(const Key('action_start_execution')), findsNothing);
      expect(find.byKey(const Key('action_open_checklist')), findsNothing);
      expect(find.text('Start Execution'), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets(
        '(e) cs=true ASSIGNED detail with ["START"] shows action_start_execution and tapping calls POST staff-workorders/77/execute/',
        (tester) async {
      final adapter = _StubAdapter(
        status: 'ASSIGNED',
        allowedActionsJson: {
          'work_order': 77,
          'current_status': 'ASSIGNED',
          'allowed_actions': ['START'],
          'blocked_actions': const [],
        },
      );
      await _pumpDetail(tester, adapter: adapter, authRepo: mockRepo);

      final btn = find.byKey(const Key('action_start_execution'));
      expect(btn, findsOneWidget);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(
        adapter.calls.any((c) => c.contains('POST ') && c.contains('staff-workorders/77/execute/')),
        isTrue,
      );
    });

    testWidgets(
        '(f) cs=true IN_PROGRESS detail with ["CONTINUE", "COMPLETE"] shows action_open_checklist and no secondary Continue/Complete buttons',
        (tester) async {
      final adapter = _StubAdapter(
        status: 'IN_PROGRESS',
        linkedRecordId: 901,
        allowedActionsJson: {
          'work_order': 77,
          'current_status': 'IN_PROGRESS',
          'allowed_actions': ['CONTINUE', 'COMPLETE'],
          'blocked_actions': const [],
        },
      );
      await _pumpDetail(tester, adapter: adapter, authRepo: mockRepo);

      expect(find.byKey(const Key('action_open_checklist')), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      expect(find.text('Complete'), findsNothing);
    });

    testWidgets(
        '(g) unknown token "FOO" is dropped and does not produce a tappable button',
        (tester) async {
      final parsed = WorkOrderActionSet.fromJson({
        'work_order': 77,
        'current_status': 'IN_PROGRESS',
        'allowed_actions': ['FOO'],
        'blocked_actions': const [],
      });
      expect(parsed.allowed, isEmpty);

      final adapter = _StubAdapter(
        status: 'IN_PROGRESS',
        linkedRecordId: 901,
        allowedActionsJson: {
          'work_order': 77,
          'current_status': 'IN_PROGRESS',
          'allowed_actions': ['FOO'],
          'blocked_actions': const [],
        },
      );
      await _pumpDetail(tester, adapter: adapter, authRepo: mockRepo);
      expect(find.text('FOO'), findsNothing);
    });

    testWidgets(
        '(h) A2: cs=true REWORK_REQUIRED detail with ["CONTINUE"] shows action_start_execution and tapping calls POST staff-workorders/77/execute/',
        (tester) async {
      final adapter = _StubAdapter(
        status: 'REWORK_REQUIRED',
        linkedRecordId: 901,
        allowedActionsJson: {
          'work_order': 77,
          'current_status': 'REWORK_REQUIRED',
          'allowed_actions': ['CONTINUE'],
          'blocked_actions': const [],
        },
      );
      await _pumpDetail(tester, adapter: adapter, authRepo: mockRepo);

      final btn = find.byKey(const Key('action_start_execution'));
      expect(btn, findsOneWidget);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(
        adapter.calls.any((c) => c.contains('POST ') && c.contains('staff-workorders/77/execute/')),
        isTrue,
      );
    });
  });
}
