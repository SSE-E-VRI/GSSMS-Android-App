import 'package:dio/dio.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';

class DashboardApiService {
  DashboardApiService(this._dio);

  final Dio _dio;

  Future<AttentionSummary> getAttention() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/maintenance/schedules/attention/');
    final data = response.data ?? <String, dynamic>{};
    return AttentionSummary.fromJson(data);
  }

  Future<DashboardSummary> getSummary() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/maintenance/dashboard/summary/');
    final data = response.data ?? <String, dynamic>{};
    return DashboardSummary.fromJson(data);
  }
}
