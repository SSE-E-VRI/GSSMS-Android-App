import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
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
    int? depotId,
    int? stationId,
  }) async {
    final query = <String, dynamic>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (priority != null && priority.isNotEmpty) query['priority'] = priority;
    if (depotId != null) query['depot'] = depotId;
    if (stationId != null) query['station'] = stationId;

    final response = await _dio.get('/api/v1/inspections/', queryParameters: query);
    final dynamic data = response.data;
    final List<dynamic> results;
    if (data is Map<String, dynamic> && data.containsKey('results')) {
      results = data['results'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      results = data;
    } else {
      results = [];
    }
    return results.map((e) => Inspection.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Inspection> getInspection(int id) async {
    final response = await _dio.get('/api/v1/inspections/$id/');
    return Inspection.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Inspection> createInspection(Map<String, dynamic> payload) async {
    final response = await _dio.post('/api/v1/inspections/', data: payload);
    return Inspection.fromJson(response.data as Map<String, dynamic>);
  }

  /// Convert inspection to work order — POST /api/v1/inspections/{id}/convert_to_work_order/
  Future<Map<String, dynamic>> convertToWorkOrder(int inspectionId) async {
    final response = await _dio.post('/api/v1/inspections/$inspectionId/convert_to_work_order/');
    return response.data as Map<String, dynamic>;
  }
}
