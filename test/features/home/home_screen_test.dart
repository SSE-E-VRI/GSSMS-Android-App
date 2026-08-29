import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
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
      expect(find.text('Level: GLOBAL'), findsOneWidget);

      // Super admin with wildcard has all modules
      expect(find.byKey(const Key('module_work_orders')), findsOneWidget);
      expect(find.byKey(const Key('module_complaints')), findsOneWidget);
      expect(find.byKey(const Key('module_assets')), findsOneWidget);
      expect(find.byKey(const Key('module_energy')), findsOneWidget);
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
      expect(find.text('Level: SELF'), findsOneWidget);
      expect(find.text('Vriddhachalam Depot'), findsOneWidget);

      // Only maintenance / work orders should be visible
      expect(find.byKey(const Key('module_work_orders')), findsOneWidget);
      expect(find.byKey(const Key('module_complaints')), findsNothing);
      expect(find.byKey(const Key('module_energy')), findsNothing);
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
      expect(find.byKey(const Key('module_work_orders')), findsNothing);
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
  });
}
