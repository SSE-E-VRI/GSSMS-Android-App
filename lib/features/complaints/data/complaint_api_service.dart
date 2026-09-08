import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/network/paginated_fetch.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';

final complaintApiServiceProvider = Provider<ComplaintApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return ComplaintApiService(dio);
});

class ComplaintApiService {
  ComplaintApiService(this._dio);

  final Dio _dio;

  Future<List<Complaint>> getComplaints({
    String? status,
    String? severity,
    int? zoneId,
    int? divisionId,
    int? depotId,
    String? dateFrom,
    String? dateTo,
  }) async {
    final query = <String, dynamic>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (severity != null && severity.isNotEmpty) query['severity'] = severity;
    // depot/division/zone are mutually exclusive server-side (ComplaintViewSet
    // .get_queryset: depot wins over division wins over zone) — no `_id`
    // suffix here, unlike WorkOrderViewSet's zone_id/division_id/depot_id.
    if (depotId != null) {
      query['depot'] = depotId;
    } else if (divisionId != null) {
      query['division'] = divisionId;
    } else if (zoneId != null) {
      query['zone'] = zoneId;
    }
    if (dateFrom != null && dateFrom.isNotEmpty) query['start_date'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) query['end_date'] = dateTo;

    // ComplaintViewSet sets no pagination_class, so this returns in one
    // request today; the bounded walk is here so it stays correct if
    // pagination is ever switched on server-side.
    final page = await fetchAllPages(_dio, '/api/v1/complaints/', queryParameters: query);
    return page.items
        .whereType<Map>()
        .map((e) => Complaint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Map<String, dynamic>? _asObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<Complaint> getComplaint(int id) async {
    final response = await _dio.get('/api/v1/complaints/$id/');
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected complaint payload',
      );
    }
    return Complaint.fromJson(data);
  }

  Future<Complaint> createComplaint(Map<String, dynamic> complaintData) async {
    final response = await _dio.post(
      '/api/v1/complaints/',
      data: complaintData,
    );
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected complaint payload',
      );
    }
    return Complaint.fromJson(data);
  }
}
