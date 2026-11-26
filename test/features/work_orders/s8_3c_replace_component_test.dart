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
import 'package:gssms_mobile/features/work_orders/domain/models/replacement_requests.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/replace_component_sheet.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthRepository extends Mock implements IAuthRepository {}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);
  final AuthState _initial;
  @override
  AuthState build() => _initial;
}

class _RecordedCall {
  _RecordedCall(this.method, this.path, this.data);
  final String method;
  final String path;
  final dynamic data;
}

class _RecordingAdapter implements HttpClientAdapter {
  final List<_RecordedCall> calls = [];
  int recordFetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(_RecordedCall(options.method, options.path, options.data));
    if (options.path == '/api/v1/maintenance/records/55/' &&
        options.method == 'GET') {
      recordFetchCount++;
      return _json({
        'id': 55,
        'work_order': 77,
        'work_order_status': 'IN_PROGRESS',
        'station': 10,
        'station_name': 'MAS',
        'status': 'IN_PROGRESS',
        'lines': [
          {
            'id': 101,
            'item_name': 'Track Relay',
            'inspection_point': 'Coil Check',
            'value_type': 'STATUS',
            'status': recordFetchCount > 1 ? 'OK' : 'NOT_OK',
            'observation_action': recordFetchCount > 1
                ? 'Component Replaced: Track Relay. Done'
                : null,
          }
        ],
      });
    }
    if (options.path.contains('/components/')) {
      return _jsonList([
        {
          'source_id': 'c1',
          'component_code': 'REL-1',
          'name': 'Track Relay',
          'make': 'Siemens',
          'model': 'K50',
          'serial_number': 'OLD-1',
          'is_installed': true,
          'status': 'INSTALLED',
        }
      ]);
    }
    if (options.path.contains('/api/v1/assets/')) {
      return _json({
        'count': 1,
        'results': [
          {'id': 9, 'unique_id': 'AST-9', 'name': 'Signal Box'}
        ],
      });
    }
    if (options.path == '/api/v1/maintenance/records/55/replace_component/' ||
        options.path.contains('/installed-components/') ||
        options.path.contains('/log_replacement/')) {
      return _json({'id': 1, 'status': 'OK'});
    }
    return _json({'detail': 'unexpected ${options.path}'}, status: 403);
  }

  ResponseBody _json(Map<String, dynamic> body, {int status = 200}) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  ResponseBody _jsonList(List<dynamic> body, {int status = 200}) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

UserSession _session({required bool cs}) => UserSession(
      accessToken: 'tok',
      userId: 13,
      username: cs ? 'cs_tech' : 'dept_tech',
      primaryRole: AuthRole.maintenanceStaff,
      roles: const [AuthRole.maintenanceStaff],
      permissions: const ['maintenance.view', 'maintenance.edit', 'assets.replace'],
      scope: const OrgScope(level: OrgScopeLevel.depot),
      isContractStaff: cs,
    );

const _jobWork = ReplacementJobWork(
  recordId: 55,
  workOrderId: 77,
  stationId: 10,
  stationName: 'MAS',
  assetId: 9,
  assetUniqueId: 'AST-9',
  assetName: 'Signal Box',
);

void main() {
  late _MockAuthRepository mockAuthRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockAuthRepo = _MockAuthRepository();
  });

  group('S8-3c D58 replace_component for cs=true', () {
    testWidgets('(1) cs=true menu hides Enter Replaced Asset and keeps Enter Replaced Component',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;
      final s = _session(cs: true);
      when(() => mockAuthRepo.currentSession).thenReturn(s);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockAuthRepo),
            authControllerProvider
                .overrideWith(() => _FakeAuthController(Authenticated(s))),
            authenticatedDioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: ChecklistFormScreen(recordId: 55)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('checklist_overflow_menu')));
      await tester.pumpAndSettle();

      expect(find.text('Enter Replaced Asset'), findsNothing);
      expect(find.text('Enter Replaced Component'), findsOneWidget);
    });

    testWidgets('(2) cs=false menu keeps both Enter Replaced Asset and Enter Replaced Component',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;
      final s = _session(cs: false);
      when(() => mockAuthRepo.currentSession).thenReturn(s);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockAuthRepo),
            authControllerProvider
                .overrideWith(() => _FakeAuthController(Authenticated(s))),
            authenticatedDioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: ChecklistFormScreen(recordId: 55)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('checklist_overflow_menu')));
      await tester.pumpAndSettle();

      expect(find.text('Enter Replaced Asset'), findsOneWidget);
      expect(find.text('Enter Replaced Component'), findsOneWidget);
    });

    testWidgets('(3) cs=true sheet makes 0 calls to assets/, installed-components/, log_replacement/',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;
      final s = _session(cs: true);
      when(() => mockAuthRepo.currentSession).thenReturn(s);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockAuthRepo),
            authControllerProvider
                .overrideWith(() => _FakeAuthController(Authenticated(s))),
            authenticatedDioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: ChecklistFormScreen(recordId: 55)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('checklist_overflow_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter Replaced Component'));
      await tester.pumpAndSettle();

      expect(
        adapter.calls.where((c) =>
            c.path.contains('assets/') ||
            c.path.contains('installed-components/') ||
            c.path.contains('log_replacement/')),
        isEmpty,
      );
    });

    testWidgets('(4) cs=true submit POSTs records/<id>/replace_component/ with line_id and no asset_id',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;
      final s = _session(cs: true);
      when(() => mockAuthRepo.currentSession).thenReturn(s);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockAuthRepo),
            authControllerProvider
                .overrideWith(() => _FakeAuthController(Authenticated(s))),
            authenticatedDioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: ChecklistFormScreen(recordId: 55)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('checklist_overflow_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter Replaced Component'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('replace_component_line_field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Track Relay — Coil Check').last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('replace_component_new_make')), 'ABB');
      await tester.enterText(
          find.byKey(const Key('replace_component_new_serial')), 'SN-NEW-9');
      await tester.enterText(
          find.byKey(const Key('replace_component_reason')), 'Burnt coil');
      await tester.ensureVisible(
          find.byKey(const Key('replace_component_submit')));
      await tester.tap(find.byKey(const Key('replace_component_submit')));
      await tester.pumpAndSettle();

      final post = adapter.calls.where((c) =>
          c.method == 'POST' &&
          c.path == '/api/v1/maintenance/records/55/replace_component/');
      expect(post, hasLength(1));
      final body = post.first.data as Map<String, dynamic>;
      expect(body['line_id'], 101);
      expect(body.containsKey('asset_id'), isFalse);
      expect(body['new_make'], 'ABB');
      expect(body['new_serial_number'], 'SN-NEW-9');
      expect(body['reason'], 'Burnt coil');
    });

    testWidgets('(5) required-field validation blocks submit when new_make/new_serial/reason is empty',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;
      final s = _session(cs: true);
      when(() => mockAuthRepo.currentSession).thenReturn(s);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockAuthRepo),
            authControllerProvider
                .overrideWith(() => _FakeAuthController(Authenticated(s))),
            authenticatedDioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: ChecklistFormScreen(recordId: 55)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('checklist_overflow_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter Replaced Component'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('replace_component_line_field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Track Relay — Coil Check').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
          find.byKey(const Key('replace_component_submit')));
      await tester.tap(find.byKey(const Key('replace_component_submit')));
      await tester.pumpAndSettle();

      expect(
        adapter.calls.where((c) => c.method == 'POST'),
        isEmpty,
      );
      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('(6) after success on ChecklistFormScreen, the record is re-fetched',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;
      final s = _session(cs: true);
      when(() => mockAuthRepo.currentSession).thenReturn(s);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockAuthRepo),
            authControllerProvider
                .overrideWith(() => _FakeAuthController(Authenticated(s))),
            authenticatedDioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: ChecklistFormScreen(recordId: 55)),
        ),
      );
      await tester.pumpAndSettle();
      final beforeCount = adapter.recordFetchCount;

      await tester.tap(find.byKey(const Key('checklist_overflow_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter Replaced Component'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('replace_component_line_field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Track Relay — Coil Check').last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('replace_component_new_make')), 'ABB');
      await tester.enterText(
          find.byKey(const Key('replace_component_new_serial')), 'SN-9');
      await tester.enterText(
          find.byKey(const Key('replace_component_reason')), 'Faulty');
      await tester.ensureVisible(
          find.byKey(const Key('replace_component_submit')));
      await tester.tap(find.byKey(const Key('replace_component_submit')));
      await tester.pumpAndSettle();

      expect(adapter.recordFetchCount, greaterThan(beforeCount));
      expect(find.text('Component replacement recorded!'), findsOneWidget);
    });

    testWidgets('(7) cs=false submit still uses log_replacement/',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authenticatedDioProvider.overrideWithValue(dio)],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ReplaceComponentSheet(
                  jobWork: _jobWork,
                  repository: ref.read(replacementRepositoryProvider),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Non-registered asset'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('replace_component_asset_reference')), 'Panel-1');
      await tester.enterText(
          find.byKey(const Key('replace_component_name')), 'Track Relay');
      await tester.enterText(
          find.byKey(const Key('replace_component_new_make')), 'ABB');
      await tester.enterText(
          find.byKey(const Key('replace_component_new_serial')), 'SN-9');
      await tester.enterText(
          find.byKey(const Key('replace_component_reason')), 'Faulty');
      await tester.ensureVisible(
          find.byKey(const Key('replace_component_submit')));
      await tester.tap(find.byKey(const Key('replace_component_submit')));
      await tester.pumpAndSettle();

      expect(
        adapter.calls.where((c) =>
            c.method == 'POST' &&
            c.path == '/api/v1/maintenance/work-orders/77/log_replacement/'),
        hasLength(1),
      );
    });
  });
}
