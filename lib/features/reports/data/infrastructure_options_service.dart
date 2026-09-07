import 'package:dio/dio.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';

/// Option lists for the Reports infrastructure Type / Item dropdowns.
///
/// Matches the web client: stations from `/api/v1/stations/`, other types from
/// `/api/v1/infrastructure/?type_code=LC|SB|SQ`.
class InfrastructureOptionsService {
  InfrastructureOptionsService(this._dio);

  final Dio _dio;

  List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    return const [];
  }

  Future<List<InfrastructureOption>> fetchOptions(InfraFilterType type) async {
    if (type == InfraFilterType.all || type.queryCode == null) {
      return const [];
    }

    final Response<dynamic> response;
    if (type == InfraFilterType.station) {
      response = await _dio.get<dynamic>('/api/v1/stations/');
    } else {
      response = await _dio.get<dynamic>(
        '/api/v1/infrastructure/',
        queryParameters: {'type_code': type.queryCode},
      );
    }

    return _asList(response.data)
        .whereType<Map<String, dynamic>>()
        .map(InfrastructureOption.fromJson)
        .where((o) => o.id > 0)
        .toList();
  }
}
