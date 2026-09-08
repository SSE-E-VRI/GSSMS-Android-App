import 'package:dio/dio.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';

class DashboardApiService {
  DashboardApiService(this._dio);

  final Dio _dio;

  /// Overdue / due-soon schedules.
  ///
  /// MaintenanceScheduleViewSet.attention runs `_filter_by_org`, which reads
  /// `zone_id`/`division_id`/`depot_id` (most specific wins) and has no station
  /// level. The values are ANDed with the caller's own scope server-side, so
  /// sending them can only ever narrow what the user could already see.
  Future<AttentionSummary> getAttention({
    int? zoneId,
    int? divisionId,
    int? depotId,
  }) async {
    final query = <String, dynamic>{};
    if (zoneId != null) query['zone_id'] = zoneId;
    if (divisionId != null) query['division_id'] = divisionId;
    if (depotId != null) query['depot_id'] = depotId;

    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/maintenance/schedules/attention/',
      queryParameters: query,
    );
    final data = response.data ?? <String, dynamic>{};
    return AttentionSummary.fromJson(data);
  }

  /// KPI counts, status donut segments and pending tasks.
  ///
  /// `depot_id` is the only filter this read model accepts — see the
  /// `summary` action, which threads it into every `Dash.scoped_*` call. It is
  /// deliberately not given zone/division parameters here: offering levels the
  /// endpoint ignores would leave the donut contradicting the attention card
  /// beside it.
  Future<DashboardSummary> getSummary({int? depotId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/maintenance/dashboard/summary/',
      queryParameters: depotId != null ? {'depot_id': depotId} : null,
    );
    final data = response.data ?? <String, dynamic>{};
    return DashboardSummary.fromJson(data);
  }
}
