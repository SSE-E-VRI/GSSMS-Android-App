import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:gssms_mobile/features/maintenance/presentation/screens/maintenance_screen.dart';

class MockDashboardRepository extends Mock implements IDashboardRepository {}

/// Test double for `AuthController` that starts already `Authenticated` with
/// a fixed session, so screens that read the session from
/// `authControllerProvider` (rather than a constructor param, like
/// `MaintenanceScreen`) can be exercised under a specific permission set.
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
  late MockDashboardRepository mockRepo;

  setUp(() {
    mockRepo = MockDashboardRepository();
  });

  const summary = DashboardSummary(
    stats: DashboardStats(
      totalWorkOrders: 20,
      complianceRate: 95.0,
      pendingTaskCount: 5,
      openComplaintCount: 1,
      inspectionCount: 3,
    ),
  );

  Widget pumpWith(UserSession session) {
    when(() => mockRepo.fetchAttention()).thenAnswer((_) async => const AttentionSummary());
    when(() => mockRepo.fetchSummary()).thenAnswer((_) async => summary);

    return ProviderScope(
      overrides: [
        dashboardRepositoryProvider.overrideWithValue(mockRepo),
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
        'renders Maintenance Management compliance and quick navigation shortcuts under AppTheme',
        (tester) async {
      await tester.pumpWidget(pumpWith(
        _sessionWithPermissions(const ['maintenance.view', 'complaints.view', 'inspections.view']),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Maintenance Management'), findsOneWidget);
      expect(find.text('Maintenance Compliance Rate'), findsOneWidget);
      expect(find.text('95.0%'), findsOneWidget);
      expect(find.text('Quick Navigation'), findsOneWidget);
      expect(find.text('Job Works'), findsOneWidget);
      expect(find.text('Complaints & Failures'), findsOneWidget);
      expect(find.text('Inspections & Notes'), findsOneWidget);
    });

    // Regression: ComplaintViewSet/InspectionViewSet each gate reads on their
    // own permission code (complaints.view / inspections.view), independent
    // of maintenance.view — a role without them would 403 on those lists, so
    // the shortcuts must not be shown just because the user can see this
    // maintenance.view-gated screen at all.
    testWidgets(
        'hides Complaints/Inspections shortcuts when the session lacks their permission',
        (tester) async {
      await tester.pumpWidget(pumpWith(
        _sessionWithPermissions(const ['maintenance.view']),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Job Works'), findsOneWidget);
      expect(find.text('Complaints & Failures'), findsNothing);
      expect(find.text('Inspections & Notes'), findsNothing);
    });
  });
}
