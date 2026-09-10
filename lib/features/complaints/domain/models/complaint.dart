import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

// Canonical values per API contract SSOT §10.3 — the backend
// Complaint.STATUS_CHOICES is only OPEN/CONVERTED/CLOSED. Do not invent
// IN_PROGRESS/RESOLVED/REJECTED; once converted, effective operational
// status is derived from the linked Work Order (see `isConverted`/
// `workOrderId` below), not a Complaint status value.
enum ComplaintStatus {
  open('OPEN', 'Open'),
  converted('CONVERTED', 'Converted'),
  closed('CLOSED', 'Closed'),
  unknown('UNKNOWN', 'Unknown');

  const ComplaintStatus(this.code, this.displayName);
  final String code;
  final String displayName;

  static ComplaintStatus fromString(String? code) {
    if (code == null) return ComplaintStatus.unknown;
    final upper = code.toUpperCase().trim();
    for (final s in ComplaintStatus.values) {
      if (s.code == upper) return s;
    }
    return ComplaintStatus.unknown;
  }
}

enum ComplaintSeverity {
  critical('CRITICAL', 'Critical'),
  high('HIGH', 'High'),
  medium('MEDIUM', 'Medium'),
  low('LOW', 'Low');

  const ComplaintSeverity(this.code, this.displayName);
  final String code;
  final String displayName;

  static ComplaintSeverity fromString(String? code) {
    if (code == null) return ComplaintSeverity.medium;
    final upper = code.toUpperCase().trim();
    for (final s in ComplaintSeverity.values) {
      if (s.code == upper) return s;
    }
    return ComplaintSeverity.medium;
  }
}

class Complaint extends Equatable {
  const Complaint({
    required this.id,
    required this.complaintNumber,
    required this.title,
    this.description,
    this.status = ComplaintStatus.open,
    this.severity = ComplaintSeverity.medium,
    this.stationId,
    this.stationName,
    this.depotId,
    this.depotName,
    this.assetId,
    this.assetName,
    this.reportedByName,
    this.createdAt,
    this.resolvedAt,
    this.isConverted = false,
    this.workOrderId,
  });

  final int id;
  final String complaintNumber;
  final String title;
  final String? description;
  final ComplaintStatus status;
  final ComplaintSeverity severity;
  final int? stationId;
  final String? stationName;
  final int? depotId;
  final String? depotName;
  final int? assetId;
  final String? assetName;
  final String? reportedByName;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  /// From ComplaintSerializer's `is_converted` — whether a Work Order has
  /// already been migrated from this complaint. Authoritative independent of
  /// [status] (SSOT §10.1/§10.3).
  final bool isConverted;

  /// From `wo_id` — the linked Work Order's id, when [isConverted] is true.
  final int? workOrderId;

  factory Complaint.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d == null || d == '') return null;
      return DateTime.tryParse(d.toString());
    }

    int? fkId(dynamic v) => v is Map ? asJsonInt(v['id']) : asJsonInt(v);

    return Complaint(
      id: asJsonInt(json['id']) ?? 0,
      complaintNumber:
          asJsonString(json['complaint_number']) ?? 'CMP-${json['id']}',
      title: asJsonString(json['title']) ?? 'Untitled Complaint',
      description: asJsonString(json['description']),
      status: ComplaintStatus.fromString(asJsonString(json['status'])),
      severity: ComplaintSeverity.fromString(asJsonString(json['severity'])),
      stationId: fkId(json['station']),
      stationName: asJsonString(json['station_name']),
      depotId: fkId(json['depot']),
      depotName: asJsonString(json['depot_name']),
      assetId: fkId(json['asset']),
      assetName: asJsonString(json['asset_name']),
      reportedByName: asJsonString(json['reported_by_name']) ??
          asJsonString(json['created_by_name']),
      createdAt: parseDate(json['created_at']),
      resolvedAt: parseDate(json['resolved_at']),
      isConverted: asJsonBool(json['is_converted']) ?? false,
      workOrderId: asJsonInt(json['wo_id'] ?? json['work_order_id']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        complaintNumber,
        title,
        description,
        status,
        severity,
        stationId,
        stationName,
        depotId,
        depotName,
        assetId,
        assetName,
        reportedByName,
        createdAt,
        resolvedAt,
        isConverted,
        workOrderId,
      ];
}
