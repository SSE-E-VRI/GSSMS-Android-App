import 'package:gssms_mobile/features/deficiencies/data/deficiency_api_service.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';

abstract class IDeficiencyRepository {
  Future<List<Deficiency>> fetchPendingDeficiencies({
    int? zoneId,
    int? divisionId,
    int? depotId,
  });
  Future<List<Deficiency>> fetchDeficienciesForAsset(int assetId);
}

class DeficiencyRepository implements IDeficiencyRepository {
  DeficiencyRepository(this._apiService);
  final DeficiencyApiService _apiService;

  @override
  Future<List<Deficiency>> fetchPendingDeficiencies({
    int? zoneId,
    int? divisionId,
    int? depotId,
  }) {
    return _apiService.getPendingDeficiencies(
      zoneId: zoneId,
      divisionId: divisionId,
      depotId: depotId,
    );
  }

  @override
  Future<List<Deficiency>> fetchDeficienciesForAsset(int assetId) {
    return _apiService.getDeficienciesForAsset(assetId);
  }
}
