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
      dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date'].toString()) : null,
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

class DashboardSummary extends Equatable {
  const DashboardSummary({
    required this.stats,
    this.pendingTasks = const [],
  });

  final DashboardStats stats;
  final List<dynamic> pendingTasks;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final rawStats = json['stats'] as Map<String, dynamic>? ?? json;
    return DashboardSummary(
      stats: DashboardStats.fromJson(rawStats),
      pendingTasks: json['pending_tasks'] as List<dynamic>? ?? const [],
    );
  }

  @override
  List<Object?> get props => [stats, pendingTasks];
}
