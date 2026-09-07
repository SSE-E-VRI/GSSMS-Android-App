import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:gssms_mobile/features/dashboard/presentation/screens/dashboard_screen.dart';

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
      expect(find.text('Operational Metrics'), findsOneWidget);
      expect(find.text('Compliance Rate'), findsOneWidget);
      expect(find.text('88.0%'), findsOneWidget);
    });
  });
}
