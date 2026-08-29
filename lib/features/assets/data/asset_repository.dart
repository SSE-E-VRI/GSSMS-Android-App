import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';

abstract class IAssetRepository {
  Future<List<Asset>> fetchAssets({
    String? search,
    String? status,
    String? category,
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
  Future<List<Asset>> fetchAssets({
    String? search,
    String? status,
    String? category,
    int? depotId,
    int? stationId,
  }) async {
    return _apiService.getAssets(
      search: search,
      status: status,
      category: category,
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
