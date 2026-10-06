import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/domain/location_label.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_effective_status.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_evidence_photo.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_point.dart';

enum InspectionStatus {
  open('OPEN', 'Open'),
  actionRequired('ACTION_REQUIRED', 'Action Required'),
  converted('CONVERTED', 'Converted to Job Work'),
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

/// An inspection as `InspectionSerializer` returns it.
///
/// Dual-status architecture (DOC-CMMS-INSP-001 §11/§12):
/// [status] is the persisted `record_status`; [effectiveStatus] is the
/// computed aggregate across points + Job Works shown on web dashboards.
class Inspection extends Equatable {
  const Inspection({
    required this.id,
    required this.title,
    this.notes,
    this.status = InspectionStatus.open,
    this.inspectionNumber,
    this.effectiveStatus = EffectiveInspectionStatus.unknown,
    this.stationId,
    this.stationName,
    this.depotId,
    this.depotName,
    this.depotDivisionId,
    this.infrastructureId,
    this.infrastructureName,
    this.infrastructureType,
    this.lcGateNumber,
    this.serviceBuildingName,
    this.staffQuarterName,
    this.assetId,
    this.assetUniqueId,
    this.assetName,
    this.generalAssetDescription,
    this.inspectionDate,
    this.createdAt,
    this.createdByName,
    this.createdByDesignation,
    this.createdByRole,
    this.isConverted = false,
    this.workOrderId,
    this.workOrderStatus,
    this.woAssignedToName,
    this.pointsCount = 0,
    this.unassignedPointsCount = 0,
    this.points = const [],
    this.jobWorks = const [],
    this.jobWorkCount = 0,
    this.generalEvidencePhotos = const [],
  });

  final int id;
  final String title;
  final String? notes;
  final InspectionStatus status;

  /// Human-readable server number (`INSP-YYYYMM-XXXX`). Null on very old rows.
  final String? inspectionNumber;

  /// Computed aggregate (`effective_status`). Unknown when backend omits it
  /// (e.g. lightweight list rows from old builds).
  final EffectiveInspectionStatus effectiveStatus;

  final int? stationId;
  final String? stationName;
  final int? depotId;
  final String? depotName;
  final int? depotDivisionId;
  final int? infrastructureId;
  final String? infrastructureName;
  final String? infrastructureType;
  final String? lcGateNumber;
  final String? serviceBuildingName;
  final String? staffQuarterName;

  /// Optional default asset scope at Inspection level (Slice I1).
  final int? assetId;
  final String? assetUniqueId;
  final String? assetName;
  final String? generalAssetDescription;

  final DateTime? inspectionDate;
  final DateTime? createdAt;

  /// Inspector's full name when the serializer has it (`created_by_first_name`
  /// + `created_by_last_name`), otherwise the username (`created_by_name`).
  final String? createdByName;
  final String? createdByDesignation;
  final String? createdByRole;

  /// From InspectionSerializer.get_is_converted — whether a Work Order has
  /// already been migrated from this inspection. This is the authoritative
  /// signal, independent of [status] (which the server may or may not also
  /// reflect as CONVERTED).
  final bool isConverted;

  /// From InspectionSerializer.get_wo_id — the linked Work Order's id, when
  /// [isConverted] is true.
  final int? workOrderId;

  /// From `wo_status` — raw status of the linked Job Work.
  final String? workOrderStatus;

  /// From `wo_assigned_to_name` — who holds the linked Job Work, if anyone.
  /// Only the legacy single-Job-Work serializer path sends this; `''` and
  /// absent both read as null.
  final String? woAssignedToName;

  /// Structured points (full retrieve; list rows stub to `[]` server-side).
  final int pointsCount;

  /// From `unassigned_points_count` — points not yet clubbed into a Job Work.
  final int unassignedPointsCount;
  final List<InspectionPoint> points;

  /// Legacy migrated Job Works (`migrated_wo`).
  final List<InspectionJobWorkRef> jobWorks;
  final int jobWorkCount;

  /// General/site overview evidence (point-less photos).
  final List<InspectionEvidencePhoto> generalEvidencePhotos;

  /// Whether the record is closed by record or effective status.
  bool get isClosed =>
      status == InspectionStatus.closed ||
      effectiveStatus == EffectiveInspectionStatus.closed;

  /// User-facing reference: server number when present, else `#id`.
  String get reference {
    final n = inspectionNumber?.trim();
    if (n != null && n.isNotEmpty) return n;
    return '#$id';
  }

  /// Web `getInspectionLocationDisplay`: station+infra, station, infra,
  /// LC gate / building / quarter, asset, depot fallback.
  String? get locationLabel {
    final base = infrastructureLocationLabel(
      stationName: stationName,
      lcGateNumber: lcGateNumber,
      serviceBuildingName: serviceBuildingName,
      staffQuarterName: staffQuarterName,
      infrastructureName: infrastructureName,
    );
    if (base != null) {
      // Web shows "Station - Infra" when both are present and station-only
      // label would otherwise hide the infra name.
      if (stationName?.trim().isNotEmpty == true &&
          infrastructureName?.trim().isNotEmpty == true) {
        return '${stationName!.trim()} - ${infrastructureName!.trim()}';
      }
      return base;
    }
    if (assetUniqueId?.trim().isNotEmpty == true) {
      return '${assetUniqueId!.trim()} (Asset)';
    }
    if (depotName?.trim().isNotEmpty == true) {
      return '${depotName!.trim()} (Depot)';
    }
    return null;
  }

  factory Inspection.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d == null || d == '') return null;
      return asJsonDateTime(d);
    }

    int? fkId(dynamic v) => v is Map ? asJsonInt(v['id']) : asJsonInt(v);

    final first = asJsonString(json['created_by_first_name'])?.trim() ?? '';
    final last = asJsonString(json['created_by_last_name'])?.trim() ?? '';
    final fullName = '$first $last'.trim();

    // record_status is the persisted column; older payloads only send status.
    final recordRaw =
        asJsonString(json['record_status']) ?? asJsonString(json['status']);

    List<InspectionPoint> parsePoints(dynamic v) {
      if (v is! List) return const [];
      return v
          .whereType<Map>()
          .map((e) => InspectionPoint.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    List<InspectionJobWorkRef> parseJobWorks(dynamic v) {
      if (v is! List) return const [];
      return v
          .whereType<Map>()
          .map((e) =>
              InspectionJobWorkRef.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    List<InspectionEvidencePhoto> parsePhotos(dynamic v) {
      if (v is! List) return const [];
      return v
          .whereType<Map>()
          .map((e) =>
              InspectionEvidencePhoto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final points = parsePoints(json['points']);
    final pointsCount = asJsonInt(json['points_count']) ?? points.length;
    final jobWorks = parseJobWorks(json['job_works']);
    final jobWorkCount =
        asJsonInt(json['job_work_count']) ?? jobWorks.length;

    return Inspection(
      id: asJsonInt(json['id']) ?? 0,
      title: asJsonString(json['title']) ?? 'Untitled Inspection',
      notes: asJsonString(json['notes']),
      status: InspectionStatus.fromString(recordRaw),
      inspectionNumber: asJsonString(json['inspection_number']),
      effectiveStatus: EffectiveInspectionStatus.fromString(
          asJsonString(json['effective_status'])),
      stationId: fkId(json['station']),
      stationName: asJsonString(json['station_name']),
      depotId: fkId(json['depot']),
      depotName: asJsonString(json['depot_name']),
      depotDivisionId: asJsonInt(json['depot_division_id']),
      infrastructureId: fkId(json['infrastructure']),
      infrastructureName: asJsonString(json['infrastructure_name']),
      infrastructureType: asJsonString(json['infrastructure_type']),
      lcGateNumber: asJsonString(json['lc_gate_number']),
      serviceBuildingName: asJsonString(json['service_building_name']),
      staffQuarterName: asJsonString(json['staff_quarter_name']),
      assetId: fkId(json['asset']),
      assetUniqueId: asJsonString(json['asset_unique_id']),
      assetName: asJsonString(json['asset_name']),
      generalAssetDescription:
          asJsonString(json['general_asset_description']),
      inspectionDate: parseDate(json['inspection_date']),
      createdAt: parseDate(json['created_at']),
      createdByName:
          fullName.isNotEmpty ? fullName : asJsonString(json['created_by_name']),
      createdByDesignation: asJsonString(json['created_by_designation']),
      createdByRole: asJsonString(json['created_by_role']),
      isConverted: asJsonBool(json['is_converted']) ?? false,
      workOrderId: asJsonInt(json['wo_id']),
      workOrderStatus: asJsonString(json['wo_status']),
      woAssignedToName: asJsonNonBlankString(json['wo_assigned_to_name']),
      pointsCount: pointsCount,
      unassignedPointsCount: asJsonInt(json['unassigned_points_count']) ?? 0,
      points: points,
      jobWorks: jobWorks,
      jobWorkCount: jobWorkCount,
      generalEvidencePhotos: parsePhotos(json['general_evidence_photos']),
    );
  }

  /// Local copy after a successful conversion, before the next refresh.
  Inspection markConverted({int? workOrderId}) {
    return Inspection(
      id: id,
      title: title,
      notes: notes,
      status: InspectionStatus.converted,
      inspectionNumber: inspectionNumber,
      effectiveStatus: effectiveStatus,
      stationId: stationId,
      stationName: stationName,
      depotId: depotId,
      depotName: depotName,
      depotDivisionId: depotDivisionId,
      infrastructureId: infrastructureId,
      infrastructureName: infrastructureName,
      infrastructureType: infrastructureType,
      lcGateNumber: lcGateNumber,
      serviceBuildingName: serviceBuildingName,
      staffQuarterName: staffQuarterName,
      assetId: assetId,
      assetUniqueId: assetUniqueId,
      assetName: assetName,
      generalAssetDescription: generalAssetDescription,
      inspectionDate: inspectionDate,
      createdAt: createdAt,
      createdByName: createdByName,
      createdByDesignation: createdByDesignation,
      createdByRole: createdByRole,
      isConverted: true,
      workOrderId: workOrderId ?? this.workOrderId,
      workOrderStatus: workOrderStatus,
      woAssignedToName: woAssignedToName,
      pointsCount: pointsCount,
      unassignedPointsCount: unassignedPointsCount,
      points: points,
      jobWorks: jobWorks,
      jobWorkCount: jobWorkCount,
      generalEvidencePhotos: generalEvidencePhotos,
    );
  }

  Inspection copyWithDetail({
    List<InspectionPoint>? points,
    List<InspectionEvidencePhoto>? generalEvidencePhotos,
    EffectiveInspectionStatus? effectiveStatus,
    InspectionStatus? status,
    bool? isConverted,
    int? workOrderId,
    String? workOrderStatus,
    String? woAssignedToName,
  }) {
    return Inspection(
      id: id,
      title: title,
      notes: notes,
      status: status ?? this.status,
      inspectionNumber: inspectionNumber,
      effectiveStatus: effectiveStatus ?? this.effectiveStatus,
      stationId: stationId,
      stationName: stationName,
      depotId: depotId,
      depotName: depotName,
      depotDivisionId: depotDivisionId,
      infrastructureId: infrastructureId,
      infrastructureName: infrastructureName,
      infrastructureType: infrastructureType,
      lcGateNumber: lcGateNumber,
      serviceBuildingName: serviceBuildingName,
      staffQuarterName: staffQuarterName,
      assetId: assetId,
      assetUniqueId: assetUniqueId,
      assetName: assetName,
      generalAssetDescription: generalAssetDescription,
      inspectionDate: inspectionDate,
      createdAt: createdAt,
      createdByName: createdByName,
      createdByDesignation: createdByDesignation,
      createdByRole: createdByRole,
      isConverted: isConverted ?? this.isConverted,
      workOrderId: workOrderId ?? this.workOrderId,
      workOrderStatus: workOrderStatus ?? this.workOrderStatus,
      woAssignedToName: woAssignedToName ?? this.woAssignedToName,
      pointsCount: points != null ? points.length : pointsCount,
      unassignedPointsCount: unassignedPointsCount,
      points: points ?? this.points,
      jobWorks: jobWorks,
      jobWorkCount: jobWorkCount,
      generalEvidencePhotos:
          generalEvidencePhotos ?? this.generalEvidencePhotos,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        notes,
        status,
        inspectionNumber,
        effectiveStatus,
        stationId,
        stationName,
        depotId,
        depotName,
        depotDivisionId,
        infrastructureId,
        infrastructureName,
        infrastructureType,
        lcGateNumber,
        serviceBuildingName,
        staffQuarterName,
        assetId,
        assetUniqueId,
        assetName,
        generalAssetDescription,
        inspectionDate,
        createdAt,
        createdByName,
        createdByDesignation,
        createdByRole,
        isConverted,
        workOrderId,
        workOrderStatus,
        woAssignedToName,
        pointsCount,
        unassignedPointsCount,
        points,
        jobWorks,
        jobWorkCount,
        generalEvidencePhotos,
      ];
}
