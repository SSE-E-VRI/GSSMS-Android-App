import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';

final assetApiServiceProvider = Provider<AssetApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return AssetApiService(dio);
});

class AssetApiService {
  AssetApiService(this._dio);

  final Dio _dio;

  Future<List<Asset>> getAssets({
    String? search,
    String? status,
    String? category,
    int? depotId,
    int? stationId,
  }) async {
    final query = <String, dynamic>{};
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (category != null && category.isNotEmpty) query['category'] = category;
    if (depotId != null) query['depot'] = depotId;
    if (stationId != null) query['station'] = stationId;

    final response = await _dio.get(
      '/api/v1/assets/',
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

    return results.map((e) => Asset.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Asset> getAsset(int id) async {
    final response = await _dio.get('/api/v1/assets/$id/');
    return Asset.fromJson(response.data as Map<String, dynamic>);
  }

  /// Resolves a scanned or typed code to a single asset.
  ///
  /// There is no dedicated lookup endpoint on the backend, so this searches the
  /// register and then requires an exact match on `unique_id` or serial number:
  /// a scan must identify one asset, never "the first of several partial hits".
  Future<Asset?> findAssetByCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;

    final matches = await getAssets(search: trimmed);
    for (final asset in matches) {
      if (asset.matchesCode(trimmed)) return asset;
    }
    return null;
  }
}
