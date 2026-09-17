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

  // S7
  Future<List<MaintenanceSchedule>> fetchUpcomingSchedules({
    required String scheduleType,
    int? stationId,
    int windowDays = 7,
    bool includeOverdue = false,
  });
  Future<Map<String, dynamic>> convertSchedule(
    int scheduleId, {
    String mode = 'LOCATION',
    int? assignedTo,
  });
  Future<BatchConvertResult> createBatchByScheduleType({
    required String scheduleType,
    int? stationId,
    int windowDays = 7,
  });
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

  // S7
  @override
  Future<List<MaintenanceSchedule>> fetchUpcomingSchedules({
    required String scheduleType,
    int? stationId,
    int windowDays = 7,
    bool includeOverdue = false,
  }) {
    return _apiService.getUpcomingSchedules(
      scheduleType: scheduleType,
      stationId: stationId,
      windowDays: windowDays,
      includeOverdue: includeOverdue,
    );
  }

  @override
  Future<Map<String, dynamic>> convertSchedule(
    int scheduleId, {
    String mode = 'LOCATION',
    int? assignedTo,
  }) {
    return _apiService.convertSchedule(
      scheduleId,
      mode: mode,
      assignedTo: assignedTo,
    );
  }

  @override
  Future<BatchConvertResult> createBatchByScheduleType({
    required String scheduleType,
    int? stationId,
    int windowDays = 7,
  }) {
    return _apiService.createBatchByScheduleType(
      scheduleType: scheduleType,
      stationId: stationId,
      windowDays: windowDays,
    );
  }
}
