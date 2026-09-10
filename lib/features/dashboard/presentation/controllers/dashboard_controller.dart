import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
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

  DashboardLoaded? _resolvePrevious() {
    final s = state;
    if (s is DashboardLoaded) return s;
    if (s is DashboardError) return s.previousLoaded;
    return null;
  }

  Future<void> loadDashboard() async {
    final previous = _resolvePrevious();
    state = const DashboardLoading();
    await _load(previous?.orgScope ?? OrgScopeSelection.empty, previous);
  }

  /// Server-side zone/division/depot filter. Both endpoints AND it with the
  /// caller's own scope, so this can only narrow what the user is already
  /// entitled to see.
  Future<void> setOrgScope(OrgScopeSelection scope) =>
      _load(scope, _resolvePrevious());

  Future<void> _load(OrgScopeSelection scope, DashboardLoaded? previous) async {
    try {
      final results = await Future.wait([
        // attention and summary both now accept zone/division/depot
        // (most-specific-wins) — passing the same selection to both is what
        // keeps the attention card and the KPI donut describing one
        // consistent set of work.
        _repository.fetchAttention(
          zoneId: scope.zoneId,
          divisionId: scope.divisionId,
          depotId: scope.depotId,
        ),
        _repository.fetchSummary(
          zoneId: scope.zoneId,
          divisionId: scope.divisionId,
          depotId: scope.depotId,
        ),
      ]);

      state = DashboardLoaded(
        attention: results[0] as AttentionSummary,
        summary: results[1] as DashboardSummary,
        orgScope: scope,
      );
    } catch (e) {
      state = DashboardError(
        'Failed to load dashboard data: $e',
        previousLoaded: previous?.copyWith(orgScope: scope),
      );
    }
  }
}
