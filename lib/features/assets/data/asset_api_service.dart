import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/network/paginated_fetch.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_component.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_maintenance_summary.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_replacement_event.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_specification.dart';
import 'package:gssms_mobile/features/assets/domain/models/reliability_metrics.dart';

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

  Map<String, dynamic>? _asObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) return data['results'] as List<dynamic>;
    return const [];
  }

  /// "Asset Maintenance Status" panel + the Maintenance tab —
  /// `AssetViewSet.maintenance_summary`.
  Future<AssetMaintenanceSummary> getMaintenanceSummary(int assetId) async {
    final response = await _dio.get('/api/v1/assets/$assetId/maintenance-summary/');
    return AssetMaintenanceSummary.fromJson(_asObject(response.data) ?? const {});
  }

  /// "Reliability Analysis (ISO 55000)" panel — note this lives under the
  /// maintenance work-orders router, not `/assets/`
  /// (`WorkOrderViewSet.reliability_metrics`), scoped to one asset via
  /// `asset_id`. [startDate]/[endDate] are `yyyy-MM-dd`; omitting both
  /// matches the server's own default (last 30 days).
  Future<ReliabilityMetrics> getReliabilityMetrics(
    int assetId, {
    String? startDate,
    String? endDate,
  }) async {
    final query = <String, dynamic>{'asset_id': assetId};
    if (startDate != null) query['start_date'] = startDate;
    if (endDate != null) query['end_date'] = endDate;
    final response = await _dio.get(
      '/api/v1/maintenance/work-orders/reliability_metrics/',
      queryParameters: query,
    );
    return ReliabilityMetrics.fromJson(_asObject(response.data) ?? const {});
  }

  /// Specifications tab — `AssetViewSet.specifications` (read-only on mobile;
  /// see [AssetSpecificationWorkspace]'s doc comment).
  Future<AssetSpecificationWorkspace> getSpecifications(int assetId) async {
    final response = await _dio.get('/api/v1/assets/$assetId/specifications/');
    return AssetSpecificationWorkspace.fromJson(_asObject(response.data) ?? const {});
  }

  /// Components tab — `AssetViewSet.components`. `include_history=false`
  /// (the server default) matches web's own default view: active
  /// components only, not the full replace/remove history for each slot.
  Future<List<AssetComponent>> getComponents(int assetId) async {
    final response = await _dio.get('/api/v1/assets/$assetId/components/');
    return _asList(response.data)
        .whereType<Map>()
        .map((e) => AssetComponent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Replacement History tab — `AssetViewSet.replacement_history`.
  Future<List<AssetReplacementEvent>> getReplacementHistory(int assetId) async {
    final response = await _dio.get('/api/v1/assets/$assetId/replacement-history/');
    return _asList(response.data)
        .whereType<Map>()
        .map((e) => AssetReplacementEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
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
