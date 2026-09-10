import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

enum InspectionStatus {
  open('OPEN', 'Open'),
  actionRequired('ACTION_REQUIRED', 'Action Required'),
  converted('CONVERTED', 'Converted to Work Order'),
  closed('CLOSED', 'Closed'),
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
    this.notes,
    this.status = InspectionStatus.open,
    this.priority = InspectionPriority.medium,
    this.stationId,
    this.stationName,
    this.depotId,
    this.depotName,
    this.assetId,
    this.assetName,
    this.inspectionDate,
    this.completedDate,
    this.createdAt,
    this.reportedByName,
    this.isConverted = false,
    this.workOrderId,
  });

  final int id;
  final String inspectionNumber;
  final String title;
  final String? notes;
  final InspectionStatus status;
  final InspectionPriority priority;
  final int? stationId;
  final String? stationName;
  final int? depotId;
  final String? depotName;
  final int? assetId;
  final String? assetName;
  final DateTime? inspectionDate;
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
      notes: asJsonString(json['notes']),
      status: InspectionStatus.fromString(asJsonString(json['status'])),
      priority: InspectionPriority.fromString(
          asJsonString(json['priority']) ?? asJsonString(json['severity'])),
      stationId: fkId(json['station']),
      stationName: asJsonString(json['station_name']),
      depotId: fkId(json['depot']),
      depotName: asJsonString(json['depot_name']),
      assetId: fkId(json['asset']),
      assetName: asJsonString(json['asset_name']),
      inspectionDate: parseDate(json['inspection_date']),
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
        notes,
        status,
        priority,
        stationId,
        stationName,
        depotId,
        depotName,
        assetId,
        assetName,
        inspectionDate,
        completedDate,
        createdAt,
        reportedByName,
        isConverted,
        workOrderId,
      ];
}
