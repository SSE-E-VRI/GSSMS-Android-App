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
    int? depotId,
    int? stationId,
  }) async {
    final query = <String, dynamic>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (severity != null && severity.isNotEmpty) query['severity'] = severity;
    if (depotId != null) query['depot'] = depotId;
    if (stationId != null) query['station'] = stationId;

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
