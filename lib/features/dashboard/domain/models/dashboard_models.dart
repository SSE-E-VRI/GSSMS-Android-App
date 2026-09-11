import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

class AttentionItem extends Equatable {
  const AttentionItem({
    required this.id,
    required this.masterName,
    this.stationName,
    this.depotName,
    this.dueDate,
    this.daysOverdue,
    this.priority,
  });

  final int id;
  final String masterName;
  final String? stationName;
  final String? depotName;
  final DateTime? dueDate;
  final int? daysOverdue;
  final String? priority;

  factory AttentionItem.fromJson(Map<String, dynamic> json) {
    return AttentionItem(
      id: asJsonInt(json['id']) ?? 0,
      masterName: asJsonString(json['master_name']) ?? asJsonString(json['name']) ?? 'Schedule Item',
      stationName: asJsonString(json['station_name']),
      depotName: asJsonString(json['depot_name']),
      dueDate: json['due_date'] != null ? asJsonDateTime(json['due_date']) : null,
      daysOverdue: asJsonInt(json['days_overdue']) ?? asJsonInt(json['days_pending']),
      priority: asJsonString(json['priority']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        masterName,
        stationName,
        depotName,
        dueDate,
        daysOverdue,
        priority,
      ];
}

class AttentionSummary extends Equatable {
  const AttentionSummary({
    this.overdue = const [],
    this.dueSoon = const [],
    this.upcoming = const [],
  });

  final List<AttentionItem> overdue;
  final List<AttentionItem> dueSoon;
  final List<AttentionItem> upcoming;

  factory AttentionSummary.fromJson(Map<String, dynamic> json) {
    final rawOverdue = json['overdue'] as List<dynamic>? ?? const [];
    final rawDueSoon = (json['due_within_7d'] ?? json['due_soon']) as List<dynamic>? ?? const [];
    final rawUpcoming = json['upcoming'] as List<dynamic>? ?? const [];

    return AttentionSummary(
      overdue: rawOverdue.whereType<Map<String, dynamic>>().map(AttentionItem.fromJson).toList(),
      dueSoon: rawDueSoon.whereType<Map<String, dynamic>>().map(AttentionItem.fromJson).toList(),
      upcoming: rawUpcoming.whereType<Map<String, dynamic>>().map(AttentionItem.fromJson).toList(),
    );
  }

  @override
  List<Object?> get props => [overdue, dueSoon, upcoming];
}

class WorkOrderStatusSegment extends Equatable {
  const WorkOrderStatusSegment({
    required this.label,
    required this.count,
    this.colorHex,
  });

  final String label;
  final int count;
  final String? colorHex;

  factory WorkOrderStatusSegment.fromJson(Map<String, dynamic> json) {
    return WorkOrderStatusSegment(
      label: asJsonString(json['label']) ?? asJsonString(json['status']) ?? 'Unknown',
      count: asJsonInt(json['count']) ?? asJsonInt(json['total']) ?? 0,
      colorHex: asJsonString(json['color']),
    );
  }

  @override
  List<Object?> get props => [label, count, colorHex];
}

class MaintenanceTypeStat extends Equatable {
  const MaintenanceTypeStat({
    required this.label,
    required this.count,
    this.percentage = 0.0,
  });

  final String label;
  final int count;
  final double percentage;

  factory MaintenanceTypeStat.fromJson(Map<String, dynamic> json) {
    return MaintenanceTypeStat(
      label: asJsonString(json['label']) ?? asJsonString(json['type']) ?? 'General',
      count: asJsonInt(json['count']) ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  List<Object?> get props => [label, count, percentage];
}

class DashboardStats extends Equatable {
  const DashboardStats({
    this.totalWorkOrders = 0,
    this.complianceRate = 0.0,
    this.pendingVerificationCount = 0,
    this.pendingTaskCount = 0,
    this.openComplaintCount = 0,
    this.inspectionCount = 0,
    this.statusSegments = const [],
    this.typeStats = const [],
  });

  final int totalWorkOrders;
  final double complianceRate;
  final int pendingVerificationCount;
  final int pendingTaskCount;
  final int openComplaintCount;
  final int inspectionCount;
  final List<WorkOrderStatusSegment> statusSegments;
  final List<MaintenanceTypeStat> typeStats;

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['status_segments'] as List<dynamic>? ?? const [];
    final rawTypeStats = json['type_stats'] as List<dynamic>? ?? const [];

    return DashboardStats(
      totalWorkOrders: asJsonInt(json['total_work_orders']) ?? asJsonInt(json['total_job_works']) ?? 0,
      complianceRate: (json['compliance_rate'] as num?)?.toDouble() ?? 0.0,
      pendingVerificationCount: asJsonInt(json['pending_verification_count']) ?? 0,
      pendingTaskCount: asJsonInt(json['pending_task_count']) ?? 0,
      openComplaintCount: asJsonInt(json['open_complaint_count']) ?? 0,
      inspectionCount: asJsonInt(json['inspection_count']) ?? 0,
      statusSegments: rawSegments.whereType<Map<String, dynamic>>().map(WorkOrderStatusSegment.fromJson).toList(),
      typeStats: rawTypeStats.whereType<Map<String, dynamic>>().map(MaintenanceTypeStat.fromJson).toList(),
    );
  }

  @override
  List<Object?> get props => [
        totalWorkOrders,
        complianceRate,
        pendingVerificationCount,
        pendingTaskCount,
        openComplaintCount,
        inspectionCount,
        statusSegments,
        typeStats,
      ];
}

enum PendingActionKind {
  verification('VERIFICATION', 'Verification'),
  assignment('ASSIGNMENT', 'Assignment'),
  complaint('COMPLAINT', 'Complaint'),
  inspection('INSPECTION', 'Inspection'),
  task('TASK', 'Task'),
  unknown('UNKNOWN', 'Action');

  const PendingActionKind(this.code, this.displayName);
  final String code;
  final String displayName;

  static PendingActionKind fromString(String? code) {
    if (code == null) return PendingActionKind.unknown;
    final upper = code.trim().toUpperCase();
    for (final k in PendingActionKind.values) {
      if (k.code == upper) return k;
    }
    if (upper.contains('VERIFY')) return PendingActionKind.verification;
    if (upper.contains('ASSIGN')) return PendingActionKind.assignment;
    if (upper.contains('COMPLAINT')) return PendingActionKind.complaint;
    if (upper.contains('INSPECT')) return PendingActionKind.inspection;
    return PendingActionKind.unknown;
  }
}

/// One actionable row from `summary.pending_tasks`. The backend shape is not
/// contract-pinned, so every field is coerced with fallbacks and unknown
/// shapes degrade to a generic task row rather than crashing the dashboard.
class PendingAction extends Equatable {
  const PendingAction({
    required this.id,
    this.kind = PendingActionKind.unknown,
    required this.title,
    this.subtitle,
    this.workOrderId,
    this.complaintId,
    this.inspectionId,
    this.dueDate,
  });

  final int id;
  final PendingActionKind kind;
  final String title;
  final String? subtitle;
  final int? workOrderId;
  final int? complaintId;
  final int? inspectionId;
  final DateTime? dueDate;

  static int? _fkId(dynamic v) =>
      v is Map ? asJsonInt(v['id']) : asJsonInt(v);

  factory PendingAction.fromJson(Map<String, dynamic> json) {
    final workOrderId =
        _fkId(json['work_order_id'] ?? json['work_order'] ?? json['wo_id']);
    final complaintId = _fkId(json['complaint_id'] ?? json['complaint']);
    final inspectionId =
        _fkId(json['inspection_id'] ?? json['inspection']);
    return PendingAction(
      id: asJsonInt(json['id']) ??
          workOrderId ??
          complaintId ??
          inspectionId ??
          0,
      kind: PendingActionKind.fromString(asJsonString(
          json['kind'] ?? json['type'] ?? json['action'] ?? json['category'])),
      title: asJsonString(
              json['title'] ??
                  json['name'] ??
                  json['label'] ??
                  json['subject'] ??
                  json['ticket_number']) ??
          'Pending action',
      subtitle: asJsonString(json['subtitle'] ??
          json['description'] ??
          json['station_name'] ??
          json['depot_name'] ??
          json['remarks']),
      workOrderId: workOrderId,
      complaintId:
          _fkId(json['complaint_id'] ?? json['complaint']),
      inspectionId:
          _fkId(json['inspection_id'] ?? json['inspection']),
      dueDate: json['due_date'] != null
          ? asJsonDateTime(json['due_date'])
          : (json['created_at'] != null
              ? asJsonDateTime(json['created_at'])
              : null),
    );
  }

  @override
  List<Object?> get props =>
      [id, kind, title, subtitle, workOrderId, complaintId, inspectionId, dueDate];
}

class DashboardSummary extends Equatable {
  const DashboardSummary({
    required this.stats,
    this.pendingTasks = const [],
  });

  final DashboardStats stats;
  final List<PendingAction> pendingTasks;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final rawStats = json['stats'] as Map<String, dynamic>? ?? json;
    final rawTasks = json['pending_tasks'] as List<dynamic>? ?? const [];
    return DashboardSummary(
      stats: DashboardStats.fromJson(rawStats),
      pendingTasks: rawTasks
          .whereType<Map>()
          .map((e) => PendingAction.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [stats, pendingTasks];
}
