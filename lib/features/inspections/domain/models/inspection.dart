import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/domain/location_label.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

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

/// An inspection as `InspectionSerializer` returns it (SSOT §11.1).
///
/// Inspections have no priority/severity and no asset link (SSOT §11.3), and
/// no server-issued inspection number — the reference is `#<id>`.
class Inspection extends Equatable {
  const Inspection({
    required this.id,
    required this.title,
    this.notes,
    this.status = InspectionStatus.open,
    this.stationId,
    this.stationName,
    this.depotId,
    this.depotName,
    this.infrastructureName,
    this.infrastructureType,
    this.lcGateNumber,
    this.serviceBuildingName,
    this.staffQuarterName,
    this.inspectionDate,
    this.createdAt,
    this.createdByName,
    this.createdByDesignation,
    this.isConverted = false,
    this.workOrderId,
    this.workOrderStatus,
  });

  final int id;
  final String title;
  final String? notes;
  final InspectionStatus status;
  final int? stationId;
  final String? stationName;
  final int? depotId;
  final String? depotName;
  final String? infrastructureName;
  final String? infrastructureType;
  final String? lcGateNumber;
  final String? serviceBuildingName;
  final String? staffQuarterName;
  final DateTime? inspectionDate;
  final DateTime? createdAt;

  /// Inspector's full name when the serializer has it (`created_by_first_name`
  /// + `created_by_last_name`), otherwise the username (`created_by_name`).
  final String? createdByName;
  final String? createdByDesignation;

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

  /// User-facing reference.
  String get reference => '#$id';

  /// Web `getInfraName`: station, else LC gate / building / quarter.
  String? get locationLabel => infrastructureLocationLabel(
        stationName: stationName,
        lcGateNumber: lcGateNumber,
        serviceBuildingName: serviceBuildingName,
        staffQuarterName: staffQuarterName,
        infrastructureName: infrastructureName,
      );

  factory Inspection.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d == null || d == '') return null;
      return asJsonDateTime(d);
    }

    int? fkId(dynamic v) => v is Map ? asJsonInt(v['id']) : asJsonInt(v);

    final first = asJsonString(json['created_by_first_name'])?.trim() ?? '';
    final last = asJsonString(json['created_by_last_name'])?.trim() ?? '';
    final fullName = '$first $last'.trim();

    return Inspection(
      id: asJsonInt(json['id']) ?? 0,
      title: asJsonString(json['title']) ?? 'Untitled Inspection',
      notes: asJsonString(json['notes']),
      status: InspectionStatus.fromString(asJsonString(json['status'])),
      stationId: fkId(json['station']),
      stationName: asJsonString(json['station_name']),
      depotId: fkId(json['depot']),
      depotName: asJsonString(json['depot_name']),
      infrastructureName: asJsonString(json['infrastructure_name']),
      infrastructureType: asJsonString(json['infrastructure_type']),
      lcGateNumber: asJsonString(json['lc_gate_number']),
      serviceBuildingName: asJsonString(json['service_building_name']),
      staffQuarterName: asJsonString(json['staff_quarter_name']),
      inspectionDate: parseDate(json['inspection_date']),
      createdAt: parseDate(json['created_at']),
      createdByName:
          fullName.isNotEmpty ? fullName : asJsonString(json['created_by_name']),
      createdByDesignation: asJsonString(json['created_by_designation']),
      isConverted: asJsonBool(json['is_converted']) ?? false,
      workOrderId: asJsonInt(json['wo_id']),
      workOrderStatus: asJsonString(json['wo_status']),
    );
  }

  /// Local copy after a successful conversion, before the next refresh.
  Inspection markConverted({int? workOrderId}) {
    return Inspection(
      id: id,
      title: title,
      notes: notes,
      status: InspectionStatus.converted,
      stationId: stationId,
      stationName: stationName,
      depotId: depotId,
      depotName: depotName,
      infrastructureName: infrastructureName,
      infrastructureType: infrastructureType,
      lcGateNumber: lcGateNumber,
      serviceBuildingName: serviceBuildingName,
      staffQuarterName: staffQuarterName,
      inspectionDate: inspectionDate,
      createdAt: createdAt,
      createdByName: createdByName,
      createdByDesignation: createdByDesignation,
      isConverted: true,
      workOrderId: workOrderId ?? this.workOrderId,
      workOrderStatus: workOrderStatus,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        notes,
        status,
        stationId,
        stationName,
        depotId,
        depotName,
        infrastructureName,
        infrastructureType,
        lcGateNumber,
        serviceBuildingName,
        staffQuarterName,
        inspectionDate,
        createdAt,
        createdByName,
        createdByDesignation,
        isConverted,
        workOrderId,
        workOrderStatus,
      ];
}
