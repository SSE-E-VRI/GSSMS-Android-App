import 'package:dio/dio.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/domain/models/maintenance_register_entry.dart';

class ReportsApiService {
  ReportsApiService(this._dio);

  final Dio _dio;

  Future<List<MaintenanceRegisterEntry>> getMaintenanceRegister({
    required String startDate,
    required String endDate,
    int? zoneId,
    int? divisionId,
    int? depotId,
    InfraFilterType infraType = InfraFilterType.all,
    int? infraId,
  }) async {
    final query = <String, dynamic>{
      'start_date': startDate,
      'end_date': endDate,
    };
    // zone_id/division_id/depot_id (most-specific-wins) and the infra_type/id
    // filter below are independent, separately applied server-side
    // (register_report), not mutually exclusive — both can be sent together.
    if (depotId != null) {
      query['depot_id'] = depotId;
    } else if (divisionId != null) {
      query['division_id'] = divisionId;
    } else if (zoneId != null) {
      query['zone_id'] = zoneId;
    }
    // Send infra_type whenever a type is chosen — the server only reads it as
    // a fallback when no specific item id is present ("All LC Gates" has no
    // id to filter on), so omitting it left a type-only selection filtering
    // nothing. The specific id param, when present, still takes precedence
    // server-side, so sending both is safe.
    final typeParam = infraType.registerTypeParam;
    if (typeParam != null) {
      query['infra_type'] = typeParam;
    }
    final idParam = infraType.registerIdParam;
    if (idParam != null && infraId != null) {
      query[idParam] = infraId;
    }

    final response = await _dio.get<dynamic>(
      '/api/v1/maintenance/records/register_report/',
      queryParameters: query,
    );

    final raw = response.data;
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().map(MaintenanceRegisterEntry.fromJson).toList();
    } else if (raw is Map<String, dynamic> && raw['results'] is List) {
      final list = raw['results'] as List;
      return list.whereType<Map<String, dynamic>>().map(MaintenanceRegisterEntry.fromJson).toList();
    }
    return const [];
  }
}
