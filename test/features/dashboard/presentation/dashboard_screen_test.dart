import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:gssms_mobile/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import '../../../helpers/fake_auth.dart';

class MockDashboardRepository extends Mock implements IDashboardRepository {}

void main() {
  late MockDashboardRepository mockRepo;

  setUp(() {
    mockRepo = MockDashboardRepository();
  });

  group('DashboardScreen Widget Tests', () {
    testWidgets('renders Dashboard header, attention section and KPI metrics under AppTheme', (tester) async {
      const attention = AttentionSummary(
        overdue: [
          AttentionItem(id: 1, masterName: 'Monthly Transformer Check', stationName: 'Sendurai', daysOverdue: 3),
        ],
        dueSoon: [],
      );
      const summary = DashboardSummary(
        stats: DashboardStats(
          totalWorkOrders: 15,
          complianceRate: 88.0,
          pendingTaskCount: 4,
          openComplaintCount: 2,
        ),
      );

      when(() => mockRepo.fetchAttention()).thenAnswer((_) async => attention);
      when(() => mockRepo.fetchSummary()).thenAnswer((_) async => summary);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(
                permissions: const ['dashboard.view', 'maintenance.view'],
              )),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const DashboardScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Attention Required'), findsOneWidget);
      expect(find.text('Monthly Transformer Check'), findsOneWidget);
      // The new Pending Actions card lengthens the list, so lower sections
      // are lazily built on scroll — drive the outer Scrollable explicitly
      // (the inner KPI GridView is a second Scrollable, so the default
      // scrollable finder is ambiguous).
      await tester.scrollUntilVisible(find.text('Pending Actions'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard_pending_actions')), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Operational Metrics'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Operational Metrics'), findsOneWidget);
      expect(find.text('Compliance Rate'), findsOneWidget);
      expect(find.text('88.0%'), findsOneWidget);
    });

    testWidgets('shows due-soon badge, type stats and itemised pending actions', (tester) async {
      const attention = AttentionSummary(
        overdue: [],
        dueSoon: [
          AttentionItem(id: 2, masterName: 'LC Gate check', stationName: 'TPJ', dueDate: null),
        ],
      );
      const summary = DashboardSummary(
        stats: DashboardStats(
          totalWorkOrders: 6,
          complianceRate: 70.0,
          typeStats: [MaintenanceTypeStat(label: 'Preventive', count: 4, percentage: 66.0)],
        ),
        pendingTasks: [
          PendingAction(id: 9, kind: PendingActionKind.verification, title: 'Verify TR-01 job', subtitle: 'VRI', workOrderId: 101),
        ],
      );

      when(() => mockRepo.fetchAttention()).thenAnswer((_) async => attention);
      when(() => mockRepo.fetchSummary()).thenAnswer((_) async => summary);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(
                permissions: const ['dashboard.view', 'maintenance.view'],
              )),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('attention_due_soon_badge')), findsOneWidget);
      expect(find.text('Due in 7 Days'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const Key('dashboard_type_stats')), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard_type_stats')), findsOneWidget);
      expect(find.textContaining('Preventive'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Verify TR-01 job'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Verify TR-01 job'), findsOneWidget);
    });

    testWidgets('session=null shows permission denied and no pending work-order rows',
        (tester) async {
      when(() => mockRepo.fetchAttention())
          .thenAnswer((_) async => const AttentionSummary());
      when(() => mockRepo.fetchSummary()).thenAnswer(
        (_) async => const DashboardSummary(
          stats: DashboardStats(pendingTaskCount: 4),
          pendingTasks: [
            PendingAction(
                id: 9,
                kind: PendingActionKind.verification,
                title: 'Verify TR-01 job',
                workOrderId: 101),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dashboardRepositoryProvider.overrideWithValue(mockRepo)],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to view this screen.'),
          findsOneWidget);
      expect(find.text('Verify TR-01 job'), findsNothing);
      expect(find.byKey(const Key('dashboard_pending_actions')), findsNothing);
    });

    testWidgets('dashboard.view without maintenance.view does not open Job Work detail',
        (tester) async {
      const summary = DashboardSummary(
        stats: DashboardStats(totalWorkOrders: 1),
        pendingTasks: [
          PendingAction(
              id: 9,
              kind: PendingActionKind.verification,
              title: 'Verify TR-01 job',
              workOrderId: 101),
        ],
      );
      when(() => mockRepo.fetchAttention())
          .thenAnswer((_) async => const AttentionSummary());
      when(() => mockRepo.fetchSummary()).thenAnswer((_) async => summary);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(
                permissions: const ['dashboard.view'],
              )),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Verify TR-01 job'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Verify TR-01 job'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkOrderDetailScreen), findsNothing);
    });
  });
}
