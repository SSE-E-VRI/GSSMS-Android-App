import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/domain/location_label.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

// Canonical values per API contract SSOT §10.3 — the backend
// Complaint.STATUS_CHOICES is only OPEN/CONVERTED/CLOSED. Do not invent
// IN_PROGRESS/RESOLVED/REJECTED; once converted, effective operational
// status is derived from the linked Work Order (see `isConverted`/
// `workOrderStatus` below), not a Complaint status value.
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

/// A complaint as `ComplaintSerializer` returns it (SSOT §10.1).
///
/// There is no severity/priority on complaints (SSOT §10.6, FIX-002) and no
/// server-issued complaint number: the reference shown to users is `#<id>`,
/// exactly as the Web "Complaint Details" view shows it.
class Complaint extends Equatable {
  const Complaint({
    required this.id,
    required this.title,
    this.description,
    this.status = ComplaintStatus.open,
    this.department,
    this.stationId,
    this.stationName,
    this.depotId,
    this.depotName,
    this.infrastructureName,
    this.infrastructureType,
    this.lcGateNumber,
    this.serviceBuildingName,
    this.staffQuarterName,
    this.assetId,
    this.assetUniqueId,
    this.createdAt,
    this.isConverted = false,
    this.workOrderId,
    this.workOrderStatus,
    this.workOrderTicketNumber,
  });

  final int id;
  final String title;
  final String? description;
  final ComplaintStatus status;

  /// `complaint_department` lookup key (SSOT §10.4) — display via the lookup.
  final String? department;
  final int? stationId;
  final String? stationName;
  final int? depotId;
  final String? depotName;
  final String? infrastructureName;
  final String? infrastructureType;
  final String? lcGateNumber;
  final String? serviceBuildingName;
  final String? staffQuarterName;
  final int? assetId;

  /// The linked asset's server-generated `unique_id` (serializer
  /// `asset_unique_id`) — what the Web register shows as "Asset".
  final String? assetUniqueId;
  final DateTime? createdAt;

  /// From ComplaintSerializer's `is_converted` — whether a Work Order has
  /// already been migrated from this complaint. Authoritative independent of
  /// [status] (SSOT §10.1/§10.3).
  final bool isConverted;

  /// From `wo_id` — the linked Work Order's id, when [isConverted] is true.
  final int? workOrderId;

  /// From `wo_status` — raw Work Order status value of the linked Job Work.
  final String? workOrderStatus;

  /// From `wo_ticket_number` — the linked Job Work's human reference.
  final String? workOrderTicketNumber;

  /// User-facing reference (Web "Reference ID").
  String get reference => '#$id';

  /// Web `getInfraName`: station, else LC gate / building / quarter.
  String? get locationLabel => infrastructureLocationLabel(
        stationName: stationName,
        lcGateNumber: lcGateNumber,
        serviceBuildingName: serviceBuildingName,
        staffQuarterName: staffQuarterName,
        infrastructureName: infrastructureName,
      );

  factory Complaint.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d == null || d == '') return null;
      return asJsonDateTime(d);
    }

    int? fkId(dynamic v) => v is Map ? asJsonInt(v['id']) : asJsonInt(v);

    return Complaint(
      id: asJsonInt(json['id']) ?? 0,
      title: asJsonString(json['title']) ?? 'Untitled Complaint',
      description: asJsonString(json['description']),
      status: ComplaintStatus.fromString(asJsonString(json['status'])),
      department: asJsonString(json['department']),
      stationId: fkId(json['station']),
      stationName: asJsonString(json['station_name']),
      depotId: fkId(json['depot']),
      depotName: asJsonString(json['depot_name']),
      infrastructureName: asJsonString(json['infrastructure_name']),
      infrastructureType: asJsonString(json['infrastructure_type']),
      lcGateNumber: asJsonString(json['lc_gate_number']),
      serviceBuildingName: asJsonString(json['service_building_name']),
      staffQuarterName: asJsonString(json['staff_quarter_name']),
      assetId: fkId(json['asset']),
      assetUniqueId: asJsonString(json['asset_unique_id']),
      createdAt: parseDate(json['created_at']),
      isConverted: asJsonBool(json['is_converted']) ?? false,
      workOrderId: asJsonInt(json['wo_id']),
      workOrderStatus: asJsonString(json['wo_status']),
      workOrderTicketNumber: asJsonString(json['wo_ticket_number']),
    );
  }

  /// Local copy after a successful conversion, before the next refresh
  /// brings the server's `wo_*` fields.
  Complaint markConverted({int? workOrderId}) {
    return Complaint(
      id: id,
      title: title,
      description: description,
      status: ComplaintStatus.converted,
      department: department,
      stationId: stationId,
      stationName: stationName,
      depotId: depotId,
      depotName: depotName,
      infrastructureName: infrastructureName,
      infrastructureType: infrastructureType,
      lcGateNumber: lcGateNumber,
      serviceBuildingName: serviceBuildingName,
      staffQuarterName: staffQuarterName,
      assetId: assetId,
      assetUniqueId: assetUniqueId,
      createdAt: createdAt,
      isConverted: true,
      workOrderId: workOrderId ?? this.workOrderId,
      workOrderStatus: workOrderStatus,
      workOrderTicketNumber: workOrderTicketNumber,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        status,
        department,
        stationId,
        stationName,
        depotId,
        depotName,
        infrastructureName,
        infrastructureType,
        lcGateNumber,
        serviceBuildingName,
        staffQuarterName,
        assetId,
        assetUniqueId,
        createdAt,
        isConverted,
        workOrderId,
        workOrderStatus,
        workOrderTicketNumber,
      ];
}
