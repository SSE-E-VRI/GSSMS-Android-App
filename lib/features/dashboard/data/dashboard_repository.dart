import 'package:gssms_mobile/features/dashboard/data/dashboard_api_service.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';

abstract class IDashboardRepository {
  Future<AttentionSummary> fetchAttention();
  Future<DashboardSummary> fetchSummary();
}

/// Read-only: unlike [WorkOrderRepository], there is no local cache to fall
/// back to, so every failure — network drop, expired session, permission
/// denial, server error — propagates to the controller's error state rather
/// than being swallowed into an empty/zero result. A dashboard that silently
/// shows "0 Overdue" on a failed request is worse than showing nothing: it
/// reads as a genuine all-clear.
class DashboardRepository implements IDashboardRepository {
  DashboardRepository(this._apiService);

  final DashboardApiService _apiService;

  @override
  Future<AttentionSummary> fetchAttention() => _apiService.getAttention();

  @override
  Future<DashboardSummary> fetchSummary() => _apiService.getSummary();
}
