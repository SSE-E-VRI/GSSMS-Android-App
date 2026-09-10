import 'package:gssms_mobile/features/reports/data/reports_api_service.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/domain/models/maintenance_register_entry.dart';

abstract class IReportsRepository {
  Future<List<MaintenanceRegisterEntry>> fetchMaintenanceRegister({
    required String startDate,
    required String endDate,
    int? zoneId,
    int? divisionId,
    int? depotId,
    InfraFilterType infraType = InfraFilterType.all,
    int? infraId,
  });
}

/// Read-only, no local cache: failures propagate to the controller's error
/// state rather than being swallowed into an empty result, which would read
/// as "no records for this range" instead of "the request failed".
class ReportsRepository implements IReportsRepository {
  ReportsRepository(this._apiService);

  final ReportsApiService _apiService;

  @override
  Future<List<MaintenanceRegisterEntry>> fetchMaintenanceRegister({
    required String startDate,
    required String endDate,
    int? zoneId,
    int? divisionId,
    int? depotId,
    InfraFilterType infraType = InfraFilterType.all,
    int? infraId,
  }) {
    return _apiService.getMaintenanceRegister(
      startDate: startDate,
      endDate: endDate,
      zoneId: zoneId,
      divisionId: divisionId,
      depotId: depotId,
      infraType: infraType,
      infraId: infraId,
    );
  }
}
