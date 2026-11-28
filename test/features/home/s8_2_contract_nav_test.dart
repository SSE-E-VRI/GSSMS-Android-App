import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/services/profile_photo_cache.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_profile.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/auth/presentation/screens/user_profile_screen.dart';
import 'package:gssms_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:gssms_mobile/features/more/presentation/screens/more_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

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
    if (options.path.contains('staff-workorders')) {
      return ResponseBody.fromString(
        jsonEncode({
          'count': 1,
          'results': [
            {
              'id': 42,
              'work_order_number': 'WO-CS-0042',
              'title': 'Check Traction Transformer',
              'status': 'ASSIGNED',
              'priority': 'MEDIUM',
              'work_type': 'PM',
              'station_name': 'MAS',
            }
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'detail': 'unexpected call to ${options.path}'}),
      403,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

UserSession _buildSession({
  required bool isContractStaff,
  List<AuthRole> roles = const [AuthRole.maintenanceStaff, AuthRole.depotIncharge],
}) {
  return UserSession(
    accessToken: 'tok',
    userId: 13,
    username: isContractStaff ? 'cs_tech' : 'dept_tech',
    firstName: isContractStaff ? 'Contract' : 'Dept',
    lastName: 'Tech',
    primaryRole: AuthRole.maintenanceStaff,
    roles: roles,
    permissions: const [
      'maintenance.view',
      'maintenance.edit',
      'assets.view',
      'complaints.view',
      'inspections.view',
      'dashboard.view',
      'reports.view',
    ],
    scope: const OrgScope(level: OrgScopeLevel.depot),
    isContractStaff: isContractStaff,
  );
}

void main() {
  late MockAuthRepository mockRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRepo = MockAuthRepository();
  });

  group('S8-2 Contract staff navigation & Home', () {
    testWidgets(
        'A. cs=true Home makes zero calls to refused endpoints and shows own job works',
        (tester) async {
      final adapter = _RecordingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..httpClientAdapter = adapter;
      final csSession = _buildSession(
        isContractStaff: true,
        roles: const [AuthRole.maintenanceStaff],
      );
      when(() => mockRepo.currentSession).thenReturn(csSession);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthController(Authenticated(csSession)),
            ),
            authenticatedDioProvider.overrideWithValue(dio),
          ],
          child: MaterialApp(
            home: HomeScreen(session: csSession, autoLoadData: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final forbidden in const [
        'schedules/attention/',
        'dashboard/summary/',
        'complaints/',
        'inspections/',
        'assets/',
      ]) {
        expect(
          adapter.paths.where((p) => p.contains(forbidden)),
          isEmpty,
          reason: 'Contract staff Home must not call $forbidden',
        );
      }

      expect(
        adapter.paths.where((p) => p.contains('staff-workorders/')),
        isNotEmpty,
        reason: 'Contract staff Home should fetch own staff-workorders/',
      );
      expect(find.text('Check Traction Transformer'), findsWidgets);
    });

    testWidgets('B. Home hides refused tabs, quick actions and modules for cs=true',
        (tester) async {
      final csSession = _buildSession(
        isContractStaff: true,
        roles: const [AuthRole.maintenanceStaff],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(home: HomeScreen(session: csSession)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav_home')), findsOneWidget);
      expect(find.byKey(const Key('nav_work')), findsOneWidget);
      expect(find.byKey(const Key('nav_more')), findsOneWidget);
      expect(find.byKey(const Key('nav_assets')), findsNothing);

      expect(find.byKey(const Key('quick_action_scan_asset')), findsNothing);
      expect(find.byKey(const Key('quick_action_work_orders')), findsOneWidget);

      for (final key in const [
        'module_dashboard',
        'module_maintenance',
        'module_complaints',
        'module_inspections',
        'module_deficiencies',
        'module_assets',
        'module_reports',
        'module_energy',
      ]) {
        expect(find.byKey(Key(key)), findsNothing,
            reason: '$key must be hidden for cs=true');
      }
    });

    testWidgets('B. Home keeps departmental destinations unchanged for cs=false',
        (tester) async {
      final deptSession = _buildSession(isContractStaff: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider
                .overrideWithValue(InMemoryLocalCacheService()),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(home: HomeScreen(session: deptSession)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav_assets')), findsOneWidget);
      expect(find.byKey(const Key('quick_action_scan_asset')), findsOneWidget);
      expect(find.byKey(const Key('module_maintenance')), findsOneWidget);
      expect(find.byKey(const Key('module_complaints')), findsOneWidget);
      expect(find.byKey(const Key('module_inspections')), findsOneWidget);
      expect(find.byKey(const Key('module_assets')), findsOneWidget);
      expect(find.byKey(const Key('module_dashboard')), findsOneWidget);
      expect(find.byKey(const Key('module_reports')), findsOneWidget);
    });

    testWidgets('B. MoreScreen hides refused modules for cs=true and keeps them for cs=false',
        (tester) async {
      final csSession = _buildSession(
        isContractStaff: true,
        roles: const [AuthRole.maintenanceStaff],
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: MoreScreen(session: csSession)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('more_profile_card')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('more_menu_logout')),
        100,
      );
      expect(find.byKey(const Key('more_menu_profile')), findsOneWidget);
      expect(find.byKey(const Key('more_menu_notifications')), findsOneWidget);
      expect(find.byKey(const Key('more_menu_logout')), findsOneWidget);

      for (final key in const [
        'more_menu_dashboard',
        'more_menu_maintenance',
        'more_menu_deficiencies',
        'more_menu_reports',
        'more_menu_energy',
      ]) {
        expect(find.byKey(Key(key)), findsNothing);
      }

      final deptSession = _buildSession(isContractStaff: false);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: MoreScreen(session: deptSession)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('more_menu_dashboard')), findsOneWidget);
      expect(find.byKey(const Key('more_menu_maintenance')), findsOneWidget);
      expect(find.byKey(const Key('more_menu_reports')), findsOneWidget);
    });

    testWidgets('B. UserProfileScreen hides editable PATCH fields for cs=true and keeps D117 password change',
        (tester) async {
      final dir = Directory.systemTemp.createTempSync('s8_2_prof_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      const profile = UserProfile(
        id: 13,
        username: 'cs_tech',
        role: 'MAINTENANCE_STAFF',
        email: 'cs@example.com',
        phoneNumber: '9990001111',
        designation: 'Contractor',
      );
      final csSession = _buildSession(
        isContractStaff: true,
        roles: const [AuthRole.maintenanceStaff],
      );
      when(() => mockRepo.currentSession).thenReturn(csSession);
      when(() => mockRepo.getProfile()).thenAnswer((_) async => profile);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(mockRepo),
            profilePhotoCacheProvider.overrideWithValue(
              ProfilePhotoCache(baseUrl: 'http://localhost:8000', storageDir: dir),
            ),
          ],
          child: const MaterialApp(home: UserProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_email_field')), findsNothing);
      expect(find.byKey(const Key('profile_phone_field')), findsNothing);
      expect(find.byKey(const Key('profile_designation_field')), findsNothing);
      expect(find.byKey(const Key('profile_save_changes_button')), findsNothing);

      expect(find.byKey(const Key('profile_current_password_field')), findsOneWidget);
      expect(find.byKey(const Key('profile_new_password_field')), findsOneWidget);
      expect(find.byKey(const Key('profile_confirm_password_field')), findsOneWidget);
      expect(find.byKey(const Key('profile_update_password_button')), findsOneWidget);
    });
  });
}
