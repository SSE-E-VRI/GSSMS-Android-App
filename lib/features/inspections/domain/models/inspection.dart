import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

enum InspectionStatus {
  pending('PENDING', 'Pending'),
  inProgress('IN_PROGRESS', 'In Progress'),
  completed('COMPLETED', 'Completed'),
  converted('CONVERTED', 'Converted to Work Order'),
  cancelled('CANCELLED', 'Cancelled'),
  unknown('UNKNOWN', 'Unknown');

  const InspectionStatus(this.code, this.displayName);
  final String code;
  final String displayName;

  static InspectionStatus fromString(String? code) {
    if (code == null) return InspectionStatus.unknown;
    final upper = code.toUpperCase().trim();
    for (final s in InspectionStatus.values) {
      if (s.code == upper) return s;
    }
    return InspectionStatus.unknown;
  }
}

enum InspectionPriority {
  critical('CRITICAL', 'Critical'),
  high('HIGH', 'High'),
  medium('MEDIUM', 'Medium'),
  low('LOW', 'Low');

  const InspectionPriority(this.code, this.displayName);
  final String code;
  final String displayName;

  static InspectionPriority fromString(String? code) {
    if (code == null) return InspectionPriority.medium;
    final upper = code.toUpperCase().trim();
    for (final p in InspectionPriority.values) {
      if (p.code == upper) return p;
    }
    return InspectionPriority.medium;
  }
}

class Inspection extends Equatable {
  const Inspection({
    required this.id,
    required this.inspectionNumber,
    required this.title,
    this.description,
    this.status = InspectionStatus.pending,
    this.priority = InspectionPriority.medium,
    this.stationId,
    this.stationName,
    this.depotId,
    this.depotName,
    this.assetId,
    this.assetName,
    this.scheduledDate,
    this.completedDate,
    this.createdAt,
    this.reportedByName,
    this.isConverted = false,
    this.workOrderId,
  });

  final int id;
  final String inspectionNumber;
  final String title;
  final String? description;
  final InspectionStatus status;
  final InspectionPriority priority;
  final int? stationId;
  final String? stationName;
  final int? depotId;
  final String? depotName;
  final int? assetId;
  final String? assetName;
  final DateTime? scheduledDate;
  final DateTime? completedDate;
  final DateTime? createdAt;
  final String? reportedByName;

  /// From InspectionSerializer.get_is_converted — whether a Work Order has
  /// already been migrated from this inspection. This is the authoritative
  /// signal, independent of [status] (which the server may or may not also
  /// reflect as CONVERTED).
  final bool isConverted;

  /// From InspectionSerializer.get_wo_id — the linked Work Order's id, when
  /// [isConverted] is true.
  final int? workOrderId;

  factory Inspection.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d == null || d == '') return null;
      return DateTime.tryParse(d.toString());
    }

    int? fkId(dynamic v) => v is Map ? asJsonInt(v['id']) : asJsonInt(v);

    return Inspection(
      id: asJsonInt(json['id']) ?? 0,
      inspectionNumber: asJsonString(json['inspection_number']) ??
          asJsonString(json['ticket_number']) ??
          'INSP-${json['id']}',
      title: asJsonString(json['title']) ?? 'Untitled Inspection',
      description: asJsonString(json['description']),
      status: InspectionStatus.fromString(asJsonString(json['status'])),
      priority: InspectionPriority.fromString(
          asJsonString(json['priority']) ?? asJsonString(json['severity'])),
      stationId: fkId(json['station']),
      stationName: asJsonString(json['station_name']),
      depotId: fkId(json['depot']),
      depotName: asJsonString(json['depot_name']),
      assetId: fkId(json['asset']),
      assetName: asJsonString(json['asset_name']),
      scheduledDate: parseDate(json['scheduled_date']),
      completedDate: parseDate(json['completed_date'] ?? json['resolved_at']),
      createdAt: parseDate(json['created_at']),
      reportedByName: asJsonString(json['reported_by_name']) ??
          asJsonString(json['created_by_name']),
      isConverted: asJsonBool(json['is_converted']) ?? false,
      workOrderId: asJsonInt(
          json['wo_id'] ?? json['work_order_id'] ?? json['work_order']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        inspectionNumber,
        title,
        description,
        status,
        priority,
        stationId,
        stationName,
        depotId,
        depotName,
        assetId,
        assetName,
        scheduledDate,
        completedDate,
        createdAt,
        reportedByName,
        isConverted,
        workOrderId,
      ];
}
