import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';

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
}
