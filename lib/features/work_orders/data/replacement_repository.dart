import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_component.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/replacement_requests.dart';

abstract class IReplacementRepository {
  Future<AssetPage> fetchStationAssets({
    required int stationId,
    int? infrastructureId,
  });
  Future<List<AssetComponent>> fetchReplaceableComponents(int assetId);
  Future<void> replaceAsset(int assetId, AssetReplacementRequest request);
  Future<void> replaceInstalledComponent(
    String installedComponentId,
    InstalledComponentReplacementRequest request,
  );
  Future<void> logJobWorkReplacement(
    int workOrderId,
    JobWorkComponentReplacementRequest request,
  );
}

class ReplacementRepository implements IReplacementRepository {
  ReplacementRepository(this._api, this._assets);

  final ReplacementApiService _api;
  final AssetApiService _assets;

  /// Always station-scoped: [stationId] is non-null so the unscoped asset list
  /// can never be requested from here.
  @override
  Future<AssetPage> fetchStationAssets({
    required int stationId,
    int? infrastructureId,
  }) {
    return _assets.getAssets(
      stationId: stationId,
      infrastructureId: infrastructureId,
    );
  }

  @override
  Future<List<AssetComponent>> fetchReplaceableComponents(int assetId) async {
    final all = await _assets.getComponents(assetId);
    return all.where((c) => c.isReplaceableInstalled).toList();
  }

  @override
  Future<void> replaceAsset(int assetId, AssetReplacementRequest request) =>
      _api.replaceAsset(assetId, request);

  @override
  Future<void> replaceInstalledComponent(
    String installedComponentId,
    InstalledComponentReplacementRequest request,
  ) =>
      _api.replaceInstalledComponent(installedComponentId, request);

  @override
  Future<void> logJobWorkReplacement(
    int workOrderId,
    JobWorkComponentReplacementRequest request,
  ) =>
      _api.logJobWorkReplacement(workOrderId, request);
}

final replacementRepositoryProvider = Provider<IReplacementRepository>((ref) {
  return ReplacementRepository(
    ref.watch(replacementApiServiceProvider),
    ref.watch(assetApiServiceProvider),
  );
});
