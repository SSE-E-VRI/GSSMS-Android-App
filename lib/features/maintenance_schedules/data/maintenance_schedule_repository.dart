import 'package:gssms_mobile/features/maintenance_schedules/data/maintenance_schedule_api_service.dart';
import 'package:gssms_mobile/features/maintenance_schedules/domain/models/maintenance_schedule.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/batch_convert_result.dart';

abstract class IMaintenanceScheduleRepository {
  Future<List<MaintenanceSchedule>> fetchPendingSchedules({
    int? zoneId,
    int? divisionId,
    int? depotId,
  });
  Future<BatchConvertResult> createBatchWorkOrders(List<int> scheduleIds);
}

class MaintenanceScheduleRepository implements IMaintenanceScheduleRepository {
  MaintenanceScheduleRepository(this._apiService);
  final MaintenanceScheduleApiService _apiService;

  @override
  Future<List<MaintenanceSchedule>> fetchPendingSchedules({
    int? zoneId,
    int? divisionId,
    int? depotId,
  }) {
    return _apiService.getPendingSchedules(
      zoneId: zoneId,
      divisionId: divisionId,
      depotId: depotId,
    );
  }

  @override
  Future<BatchConvertResult> createBatchWorkOrders(List<int> scheduleIds) {
    return _apiService.createBatchWorkOrders(scheduleIds);
  }
}
