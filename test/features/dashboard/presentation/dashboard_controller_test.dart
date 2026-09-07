import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_state.dart';

class MockDashboardRepository extends Mock implements IDashboardRepository {}

void main() {
  late MockDashboardRepository mockRepo;

  setUp(() {
    mockRepo = MockDashboardRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        dashboardRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('DashboardController Unit Tests', () {
    test('initial state is DashboardLoading', () {
      final container = makeContainer();
      final state = container.read(dashboardControllerProvider);
      expect(state, isA<DashboardLoading>());
    });

    test('loadDashboard transitions to DashboardLoaded on success', () async {
      const attention = AttentionSummary(overdue: [], dueSoon: []);
      const summary = DashboardSummary(stats: DashboardStats(totalWorkOrders: 10, complianceRate: 92.5));

      when(() => mockRepo.fetchAttention()).thenAnswer((_) async => attention);
      when(() => mockRepo.fetchSummary()).thenAnswer((_) async => summary);

      final container = makeContainer();
      final controller = container.read(dashboardControllerProvider.notifier);

      await controller.loadDashboard();

      final state = container.read(dashboardControllerProvider);
      expect(state, isA<DashboardLoaded>());
      final loaded = state as DashboardLoaded;
      expect(loaded.summary.stats.totalWorkOrders, 10);
      expect(loaded.summary.stats.complianceRate, 92.5);
    });

    test('loadDashboard transitions to DashboardError on failure', () async {
      when(() => mockRepo.fetchAttention()).thenThrow(Exception('Server unreachable'));
      when(() => mockRepo.fetchSummary()).thenAnswer((_) async => const DashboardSummary(stats: DashboardStats()));

      final container = makeContainer();
      final controller = container.read(dashboardControllerProvider.notifier);

      await controller.loadDashboard();

      final state = container.read(dashboardControllerProvider);
      expect(state, isA<DashboardError>());
      final err = state as DashboardError;
      expect(err.message, contains('Server unreachable'));
    });
  });
}
