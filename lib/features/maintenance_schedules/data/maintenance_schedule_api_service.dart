import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/features/maintenance_schedules/domain/models/maintenance_schedule.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/batch_convert_result.dart';

final maintenanceScheduleApiServiceProvider =
    Provider<MaintenanceScheduleApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return MaintenanceScheduleApiService(dio);
});

class MaintenanceScheduleApiService {
  MaintenanceScheduleApiService(this._dio);
  final Dio _dio;

  static const String _schedules = '/api/v1/maintenance/schedules';

  List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    return const [];
  }

  Map<String, dynamic>? _asObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  /// Active (unconverted, in-progress or tech-completed) scheduled tasks for
  /// the caller's scope — `MaintenanceScheduleViewSet.pending`, gated on
  /// `maintenance.view`. `depot_id`/`division_id`/`zone_id` (with the `_id`
  /// suffix, unlike most other list endpoints — see
  /// `MaintenanceScheduleViewSet._filter_by_org`); most-specific wins.
  Future<List<MaintenanceSchedule>> getPendingSchedules({
    int? zoneId,
    int? divisionId,
    int? depotId,
  }) async {
    final query = <String, dynamic>{};
    if (depotId != null) {
      query['depot_id'] = depotId;
    } else if (divisionId != null) {
      query['division_id'] = divisionId;
    } else if (zoneId != null) {
      query['zone_id'] = zoneId;
    }
    final response = await _dio.get('$_schedules/pending/', queryParameters: query);
    return _asList(response.data)
        .whereType<Map>()
        .map((e) => MaintenanceSchedule.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Batch-converts schedule ids into Work Orders in one all-or-nothing
  /// request — POST /schedules/create_batch_work_orders/
  /// {schedule_ids, assigned_to}. `assignedTo` is left unset here: mobile
  /// offers no assignee picker in this flow (matches web's own
  /// `convertBatch`, which always passes `null`) — assignment stays a
  /// separate step on the created Work Order.
  Future<BatchConvertResult> createBatchWorkOrders(List<int> scheduleIds) async {
    final response = await _dio.post(
      '$_schedules/create_batch_work_orders/',
      data: {'schedule_ids': scheduleIds},
    );
    return BatchConvertResult.fromJson(_asObject(response.data) ?? const {});
  }
}
