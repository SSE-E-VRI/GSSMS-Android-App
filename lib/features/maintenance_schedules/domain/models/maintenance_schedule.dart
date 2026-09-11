import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Canonical values from `MaintenanceSchedule.STATUS_CHOICES` (backend
/// `maintenance/models.py`). Note this is the *schedule's* status, distinct
/// from `WorkOrderStatus` once it's converted.
enum ScheduleStatus {
  pending('PENDING', 'Pending'),
  inProgress('IN_PROGRESS', 'In Progress'),
  completed('COMPLETED', 'Completed'),
  overdue('OVERDUE', 'Overdue'),
  unknown('UNKNOWN', 'Unknown');

  const ScheduleStatus(this.code, this.displayName);
  final String code;
  final String displayName;

  static ScheduleStatus fromString(String? code) {
    if (code == null) return ScheduleStatus.unknown;
    final upper = code.trim().toUpperCase();
    for (final s in ScheduleStatus.values) {
      if (s.code == upper) return s;
    }
    return ScheduleStatus.unknown;
  }
}

/// One row from `GET /api/v1/maintenance/schedules/pending/`
/// (`MaintenanceScheduleSerializer`) — a scheduled preventive-maintenance
/// task awaiting conversion into (or completion of) a Job Work.
class MaintenanceSchedule extends Equatable {
  const MaintenanceSchedule({
    required this.id,
    required this.templateName,
    this.scheduleType,
    this.stationName,
    this.depotName,
    required this.status,
    this.dueDate,
    this.workOrderId,
    this.workOrderTicket,
    this.workOrderStatus,
  });

  final int id;
  final String templateName;
  final String? scheduleType;
  final String? stationName;
  final String? depotName;
  final ScheduleStatus status;
  final DateTime? dueDate;

  /// From `work_order_id`/`work_order_ticket`/`work_order_status` — set once
  /// this schedule has already been converted (mirrors Inspection/Complaint's
  /// `isConverted`/`workOrderId` pattern, just derived from a non-null id
  /// here since the serializer has no separate boolean flag).
  final int? workOrderId;
  final String? workOrderTicket;
  final String? workOrderStatus;

  bool get isConverted => workOrderId != null;

  factory MaintenanceSchedule.fromJson(Map<String, dynamic> json) {
    return MaintenanceSchedule(
      id: asJsonInt(json['id']) ?? 0,
      templateName: asJsonString(json['template_name']) ??
          asJsonString(json['maintenance_master_name']) ??
          'Maintenance Task',
      scheduleType: asJsonString(json['schedule_type']),
      stationName: asJsonString(json['station_name']),
      depotName: asJsonString(json['depot_name']),
      status: ScheduleStatus.fromString(asJsonString(json['status'])),
      dueDate: asJsonString(json['due_date']) != null
          ? asJsonDateTime(json['due_date'])
          : null,
      workOrderId: asJsonInt(json['work_order_id']),
      workOrderTicket: asJsonString(json['work_order_ticket']),
      workOrderStatus: asJsonString(json['work_order_status']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        templateName,
        scheduleType,
        stationName,
        depotName,
        status,
        dueDate,
        workOrderId,
        workOrderTicket,
        workOrderStatus,
      ];
}
