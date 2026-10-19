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

/// A registration-time evidence photo (`ComplaintPhotoSerializer`).
class ComplaintPhoto extends Equatable {
  const ComplaintPhoto({
    required this.id,
    this.url,
    this.uploadedByName,
    this.uploadedAt,
    this.sizeBytes,
    this.sha256,
  });

  final int id;
  final String? url;
  final String? uploadedByName;
  final DateTime? uploadedAt;
  final int? sizeBytes;
  final String? sha256;

  factory ComplaintPhoto.fromJson(Map<String, dynamic> json) {
    return ComplaintPhoto(
      id: asJsonInt(json['id']) ?? 0,
      url: asJsonString(json['url']),
      uploadedByName: asJsonString(json['uploaded_by_name']),
      uploadedAt: asJsonDateTime(json['uploaded_at']),
      sizeBytes: asJsonInt(json['size_bytes']),
      sha256: asJsonString(json['sha256']),
    );
  }

  @override
  List<Object?> get props =>
      [id, url, uploadedByName, uploadedAt, sizeBytes, sha256];
}

/// Direct close/reject reason categories (`Complaint.CLOSURE_REASON_CHOICES`).
class ComplaintClosureReasons {
  static const values = [
    'RESOLVED',
    'DUPLICATE',
    'FALSE',
    'INVALID',
    'NOT_REQUIRED',
  ];

  static String displayName(String code) {
    switch (code.toUpperCase().trim()) {
      case 'RESOLVED':
        return 'Resolved';
      case 'DUPLICATE':
        return 'Duplicate';
      case 'FALSE':
        return 'False';
      case 'INVALID':
        return 'Invalid';
      case 'NOT_REQUIRED':
        return 'Not Required';
      default:
        return code;
    }
  }
}

/// A complaint as `ComplaintSerializer` returns it (SSOT §10.1).
///
/// Dual-status: [status] is the persisted `record_status`; [effectiveStatus]
/// is the live aggregate (linked Job Work status once converted, else the
/// record status) — mirrors web's `record_status` + `effective_status`.
class Complaint extends Equatable {
  const Complaint({
    required this.id,
    required this.title,
    this.description,
    this.status = ComplaintStatus.open,
    this.effectiveStatus,
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
    this.generalAssetDescription,
    this.failureDate,
    this.failureTime,
    this.complainantName,
    this.closureReason,
    this.closureRemarks,
    this.closedByName,
    this.closedAt,
    this.createdAt,
    this.isConverted = false,
    this.workOrderId,
    this.workOrderStatus,
    this.workOrderTicketNumber,
    this.woAssignedToName,
    this.photos = const [],
  });

  final int id;
  final String title;
  final String? description;
  final ComplaintStatus status;

  /// Live aggregate status string (`effective_status`); null on old payloads.
  final String? effectiveStatus;

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

  /// Non-registered/general item (mutually exclusive with [assetId]).
  final String? generalAssetDescription;

  /// When the failure happened / who reported it (required on create).
  final String? failureDate;
  final String? failureTime;
  final String? complainantName;

  /// Direct close/reject audit (close action only, never PATCH).
  final String? closureReason;
  final String? closureRemarks;
  final String? closedByName;
  final DateTime? closedAt;
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

  /// From `wo_assigned_to_name` — who holds the linked Job Work, if anyone.
  /// The server sends `''` for "nobody" and old payloads omit the key; both
  /// read as null.
  final String? woAssignedToName;

  /// Registration-time evidence photos (max 5, JPEG, OPEN only server-side).
  final List<ComplaintPhoto> photos;

  /// Whether the record is closed by record status.
  bool get isClosed => status == ComplaintStatus.closed;

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

    List<ComplaintPhoto> parsePhotos(dynamic v) {
      if (v is! List) return const [];
      return v
          .whereType<Map>()
          .map((e) => ComplaintPhoto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    // record_status is the persisted column; `status` is overridden with the
    // linked Work Order status once converted (serializer
    // `to_representation`), so the chip reads the record value.
    final recordRaw =
        asJsonString(json['record_status']) ?? asJsonString(json['status']);

    return Complaint(
      id: asJsonInt(json['id']) ?? 0,
      title: asJsonString(json['title']) ?? 'Untitled Breakdown',
      description: asJsonString(json['description']),
      status: ComplaintStatus.fromString(recordRaw),
      effectiveStatus: asJsonString(json['effective_status']),
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
      generalAssetDescription:
          asJsonString(json['general_asset_description']),
      failureDate: asJsonString(json['failure_date']),
      failureTime: asJsonString(json['failure_time']),
      complainantName: asJsonString(json['complainant_name']),
      closureReason: asJsonString(json['closure_reason']),
      closureRemarks: asJsonString(json['closure_remarks']),
      closedByName: asJsonString(json['closed_by_name']),
      closedAt: parseDate(json['closed_at']),
      createdAt: parseDate(json['created_at']),
      isConverted: asJsonBool(json['is_converted']) ?? false,
      workOrderId: asJsonInt(json['wo_id']),
      workOrderStatus: asJsonString(json['wo_status']),
      workOrderTicketNumber: asJsonString(json['wo_ticket_number']),
      woAssignedToName: asJsonNonBlankString(json['wo_assigned_to_name']),
      photos: parsePhotos(json['photos']),
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
      effectiveStatus: effectiveStatus,
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
      generalAssetDescription: generalAssetDescription,
      failureDate: failureDate,
      failureTime: failureTime,
      complainantName: complainantName,
      closureReason: closureReason,
      closureRemarks: closureRemarks,
      closedByName: closedByName,
      closedAt: closedAt,
      createdAt: createdAt,
      isConverted: true,
      workOrderId: workOrderId ?? this.workOrderId,
      workOrderStatus: workOrderStatus,
      workOrderTicketNumber: workOrderTicketNumber,
      woAssignedToName: woAssignedToName,
      photos: photos,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        status,
        effectiveStatus,
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
        generalAssetDescription,
        failureDate,
        failureTime,
        complainantName,
        closureReason,
        closureRemarks,
        closedByName,
        closedAt,
        createdAt,
        isConverted,
        workOrderId,
        workOrderStatus,
        workOrderTicketNumber,
        woAssignedToName,
        photos,
      ];
}
