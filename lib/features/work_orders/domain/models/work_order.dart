import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

enum WorkOrderStatus {
  newOrder('NEW', 'New'),
  assigned('ASSIGNED', 'Assigned'),
  inProgress('IN_PROGRESS', 'In Progress'),
  techCompleted('TECH_COMPLETED', 'Tech Completed'),
  verified('VERIFIED', 'Verified'),
  reworkRequired('REWORK_REQUIRED', 'Rework Required'),
  onHold('ON_HOLD', 'On Hold'),
  closed('CLOSED', 'Closed'),
  cancelled('CANCELLED', 'Cancelled'),
  unknown('UNKNOWN', 'Unknown');

  const WorkOrderStatus(this.code, this.displayName);

  final String code;
  final String displayName;

  static WorkOrderStatus fromString(String? code) {
    if (code == null) return WorkOrderStatus.unknown;
    final normalized = code.trim().toUpperCase();
    for (final status in WorkOrderStatus.values) {
      if (status.code == normalized) return status;
    }
    return WorkOrderStatus.unknown;
  }
}

/// Work order types, matching `WorkOrder.WO_TYPE_CHOICES` in the Django backend.
enum WorkOrderType {
  preventive('PREVENTIVE', 'Preventive Maintenance', 'PM'),
  corrective('CORRECTIVE', 'Corrective Maintenance', 'CM'),
  breakdown('BREAKDOWN', 'Breakdown', 'BD'),
  calibration('CALIBRATION', 'Calibration', 'CAL'),
  installation('INSTALLATION', 'Installation', 'INST'),
  other('OTHER', 'Other', 'OTH'),
  unknown('UNKNOWN', 'Unknown', '—');

  const WorkOrderType(this.code, this.displayName, this.shortLabel);

  final String code;
  final String displayName;

  /// Compact badge label; the full code is too wide for a list card.
  final String shortLabel;

  static WorkOrderType fromString(String? code) {
    if (code == null) return WorkOrderType.unknown;
    final normalized = code.trim().toUpperCase();
    for (final type in WorkOrderType.values) {
      if (type.code == normalized) return type;
    }
    // 'PM' was the short form used before the mobile client was aligned with
    // the backend's WO_TYPE_CHOICES; keep reading it so cached rows survive.
    if (normalized == 'PM') return WorkOrderType.preventive;
    return WorkOrderType.unknown;
  }
}

enum WorkOrderPriority {
  critical('CRITICAL', 'Critical'),
  high('HIGH', 'High'),
  medium('MEDIUM', 'Medium'),
  low('LOW', 'Low');

  const WorkOrderPriority(this.code, this.displayName);

  final String code;
  final String displayName;

  static WorkOrderPriority fromString(String? code) {
    if (code == null) return WorkOrderPriority.medium;
    final normalized = code.trim().toUpperCase();
    for (final p in WorkOrderPriority.values) {
      if (p.code == normalized) return p;
    }
    return WorkOrderPriority.medium;
  }
}

class WorkOrderEventSummary extends Equatable {
  const WorkOrderEventSummary({
    required this.eventType,
    required this.actor,
    this.createdAt,
    this.remarks,
  });

  final String eventType;
  final String actor;
  final DateTime? createdAt;
  final String? remarks;

  factory WorkOrderEventSummary.fromJson(Map<String, dynamic> json) {
    DateTime? dt;
    final ts = json['created_at'] ?? json['timestamp'];
    if (ts is String && ts.isNotEmpty) {
      dt = DateTime.tryParse(ts);
    }
    return WorkOrderEventSummary(
      eventType: asJsonString(json['event_type']) ?? 'EVENT',
      actor: asJsonString(json['actor']) ?? 'System',
      createdAt: dt,
      remarks: asJsonString(json['remarks']),
    );
  }

  @override
  List<Object?> get props => [eventType, actor, createdAt, remarks];
}

class WorkOrder extends Equatable {
  const WorkOrder({
    required this.id,
    required this.status,
    required this.type,
    this.ticketNumber,
    this.maintenanceMasterName,
    this.slaStatus,
    this.escalationLevel,
    this.stationId,
    this.title,
    this.description,
    this.priority = WorkOrderPriority.medium,
    this.assetId,
    this.assetName,
    this.assetCriticality,
    this.depotId,
    this.depotName,
    this.stationName,
    this.infrastructureName,
    this.infrastructureType,
    this.assignedToId,
    this.assignedToName,
    this.reportedByName,
    this.verifiedByName,
    this.dueDate,
    this.createdAt,
    this.reportCompletedAt,
    this.latestEventSummary,
    this.linkedRecordId,
    this.originalScheduleId,
    this.originalComplaintId,
    this.originalInspectionId,
  });

  final int id;
  final WorkOrderStatus status;
  final WorkOrderType type;

  /// Human-facing identifier shown throughout the web app, e.g. "TLNR-202608-0015".
  final String? ticketNumber;

  /// Checklist template this work order executes.
  final String? maintenanceMasterName;

  /// Server-computed SLA state, e.g. "OK", "AT_RISK", "BREACHED".
  final String? slaStatus;
  final String? escalationLevel;
  final int? stationId;

  final String? title;
  final String? description;
  final WorkOrderPriority priority;
  final int? assetId;
  final String? assetName;
  final String? assetCriticality;
  final int? depotId;
  final String? depotName;
  final String? stationName;
  final String? infrastructureName;
  final String? infrastructureType;
  final int? assignedToId;
  final String? assignedToName;
  final String? reportedByName;
  final String? verifiedByName;
  final DateTime? dueDate;
  final DateTime? createdAt;
  final DateTime? reportCompletedAt;
  final WorkOrderEventSummary? latestEventSummary;
  final int? linkedRecordId;
  final int? originalScheduleId;
  final int? originalComplaintId;
  final int? originalInspectionId;

  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) return title!;
    if (maintenanceMasterName != null && maintenanceMasterName!.trim().isNotEmpty) {
      return maintenanceMasterName!;
    }
    final asset = assetName ?? infrastructureName ?? stationName ?? 'Asset';
    return '${type.displayName} - $asset';
  }

  /// Ticket number when the server issued one, otherwise the numeric id.
  String get displayReference =>
      (ticketNumber != null && ticketNumber!.trim().isNotEmpty)
          ? ticketNumber!
          : 'WO #$id';

  /// True when the server flags this work order as breaching or nearing its SLA.
  bool get isSlaAtRisk {
    final s = slaStatus?.toUpperCase();
    return s == 'BREACHED' || s == 'AT_RISK' || s == 'OVERDUE';
  }

  bool get isExecutionAllowed =>
      status == WorkOrderStatus.assigned ||
      status == WorkOrderStatus.inProgress ||
      status == WorkOrderStatus.onHold ||
      status == WorkOrderStatus.reworkRequired;

  WorkOrder copyWith({
    WorkOrderStatus? status,
    String? description,
    Object? reportCompletedAt = _woUnset,
    int? linkedRecordId,
  }) {
    return WorkOrder(
      id: id,
      status: status ?? this.status,
      type: type,
      ticketNumber: ticketNumber,
      maintenanceMasterName: maintenanceMasterName,
      slaStatus: slaStatus,
      escalationLevel: escalationLevel,
      stationId: stationId,
      title: title,
      description: description ?? this.description,
      priority: priority,
      assetId: assetId,
      assetName: assetName,
      assetCriticality: assetCriticality,
      depotId: depotId,
      depotName: depotName,
      stationName: stationName,
      infrastructureName: infrastructureName,
      infrastructureType: infrastructureType,
      assignedToId: assignedToId,
      assignedToName: assignedToName,
      reportedByName: reportedByName,
      verifiedByName: verifiedByName,
      dueDate: dueDate,
      createdAt: createdAt,
      reportCompletedAt: identical(reportCompletedAt, _woUnset)
          ? this.reportCompletedAt
          : reportCompletedAt as DateTime?,
      latestEventSummary: latestEventSummary,
      linkedRecordId: linkedRecordId ?? this.linkedRecordId,
      originalScheduleId: originalScheduleId,
      originalComplaintId: originalComplaintId,
      originalInspectionId: originalInspectionId,
    );
  }

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    WorkOrderEventSummary? eventSummary;
    final latestRaw = json['latest_event_summary'];
    if (latestRaw is Map) {
      eventSummary = WorkOrderEventSummary.fromJson(
        Map<String, dynamic>.from(latestRaw),
      );
    }

    int? fkId(dynamic v) => v is Map ? asJsonInt(v['id']) : asJsonInt(v);

    return WorkOrder(
      id: asJsonInt(json['id']) ?? 0,
      status: WorkOrderStatus.fromString(asJsonString(json['status'])),
      type: WorkOrderType.fromString(asJsonString(json['type'])),
      ticketNumber: asJsonString(json['ticket_number']),
      maintenanceMasterName: asJsonString(json['maintenance_master_name']),
      slaStatus: asJsonString(json['sla_status']),
      escalationLevel: asJsonString(json['escalation_level']),
      stationId: fkId(json['station']),
      title: asJsonString(json['title']),
      description: asJsonString(json['description']),
      priority: WorkOrderPriority.fromString(asJsonString(json['priority'])),
      assetId: fkId(json['asset']),
      assetName: asJsonString(json['asset_name']),
      assetCriticality: asJsonString(json['asset_criticality']),
      depotId: fkId(json['depot']),
      depotName: asJsonString(json['depot_name']),
      stationName: asJsonString(json['station_name']),
      infrastructureName: asJsonString(json['infrastructure_name']),
      infrastructureType: asJsonString(json['infrastructure_type']),
      assignedToId: fkId(json['assigned_to']),
      assignedToName: asJsonString(json['assigned_to_name']),
      reportedByName: asJsonString(json['reported_by_name']),
      verifiedByName: asJsonString(json['verified_by_name']),
      dueDate: parseDate(json['due_date']),
      createdAt: parseDate(json['created_at']),
      reportCompletedAt: parseDate(json['report_completed_at']),
      latestEventSummary: eventSummary,
      linkedRecordId: asJsonInt(json['linked_record_id']),
      originalScheduleId: asJsonInt(json['original_schedule_id']),
      originalComplaintId: asJsonInt(json['original_complaint_id']),
      originalInspectionId: asJsonInt(json['original_inspection_id']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        status,
        type,
        ticketNumber,
        maintenanceMasterName,
        slaStatus,
        escalationLevel,
        stationId,
        stationName,
        title,
        description,
        priority,
        assetId,
        assetName,
        assetCriticality,
        depotId,
        depotName,
        infrastructureName,
        infrastructureType,
        assignedToId,
        assignedToName,
        reportedByName,
        verifiedByName,
        dueDate,
        createdAt,
        reportCompletedAt,
        latestEventSummary,
        linkedRecordId,
        originalScheduleId,
        originalComplaintId,
        originalInspectionId,
      ];
}

/// Sentinel so [WorkOrder.copyWith] can clear [WorkOrder.reportCompletedAt].
const Object _woUnset = Object();
