import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/features/dashboard/data/dashboard_api_service.dart';
import 'package:gssms_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_state.dart';

final dashboardApiServiceProvider = Provider<DashboardApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return DashboardApiService(dio);
});

final dashboardRepositoryProvider = Provider<IDashboardRepository>((ref) {
  final api = ref.watch(dashboardApiServiceProvider);
  return DashboardRepository(api);
});

final dashboardControllerProvider =
    NotifierProvider<DashboardController, DashboardState>(() {
  return DashboardController();
});

class DashboardController extends Notifier<DashboardState> {
  @override
  DashboardState build() {
    return const DashboardLoading();
  }

  IDashboardRepository get _repository => ref.read(dashboardRepositoryProvider);

  Future<void> loadDashboard() async {
    state = const DashboardLoading();
    try {
      final results = await Future.wait([
        _repository.fetchAttention(),
        _repository.fetchSummary(),
      ]);

      state = DashboardLoaded(
        attention: results[0] as AttentionSummary,
        summary: results[1] as DashboardSummary,
      );
    } catch (e) {
      state = DashboardError('Failed to load dashboard data: $e');
    }
  }
}
