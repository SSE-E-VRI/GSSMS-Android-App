import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/network/paginated_fetch.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';

final assetApiServiceProvider = Provider<AssetApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return AssetApiService(dio);
});

/// A page-walked asset list, plus whether the walk hit its page cap.
class AssetPage {
  const AssetPage({required this.assets, required this.truncated});

  final List<Asset> assets;
  final bool truncated;
}

class AssetApiService {
  AssetApiService(this._dio);

  final Dio _dio;

  /// Assets visible to the caller, narrowed server-side.
  ///
  /// Only parameters AssetViewSet.get_queryset actually reads are sent:
  /// zone/division/depot/station are independent `if`s there (all four can be
  /// combined), the category filter is `asset_category` and matches on the
  /// category *code*, not its display name, and there is no `status` filter at
  /// all — asset lifecycle state is filtered client-side.
  ///
  /// This is the one list endpoint in the app that actually paginates
  /// (StandardResultsSetPagination), so the walk is bounded and the result
  /// reports whether it stopped short.
  Future<AssetPage> getAssets({
    String? search,
    String? assetCategoryCode,
    int? zoneId,
    int? divisionId,
    int? depotId,
    int? stationId,
  }) async {
    final query = <String, dynamic>{};
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (assetCategoryCode != null && assetCategoryCode.isNotEmpty) {
      query['asset_category'] = assetCategoryCode;
    }
    if (zoneId != null) query['zone'] = zoneId;
    if (divisionId != null) query['division'] = divisionId;
    if (depotId != null) query['depot'] = depotId;
    if (stationId != null) query['station'] = stationId;

    final page = await fetchAllPages(_dio, '/api/v1/assets/', queryParameters: query);
    return AssetPage(
      assets: page.items
          .whereType<Map<String, dynamic>>()
          .map(Asset.fromJson)
          .toList(),
      truncated: page.truncated,
    );
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
    for (final asset in matches.assets) {
      if (asset.matchesCode(trimmed)) return asset;
    }
    return null;
  }
}
