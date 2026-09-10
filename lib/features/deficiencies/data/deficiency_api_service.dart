import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';

final deficiencyApiServiceProvider = Provider<DeficiencyApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return DeficiencyApiService(dio);
});

class DeficiencyApiService {
  DeficiencyApiService(this._dio);
  final Dio _dio;

  List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    return const [];
  }

  /// Scoped, non-CLOSED deficiencies whose owning work order has reached
  /// TECH_COMPLETED/VERIFIED/CLOSED (or has no work order at all) — see the
  /// extensive reasoning in `DeficiencyViewSet.pending` on the backend. Read
  /// only: `IsAuthenticated`, no extra permission code — scope is enforced
  /// by `ScopeService` server-side via these same depot/division/zone params.
  Future<List<Deficiency>> getPendingDeficiencies({
    int? zoneId,
    int? divisionId,
    int? depotId,
  }) async {
    final query = <String, dynamic>{};
    if (depotId != null) {
      query['depot'] = depotId;
    } else if (divisionId != null) {
      query['division'] = divisionId;
    } else if (zoneId != null) {
      query['zone'] = zoneId;
    }
    final response =
        await _dio.get('/api/v1/deficiencies/pending/', queryParameters: query);
    return _asList(response.data)
        .whereType<Map>()
        .map((e) => Deficiency.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Full deficiency history for one asset (not just pending) — the
  /// Deficiencies tab on `AssetDetailScreen`, mirroring web's
  /// `api.getDeficiencies({asset: id})` against `GET /api/v1/deficiencies/`.
  Future<List<Deficiency>> getDeficienciesForAsset(int assetId) async {
    final response = await _dio.get(
      '/api/v1/deficiencies/',
      queryParameters: {'asset': assetId},
    );
    return _asList(response.data)
        .whereType<Map>()
        .map((e) => Deficiency.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
