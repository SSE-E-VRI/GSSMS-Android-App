import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_profile.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class FakeWorkOrderListController extends WorkOrderListController {
  FakeWorkOrderListController(this._initialState);
  final WorkOrderListState _initialState;

  @override
  WorkOrderListState build() => _initialState;

  @override
  Future<void> fetchWorkOrders({bool forceRefresh = false}) async {}
}

void main() {
  group('HomeScreen Widget Tests', () {
    late MockAuthRepository mockRepository;

    setUp(() {
      mockRepository = MockAuthRepository();
    });

    Widget createTestWidget(
      UserSession session, {
      WorkOrderListState? workOrderListState,
    }) {
      return ProviderScope(
        overrides: [
          localCacheServiceProvider.overrideWithValue(InMemoryLocalCacheService()),
          authRepositoryProvider.overrideWithValue(mockRepository),
          if (workOrderListState != null)
            workOrderListControllerProvider.overrideWith(
              () => FakeWorkOrderListController(workOrderListState),
            ),
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

    testWidgets('logout asks for confirmation, then signs out', (tester) async {
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
      verifyNever(() => mockRepository.logout());
      expect(find.byKey(const Key('sign_out_unsynced_warning')), findsNothing);

      await tester.tap(find.byKey(const Key('sign_out_confirm_button')));
      await tester.pumpAndSettle();

      verify(() => mockRepository.logout()).called(1);
    });

    testWidgets('cancelling the sign-out dialog keeps the session', (tester) async {
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
      await tester.tap(find.byKey(const Key('sign_out_cancel_button')));
      await tester.pumpAndSettle();

      verifyNever(() => mockRepository.logout());
    });

    // Regression B3: sign-out wipes the offline outbox; an accidental tap
    // used to discard queued checklist readings/photos without warning.
    testWidgets('sign-out warns how many unsynced changes will be discarded',
        (tester) async {
      final cache = InMemoryLocalCacheService();
      await cache.saveOutboxCommands([
        for (var i = 0; i < 2; i++)
          OutboxCommand(
            idempotencyKey: 'k$i',
            type: OutboxCommandType.submitLine,
            entityId: 7,
            payload: const {'line_id': 1},
            createdAt: DateTime(2026, 9, 11),
          ),
      ]);
      const guestSession = UserSession(
        accessToken: 'guest_token',
        username: 'guest_user',
        primaryRole: AuthRole.guest,
        roles: [AuthRole.guest],
        permissions: [],
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          localCacheServiceProvider.overrideWithValue(cache),
          authRepositoryProvider.overrideWithValue(mockRepository),
        ],
        child: const MaterialApp(home: HomeScreen(session: guestSession)),
      ));
      await tester.tap(find.byKey(const Key('home_logout_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sign_out_unsynced_warning')), findsOneWidget);
      expect(find.textContaining('2 changes saved on this device'), findsOneWidget);
      expect(find.text('Discard and sign out'), findsOneWidget);
      verifyNever(() => mockRepository.logout());
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

    testWidgets('NavigationBar destinations resolved per role permissions', (tester) async {
      // 1. Super Admin sees Home, Work, Assets, More
      const superSession = UserSession(
        accessToken: 't',
        username: 'admin',
        primaryRole: AuthRole.superAdmin,
        roles: [AuthRole.superAdmin],
        permissions: ['*'],
      );
      await tester.pumpWidget(createTestWidget(superSession));

      expect(find.byKey(const Key('nav_home')), findsOneWidget);
      expect(find.byKey(const Key('nav_work')), findsOneWidget);
      expect(find.byKey(const Key('nav_assets')), findsOneWidget);
      expect(find.byKey(const Key('nav_more')), findsOneWidget);

      // 2. Technician with maintenance.view sees Home, Work, More (no Assets)
      const techSession = UserSession(
        accessToken: 't',
        username: 'tech',
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view'],
      );
      await tester.pumpWidget(createTestWidget(techSession));

      expect(find.byKey(const Key('nav_home')), findsOneWidget);
      expect(find.byKey(const Key('nav_work')), findsOneWidget);
      expect(find.byKey(const Key('nav_assets')), findsNothing);
      expect(find.byKey(const Key('nav_more')), findsOneWidget);

      // 3. Auditor with reports.view sees Home, More (no Work, no Assets)
      const auditorSession = UserSession(
        accessToken: 't',
        username: 'auditor',
        primaryRole: AuthRole.divHqUser,
        roles: [AuthRole.divHqUser],
        permissions: ['reports.view'],
      );
      await tester.pumpWidget(createTestWidget(auditorSession));

      expect(find.byKey(const Key('nav_home')), findsOneWidget);
      expect(find.byKey(const Key('nav_work')), findsNothing);
      expect(find.byKey(const Key('nav_assets')), findsNothing);
      expect(find.byKey(const Key('nav_more')), findsOneWidget);

      // 4. Restricted guest sees Home, More
      const guestSession = UserSession(
        accessToken: 't',
        username: 'guest',
        primaryRole: AuthRole.guest,
        roles: [AuthRole.guest],
        permissions: [],
      );
      await tester.pumpWidget(createTestWidget(guestSession));

      expect(find.byKey(const Key('nav_home')), findsOneWidget);
      expect(find.byKey(const Key('nav_work')), findsNothing);
      expect(find.byKey(const Key('nav_assets')), findsNothing);
      expect(find.byKey(const Key('nav_more')), findsOneWidget);
    });

    testWidgets('switching tab to More displays MoreScreen profile card', (tester) async {
      const superSession = UserSession(
        accessToken: 't',
        username: 'admin',
        primaryRole: AuthRole.superAdmin,
        roles: [AuthRole.superAdmin],
        permissions: ['*'],
      );
      await tester.pumpWidget(createTestWidget(superSession));

      await tester.tap(find.byKey(const Key('nav_more')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('more_profile_card')), findsOneWidget);
      expect(find.byKey(const Key('more_menu_dashboard')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('more_menu_profile')), 100);
      expect(find.byKey(const Key('more_menu_profile')), findsOneWidget);
    });

    testWidgets('Quick Actions row respects permissions', (tester) async {
      // Complaint/Inspection creation lives only in their own module's list
      // screen FAB now, not duplicated as a Home quick action — so this row
      // only ever carries Scan Asset + Work Orders.
      // Super admin sees all quick action chips
      const superSession = UserSession(
        accessToken: 't',
        username: 'admin',
        primaryRole: AuthRole.superAdmin,
        roles: [AuthRole.superAdmin],
        permissions: ['*'],
      );
      await tester.pumpWidget(createTestWidget(superSession));

      expect(find.byKey(const Key('quick_action_scan_asset')), findsOneWidget);
      expect(find.byKey(const Key('quick_action_work_orders')), findsOneWidget);

      // Scan Asset resolves the code against the asset register, which needs
      // assets.view — a guest without it would only ever get a 403.
      const guestSession = UserSession(
        accessToken: 't',
        username: 'guest',
        primaryRole: AuthRole.guest,
        roles: [AuthRole.guest],
        permissions: [],
      );
      await tester.pumpWidget(createTestWidget(guestSession));

      expect(find.byKey(const Key('quick_action_scan_asset')), findsNothing);
      expect(find.byKey(const Key('quick_action_work_orders')), findsNothing);

      const assetViewer = UserSession(
        accessToken: 't',
        username: 'viewer',
        primaryRole: AuthRole.viewer,
        roles: [AuthRole.viewer],
        permissions: ['assets.view'],
      );
      await tester.pumpWidget(createTestWidget(assetViewer));

      expect(find.byKey(const Key('quick_action_scan_asset')), findsOneWidget);
      expect(find.byKey(const Key('quick_action_work_orders')), findsNothing);
    });

    testWidgets('My Work card shows in-progress work order with CONTINUE button', (tester) async {
      const techSession = UserSession(
        accessToken: 't',
        username: 'tech',
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view'],
      );

      const inProgressOrder = WorkOrder(
        id: 42,
        ticketNumber: 'WO-2026-0042',
        status: WorkOrderStatus.inProgress,
        type: WorkOrderType.preventive,
        title: 'Overhaul Transformer Bay 2',
        stationName: 'Vriddhachalam Junction',
      );

      await tester.pumpWidget(createTestWidget(
        techSession,
        workOrderListState: const WorkOrderListLoaded(
          workOrders: [inProgressOrder],
        ),
      ));

      expect(find.text('MY WORK'), findsOneWidget);
      expect(find.text('Overhaul Transformer Bay 2'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.byKey(const Key('home_continue_work_button')), findsOneWidget);
      expect(find.byKey(const Key('home_start_work_button')), findsNothing);
    });

    testWidgets('My Work card shows assigned work order with START button', (tester) async {
      const techSession = UserSession(
        accessToken: 't',
        username: 'tech',
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view'],
      );

      const assignedOrder = WorkOrder(
        id: 43,
        ticketNumber: 'WO-2026-0043',
        status: WorkOrderStatus.assigned,
        type: WorkOrderType.corrective,
        title: 'Check Breaker Trip Alarm',
        stationName: 'Vriddhachalam Junction',
      );

      await tester.pumpWidget(createTestWidget(
        techSession,
        workOrderListState: const WorkOrderListLoaded(
          workOrders: [assignedOrder],
        ),
      ));

      expect(find.text('MY WORK'), findsOneWidget);
      expect(find.text('Check Breaker Trip Alarm'), findsOneWidget);
      expect(find.text('Assigned to You'), findsOneWidget);
      expect(find.byKey(const Key('home_start_work_button')), findsOneWidget);
      expect(find.byKey(const Key('home_continue_work_button')), findsNothing);
    });

    testWidgets('My Work shows empty ready state when no active work orders', (tester) async {
      const techSession = UserSession(
        accessToken: 't',
        username: 'tech',
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view'],
      );

      await tester.pumpWidget(createTestWidget(
        techSession,
        workOrderListState: const WorkOrderListLoaded(
          workOrders: [],
        ),
      ));

      expect(find.text('MY WORK'), findsOneWidget);
      expect(
        find.text('No active job works in progress. Ready for new field assignments.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home_continue_work_button')), findsNothing);
      expect(find.byKey(const Key('home_start_work_button')), findsNothing);
    });

    testWidgets('My Work is hidden for Depot Incharge even with an active work order',
        (tester) async {
      // Depot Incharge holds maintenance.view (they oversee the depot's work),
      // but "My Work" surfaces the record assigned to the viewer as executor --
      // a technician concept. Gating on the permission alone showed a job that
      // wasn't the Incharge's to execute.
      const inchargeSession = UserSession(
        accessToken: 't',
        username: 'incharge',
        primaryRole: AuthRole.depotIncharge,
        roles: [AuthRole.depotIncharge],
        permissions: ['maintenance.view'],
      );

      const inProgressOrder = WorkOrder(
        id: 42,
        ticketNumber: 'WO-2026-0042',
        status: WorkOrderStatus.inProgress,
        type: WorkOrderType.preventive,
        title: 'Overhaul Transformer Bay 2',
        stationName: 'Vriddhachalam Junction',
      );

      await tester.pumpWidget(createTestWidget(
        inchargeSession,
        workOrderListState: const WorkOrderListLoaded(
          workOrders: [inProgressOrder],
        ),
      ));

      expect(find.text('MY WORK'), findsNothing);
      expect(find.text('Overhaul Transformer Bay 2'), findsNothing);
    });

    testWidgets('My Work is hidden for every other role in the RBAC hierarchy',
        (tester) async {
      for (final role in [
        AuthRole.superAdmin,
        AuthRole.zrAdmin,
        AuthRole.zrHqUser,
        AuthRole.divAdmin,
        AuthRole.divHqUser,
        AuthRole.depotIncharge,
        AuthRole.depotUser,
        AuthRole.controlCell,
        AuthRole.ebBillClerk,
        AuthRole.guest,
        AuthRole.viewer,
      ]) {
        final session = UserSession(
          accessToken: 't',
          username: 'u_${role.code}',
          primaryRole: role,
          roles: [role],
          permissions: const ['maintenance.view'],
        );

        await tester.pumpWidget(createTestWidget(session));
        await tester.pump();

        expect(
          find.text('MY WORK'),
          findsNothing,
          reason: '${role.code} must not see the technician My Work banner',
        );
      }
    });
  });
}
