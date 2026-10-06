import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:gssms_mobile/features/deficiencies/data/deficiency_repository.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';
import 'package:gssms_mobile/features/deficiencies/presentation/screens/deficiency_list_screen.dart';
import 'package:gssms_mobile/features/maintenance/presentation/screens/maintenance_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockDashboardRepository extends Mock implements IDashboardRepository {}
class MockDeficiencyRepository extends Mock implements IDeficiencyRepository {}

class _FakeAuthenticatedController extends AuthController {
  _FakeAuthenticatedController(this._session);

  final UserSession _session;

  @override
  AuthState build() => Authenticated(_session);
}

UserSession _sessionWithPermissions(List<String> permissions) {
  return UserSession(
    accessToken: 'test_token',
    username: 'depot_incharge',
    firstName: 'Vri',
    lastName: '',
    primaryRole: AuthRole.depotIncharge,
    roles: const [AuthRole.depotIncharge],
    permissions: permissions,
    scope: const OrgScope(level: OrgScopeLevel.depot),
  );
}

void main() {
  late MockDashboardRepository mockDashboardRepo;
  late MockDeficiencyRepository mockDeficiencyRepo;

  setUp(() {
    mockDashboardRepo = MockDashboardRepository();
    mockDeficiencyRepo = MockDeficiencyRepository();
  });

  const defaultSummary = DashboardSummary(
    stats: DashboardStats(
      totalWorkOrders: 20,
      complianceRate: 95.0,
      pendingTaskCount: 5,
      openComplaintCount: 1,
      inspectionCount: 3,
    ),
  );

  final mixedDeficiencies = [
    const Deficiency(id: 1, description: 'D1', status: DeficiencyStatus.open),
    const Deficiency(id: 2, description: 'D2', status: DeficiencyStatus.open),
    const Deficiency(id: 3, description: 'D3', status: DeficiencyStatus.open),
    const Deficiency(id: 4, description: 'D4', status: DeficiencyStatus.inProgress),
    const Deficiency(id: 5, description: 'D5', status: DeficiencyStatus.resolved),
  ];

  Widget pumpWith(
    UserSession session, {
    DashboardSummary summary = defaultSummary,
    List<Deficiency>? deficiencies,
    bool deficiencyThrows = false,
  }) {
    when(() => mockDashboardRepo.fetchAttention(
          zoneId: any(named: 'zoneId'),
          divisionId: any(named: 'divisionId'),
          depotId: any(named: 'depotId'),
        )).thenAnswer((_) async => const AttentionSummary());
    when(() => mockDashboardRepo.fetchSummary(
          zoneId: any(named: 'zoneId'),
          divisionId: any(named: 'divisionId'),
          depotId: any(named: 'depotId'),
        )).thenAnswer((_) async => summary);

    if (deficiencyThrows) {
      when(() => mockDeficiencyRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenThrow(Exception('Network error'));
    } else {
      when(() => mockDeficiencyRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => deficiencies ?? mixedDeficiencies);
    }

    return ProviderScope(
      overrides: [
        dashboardRepositoryProvider.overrideWithValue(mockDashboardRepo),
        deficiencyRepositoryProvider.overrideWithValue(mockDeficiencyRepo),
        authControllerProvider.overrideWith(() => _FakeAuthenticatedController(session)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const MaintenanceScreen(),
      ),
    );
  }

  group('MaintenanceScreen Widget Tests', () {
    testWidgets(
        'renders Maintenance Management compliance and quick navigation cards with updated wording',
        (tester) async {
      await tester.pumpWidget(pumpWith(
        _sessionWithPermissions(const [
          'maintenance.view',
          'complaints.view',
          'inspections.view',
          'assets.view',
        ]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Maintenance Management'), findsOneWidget);
      expect(find.text('Maintenance Compliance Rate'), findsOneWidget);
      expect(find.text('95.0%'), findsOneWidget);
      expect(find.text('Quick Navigation'), findsOneWidget);

      // Verify titles
      expect(find.text('Job Works'), findsOneWidget);
      expect(find.text('Breakdowns'), findsOneWidget);
      expect(find.text('Inspections'), findsOneWidget);
      expect(find.text('Deficiencies'), findsOneWidget);
      expect(find.text('Complaints & Failures'), findsNothing);
      expect(find.text('Inspections & Notes'), findsNothing);

      // Verify subtitles with plural / singular logic
      expect(find.text('5 pending Job Works'), findsOneWidget);
      expect(find.text('1 open breakdown'), findsOneWidget); // singular
      expect(find.text('3 inspections'), findsOneWidget);
      expect(find.text('3 need action'), findsOneWidget); // 3 of 5 are needs action
    });

    testWidgets('formats singular subtitles when counts are 1', (tester) async {
      const singularSummary = DashboardSummary(
        stats: DashboardStats(
          totalWorkOrders: 1,
          complianceRate: 100.0,
          pendingTaskCount: 1,
          openComplaintCount: 1,
          inspectionCount: 1,
        ),
      );

      await tester.pumpWidget(pumpWith(
        _sessionWithPermissions(const [
          'maintenance.view',
          'complaints.view',
          'inspections.view',
          'assets.view',
        ]),
        summary: singularSummary,
        deficiencies: const [
          Deficiency(id: 1, description: 'Only one', status: DeficiencyStatus.open),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('1 pending Job Work'), findsOneWidget);
      expect(find.text('1 open breakdown'), findsOneWidget);
      expect(find.text('1 inspection'), findsOneWidget);
      expect(find.text('1 need action'), findsOneWidget);
    });

    testWidgets('Job Works tile uses scheduled_task_count when the payload has it', (tester) async {
      await tester.pumpWidget(pumpWith(
        _sessionWithPermissions(const ['maintenance.view']),
        summary: const DashboardSummary(
          stats: DashboardStats(pendingTaskCount: 5, scheduledTaskCount: 2),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('2 pending Job Works'), findsOneWidget);
      expect(find.text('5 pending Job Works'), findsNothing);
    });

    testWidgets('hides shortcuts when the session lacks their permissions', (tester) async {
      await tester.pumpWidget(pumpWith(
        _sessionWithPermissions(const ['maintenance.view']),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Job Works'), findsOneWidget);
      expect(find.text('Breakdowns'), findsNothing);
      expect(find.text('Inspections'), findsNothing);
      expect(find.text('Deficiencies'), findsNothing);
    });

    testWidgets('hides Deficiencies card for technician session with assets.view', (tester) async {
      const technicianSession = UserSession(
        accessToken: 'tech_token',
        username: 'tech_user',
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: [
          'maintenance.view',
          'maintenance.edit',
          'assets.view',
          'assets.replace',
        ],
      );

      await tester.pumpWidget(pumpWith(technicianSession));
      await tester.pumpAndSettle();

      expect(find.text('Deficiencies'), findsNothing);
      expect(find.text('Job Works'), findsOneWidget);
    });

    testWidgets('shows Deficiencies card for Depot Incharge with assets.view', (tester) async {
      await tester.pumpWidget(pumpWith(
        _sessionWithPermissions(const [
          'maintenance.view',
          'assets.view',
        ]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Deficiencies'), findsOneWidget);
    });

    testWidgets('Deficiencies subtitle shows All clear when 0 need action', (tester) async {
      await tester.pumpWidget(pumpWith(
        _sessionWithPermissions(const [
          'maintenance.view',
          'assets.view',
        ]),
        deficiencies: const [
          Deficiency(id: 1, description: 'D1', status: DeficiencyStatus.inProgress),
          Deficiency(id: 2, description: 'D2', status: DeficiencyStatus.resolved),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Deficiencies'), findsOneWidget);
      expect(find.text('All clear'), findsOneWidget);
    });

    testWidgets('Deficiencies subtitle gracefully falls back to View deficiencies on error',
        (tester) async {
      await tester.pumpWidget(pumpWith(
        _sessionWithPermissions(const [
          'maintenance.view',
          'assets.view',
        ]),
        deficiencyThrows: true,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Deficiencies'), findsOneWidget);
      expect(find.text('View deficiencies'), findsOneWidget);
      // Main screen content remains intact
      expect(find.text('Maintenance Management'), findsOneWidget);
      expect(find.text('Job Works'), findsOneWidget);
    });

    testWidgets('tapping Deficiencies pushes DeficiencyListScreen', (tester) async {
      await tester.pumpWidget(pumpWith(
        _sessionWithPermissions(const [
          'maintenance.view',
          'assets.view',
        ]),
      ));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deficiencies'));
      await tester.pumpAndSettle();

      expect(find.byType(DeficiencyListScreen), findsOneWidget);
    });

    testWidgets('pull-to-refresh re-requests dashboard and deficiency count', (tester) async {
      await tester.pumpWidget(pumpWith(
        _sessionWithPermissions(const [
          'maintenance.view',
          'assets.view',
        ]),
      ));
      await tester.pumpAndSettle();

      verify(() => mockDashboardRepo.fetchSummary(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).called(1);
      verify(() => mockDeficiencyRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).called(1);

      // Trigger refresh
      final refreshIndicator = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      await refreshIndicator.onRefresh();
      await tester.pumpAndSettle();

      verify(() => mockDashboardRepo.fetchSummary(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).called(1);
      verify(() => mockDeficiencyRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).called(1);
    });
  });
}
