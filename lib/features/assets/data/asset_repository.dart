import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_component.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_maintenance_summary.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_replacement_event.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_specification.dart';
import 'package:gssms_mobile/features/assets/domain/models/reliability_metrics.dart';

abstract class IAssetRepository {
  Future<AssetPage> fetchAssets({
    String? search,
    String? assetCategoryCode,
    int? zoneId,
    int? divisionId,
    int? depotId,
    int? stationId,
  });

  Future<Asset> fetchAssetById(int id);
  Future<Asset?> scanOrFindAssetByCode(String code);

  Future<AssetMaintenanceSummary> fetchMaintenanceSummary(int assetId);
  Future<ReliabilityMetrics> fetchReliabilityMetrics(
    int assetId, {
    String? startDate,
    String? endDate,
  });
  Future<AssetSpecificationWorkspace> fetchSpecifications(int assetId);
  Future<List<AssetComponent>> fetchComponents(int assetId);
  Future<List<AssetReplacementEvent>> fetchReplacementHistory(int assetId);
}

class AssetRepository implements IAssetRepository {
  AssetRepository(this._apiService);

  final AssetApiService _apiService;

  @override
  Future<AssetPage> fetchAssets({
    String? search,
    String? assetCategoryCode,
    int? zoneId,
    int? divisionId,
    int? depotId,
    int? stationId,
  }) async {
    return _apiService.getAssets(
      search: search,
      assetCategoryCode: assetCategoryCode,
      zoneId: zoneId,
      divisionId: divisionId,
      depotId: depotId,
      stationId: stationId,
    );
  }

  @override
  Future<Asset> fetchAssetById(int id) async {
    return _apiService.getAsset(id);
  }

  @override
  Future<Asset?> scanOrFindAssetByCode(String code) async {
    return _apiService.findAssetByCode(code);
  }

  @override
  Future<AssetMaintenanceSummary> fetchMaintenanceSummary(int assetId) {
    return _apiService.getMaintenanceSummary(assetId);
  }

  @override
  Future<ReliabilityMetrics> fetchReliabilityMetrics(
    int assetId, {
    String? startDate,
    String? endDate,
  }) {
    return _apiService.getReliabilityMetrics(assetId, startDate: startDate, endDate: endDate);
  }

  @override
  Future<AssetSpecificationWorkspace> fetchSpecifications(int assetId) {
    return _apiService.getSpecifications(assetId);
  }

  @override
  Future<List<AssetComponent>> fetchComponents(int assetId) {
    return _apiService.getComponents(assetId);
  }

  @override
  Future<List<AssetReplacementEvent>> fetchReplacementHistory(int assetId) {
    return _apiService.getReplacementHistory(assetId);
  }
}
