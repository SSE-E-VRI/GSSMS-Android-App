import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/network/paginated_fetch.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';

final inspectionApiServiceProvider = Provider<InspectionApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return InspectionApiService(dio);
});

class InspectionApiService {
  InspectionApiService(this._dio);
  final Dio _dio;

  Future<List<Inspection>> getInspections({
    String? status,
    String? priority,
    int? zoneId,
    int? divisionId,
    int? depotId,
    String? dateFrom,
    String? dateTo,
    bool? pendingConversion,
  }) async {
    final query = <String, dynamic>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (priority != null && priority.isNotEmpty) query['priority'] = priority;
    // SSOT §11.4 canonical filter — server-side "not yet converted" filter,
    // distinct from `status` (OPEN/ACTION_REQUIRED inspections can both be
    // pending conversion).
    if (pendingConversion != null) {
      query['pending_conversion'] = pendingConversion.toString();
    }
    // depot/division/zone are mutually exclusive server-side
    // (InspectionViewSet.get_queryset), no `_id` suffix.
    if (depotId != null) {
      query['depot'] = depotId;
    } else if (divisionId != null) {
      query['division'] = divisionId;
    } else if (zoneId != null) {
      query['zone'] = zoneId;
    }
    if (dateFrom != null && dateFrom.isNotEmpty) query['start_date'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) query['end_date'] = dateTo;

    // InspectionViewSet sets no pagination_class, so this returns in one
    // request today; the bounded walk is here so it stays correct if
    // pagination is ever switched on server-side.
    final page = await fetchAllPages(_dio, '/api/v1/inspections/', queryParameters: query);
    return page.items
        .whereType<Map>()
        .map((e) => Inspection.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Map<String, dynamic>? _asObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<Inspection> getInspection(int id) async {
    final response = await _dio.get('/api/v1/inspections/$id/');
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected inspection payload',
      );
    }
    return Inspection.fromJson(data);
  }

  Future<Inspection> createInspection(Map<String, dynamic> payload) async {
    final response = await _dio.post('/api/v1/inspections/', data: payload);
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected inspection payload',
      );
    }
    return Inspection.fromJson(data);
  }

  /// Convert inspection to work order — POST /api/v1/inspections/{id}/convert_to_work_order/
  Future<Map<String, dynamic>> convertToWorkOrder(int inspectionId) async {
    final response = await _dio.post('/api/v1/inspections/$inspectionId/convert_to_work_order/');
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected convert-to-work-order payload',
      );
    }
    return data;
  }
}
