import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
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
    int? stationId,
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
    if (stationId != null) query['station'] = stationId;
    if (dateFrom != null && dateFrom.isNotEmpty) query['start_date'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) query['end_date'] = dateTo;

    final response = await _dio.get(
      '/api/v1/complaints/',
      queryParameters: query,
    );

    final dynamic data = response.data;
    final List<dynamic> results;
    if (data is Map<String, dynamic> && data.containsKey('results')) {
      results = data['results'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      results = data;
    } else {
      results = [];
    }

    return results.map((e) => Complaint.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Complaint> getComplaint(int id) async {
    final response = await _dio.get('/api/v1/complaints/$id/');
    return Complaint.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Complaint> createComplaint(Map<String, dynamic> complaintData) async {
    final response = await _dio.post(
      '/api/v1/complaints/',
      data: complaintData,
    );
    return Complaint.fromJson(response.data as Map<String, dynamic>);
  }
}
