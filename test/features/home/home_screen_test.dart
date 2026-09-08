import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_profile.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  group('HomeScreen Widget Tests', () {
    late MockAuthRepository mockRepository;

    setUp(() {
      mockRepository = MockAuthRepository();
    });

    Widget createTestWidget(UserSession session) {
      return ProviderScope(
        overrides: [
          localCacheServiceProvider.overrideWithValue(InMemoryLocalCacheService()),
          authRepositoryProvider.overrideWithValue(mockRepository),
        ],
        child: MaterialApp(
          home: HomeScreen(session: session),
        ),
      );
    }

    testWidgets('renders Super Admin profile with wildcard permissions and all permitted modules', (tester) async {
      const superSession = UserSession(
        accessToken: 'super_token',
        username: 'super_admin_user',
        firstName: 'System',
        lastName: 'Administrator',
        primaryRole: AuthRole.superAdmin,
        roles: [AuthRole.superAdmin],
        permissions: ['*'],
        scope: OrgScope(level: OrgScopeLevel.global),
      );

      await tester.pumpWidget(createTestWidget(superSession));

      expect(find.text('System Administrator'), findsOneWidget);
      expect(find.text('Super Admin'), findsOneWidget);
      expect(find.byKey(const Key('module_maintenance')), findsOneWidget);
      expect(find.byKey(const Key('module_complaints')), findsOneWidget);
      expect(find.byKey(const Key('module_assets')), findsOneWidget);
      expect(find.byKey(const Key('module_dashboard')), findsOneWidget);
      expect(find.byKey(const Key('module_reports')), findsOneWidget);
      expect(find.byKey(const Key('module_work_orders')), findsNothing);
      expect(find.byKey(const Key('module_energy')), findsNothing);
      expect(find.byKey(const Key('home_notifications_button')), findsOneWidget);
    });

    testWidgets('SUPER_ADMIN role without wildcard in permissions does NOT display module tiles (strict server gating)', (tester) async {
      const restrictedSuperSession = UserSession(
        accessToken: 'super_token',
        username: 'restricted_super_admin',
        primaryRole: AuthRole.superAdmin,
        roles: [AuthRole.superAdmin],
        permissions: [], // Empty permissions
        scope: OrgScope(level: OrgScopeLevel.global),
      );

      await tester.pumpWidget(createTestWidget(restrictedSuperSession));

      expect(find.text('Super Admin'), findsOneWidget);
      expect(find.byKey(const Key('module_work_orders')), findsNothing);
      expect(find.byKey(const Key('module_complaints')), findsNothing);
      expect(find.byKey(const Key('home_notifications_button')), findsNothing);
      expect(find.text('No operational modules enabled by server permissions.'), findsOneWidget);
    });

    testWidgets('renders Maintenance Staff with only assigned/permitted modules', (tester) async {
      const maintenanceSession = UserSession(
        accessToken: 'maint_token',
        username: 'tech_vri',
        firstName: 'Ramesh',
        lastName: 'Kumar',
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view'],
        depotName: 'Vriddhachalam Depot',
        scope: OrgScope(
          level: OrgScopeLevel.self,
          depot: OrgUnitInfo(id: 1, code: 'VRI', name: 'Vriddhachalam Depot'),
        ),
      );

      await tester.pumpWidget(createTestWidget(maintenanceSession));

      expect(find.text('Ramesh Kumar'), findsOneWidget);
      expect(find.text('Maintenance Staff'), findsOneWidget);

      // Only the Maintenance tile should be visible (Job Works via
      // Maintenance → Job Works / Work Orders)
      expect(find.byKey(const Key('module_maintenance')), findsOneWidget);
      expect(find.byKey(const Key('module_complaints')), findsNothing);
      expect(find.byKey(const Key('module_dashboard')), findsNothing);
      expect(find.byKey(const Key('module_reports')), findsNothing);
      expect(find.byKey(const Key('home_notifications_button')), findsOneWidget);
    });

    testWidgets('renders safe empty state for restricted user without operational permissions', (tester) async {
      const guestSession = UserSession(
        accessToken: 'guest_token',
        username: 'guest_user',
        primaryRole: AuthRole.guest,
        roles: [AuthRole.guest],
        permissions: [],
        scope: OrgScope(level: OrgScopeLevel.division),
      );

      await tester.pumpWidget(createTestWidget(guestSession));

      expect(find.text('No operational modules enabled by server permissions.'), findsOneWidget);
      expect(find.byKey(const Key('home_notifications_button')), findsNothing);
    });

    testWidgets('tapping logout button triggers repository logout', (tester) async {
      when(() => mockRepository.logout()).thenAnswer((_) async {});

      const guestSession = UserSession(
        accessToken: 'guest_token',
        username: 'guest_user',
        primaryRole: AuthRole.guest,
        roles: [AuthRole.guest],
        permissions: [],
      );

      await tester.pumpWidget(createTestWidget(guestSession));

      await tester.tap(find.byKey(const Key('home_logout_button')));
      await tester.pumpAndSettle();

      verify(() => mockRepository.logout()).called(1);
    });

    testWidgets('tapping header profile opens the editable profile screen', (tester) async {
      when(() => mockRepository.getProfile()).thenAnswer(
        (_) async => const UserProfile(
          id: 1,
          username: 'guest_user',
          role: 'GUEST',
        ),
      );

      const guestSession = UserSession(
        accessToken: 'guest_token',
        username: 'guest_user',
        primaryRole: AuthRole.guest,
        roles: [AuthRole.guest],
        permissions: [],
      );

      await tester.pumpWidget(createTestWidget(guestSession));
      await tester.tap(find.byKey(const Key('home_profile_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_email_field')), findsOneWidget);
      expect(find.byKey(const Key('profile_designation_field')), findsOneWidget);
    });

    testWidgets('CONTROL_CELL dashboard.view does not unlock maintenance or notifications',
        (tester) async {
      const cell = UserSession(
        accessToken: 't',
        username: 'control',
        primaryRole: AuthRole.controlCell,
        roles: [AuthRole.controlCell],
        permissions: ['dashboard.view', 'complaints.view', 'reports.view'],
      );

      await tester.pumpWidget(createTestWidget(cell));

      expect(find.byKey(const Key('module_dashboard')), findsOneWidget);
      expect(find.byKey(const Key('module_complaints')), findsOneWidget);
      expect(find.byKey(const Key('module_reports')), findsOneWidget);
      expect(find.byKey(const Key('module_maintenance')), findsNothing);
      expect(find.byKey(const Key('home_notifications_button')), findsNothing);
    });

    testWidgets('reports.view alone shows only Reports', (tester) async {
      const auditor = UserSession(
        accessToken: 't',
        username: 'auditor',
        primaryRole: AuthRole.divHqUser,
        roles: [AuthRole.divHqUser],
        permissions: ['reports.view'],
      );

      await tester.pumpWidget(createTestWidget(auditor));

      expect(find.byKey(const Key('module_reports')), findsOneWidget);
      expect(find.byKey(const Key('module_maintenance')), findsNothing);
      expect(find.byKey(const Key('module_dashboard')), findsNothing);
    });

    testWidgets('EB_BILL_CLERK sees the Energy placeholder instead of an empty grid',
        (tester) async {
      const clerk = UserSession(
        accessToken: 't',
        username: 'clerk',
        primaryRole: AuthRole.ebBillClerk,
        roles: [AuthRole.ebBillClerk],
        permissions: ['energy.view', 'energy.create'],
      );

      await tester.pumpWidget(createTestWidget(clerk));

      expect(find.byKey(const Key('module_energy')), findsOneWidget);
      expect(find.byKey(const Key('module_maintenance')), findsNothing);
      expect(find.text('No operational modules enabled by server permissions.'), findsNothing);
    });
  });
}
