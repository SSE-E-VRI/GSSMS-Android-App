import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Canonical values from `Deficiency.STATUS_CHOICES` (backend
/// `assets/models.py`). The `pending` list this powers already excludes
/// CLOSED server-side, but the enum still needs it for anything that reads
/// a deficiency elsewhere later.
enum DeficiencyStatus {
  open('OPEN', 'Open'),
  assigned('ASSIGNED', 'Assigned'),
  inProgress('IN_PROGRESS', 'In Progress'),
  resolved('RESOLVED', 'Resolved'),
  closed('CLOSED', 'Closed'),
  unknown('UNKNOWN', 'Unknown');

  const DeficiencyStatus(this.code, this.displayName);
  final String code;
  final String displayName;

  static DeficiencyStatus fromString(String? code) {
    if (code == null) return DeficiencyStatus.unknown;
    final upper = code.trim().toUpperCase();
    for (final s in DeficiencyStatus.values) {
      if (s.code == upper) return s;
    }
    return DeficiencyStatus.unknown;
  }
}

/// One row from `GET /api/v1/deficiencies/pending/` (`DeficiencySerializer`
/// in `assets/serializers.py`). Read-only on mobile — web's own Pending
/// Actions tab for this type has no batch-convert action either, only a
/// deep link into the asset's Deficiencies tab, which mobile mirrors by
/// opening the asset detail screen.
class Deficiency extends Equatable {
  const Deficiency({
    required this.id,
    this.code,
    required this.description,
    this.deficiencyFinding,
    this.status = DeficiencyStatus.open,
    this.severityLabel,
    this.sourceLabel,
    this.assetId,
    this.assetUniqueId,
    this.equipmentName,
    this.reportAssetEquipment,
    this.reportCheckpoint,
    this.depotName,
    this.workOrderId,
    this.workOrderTicket,
    this.detectedAt,
  });

  final int id;
  final String? code;
  final String description;
  final String? deficiencyFinding;
  final DeficiencyStatus status;
  final String? severityLabel;
  final String? sourceLabel;
  final int? assetId;
  final String? assetUniqueId;
  final String? equipmentName;

  /// Web's "Asset/Equipment" column source (`report_asset_equipment`) — the
  /// report-formatted label, distinct from [equipmentName]. See
  /// [displayAssetEquipment] for the same fallback chain web uses.
  final String? reportAssetEquipment;

  /// Web's "Checkpoint" column (`report_checkpoint`) — which checklist
  /// point/inspection item this deficiency was raised against.
  final String? reportCheckpoint;
  final String? depotName;
  final int? workOrderId;
  final String? workOrderTicket;
  final DateTime? detectedAt;

  /// The line to show as the card's main text — the human-readable finding
  /// when present, falling back to the raw description (mirrors web's
  /// `item.deficiency_finding || item.description`).
  String get displayFinding =>
      (deficiencyFinding != null && deficiencyFinding!.isNotEmpty)
          ? deficiencyFinding!
          : description;

  /// Web's "Asset/Equipment" column: `report_asset_equipment || asset_unique_id || 'General'`.
  String get displayAssetEquipment {
    if (reportAssetEquipment != null && reportAssetEquipment!.isNotEmpty) {
      return reportAssetEquipment!;
    }
    if (assetUniqueId != null && assetUniqueId!.isNotEmpty) return assetUniqueId!;
    return 'General';
  }

  factory Deficiency.fromJson(Map<String, dynamic> json) {
    return Deficiency(
      id: asJsonInt(json['id']) ?? 0,
      code: asJsonString(json['code']),
      description: asJsonString(json['description']) ?? '',
      deficiencyFinding: asJsonString(json['deficiency_finding']),
      status: DeficiencyStatus.fromString(asJsonString(json['status'])),
      severityLabel: asJsonString(json['severity_label']),
      sourceLabel: asJsonString(json['source_label']),
      assetId: asJsonInt(json['asset']),
      assetUniqueId: asJsonString(json['asset_unique_id']),
      equipmentName: asJsonString(json['equipment_name']),
      reportAssetEquipment: asJsonString(json['report_asset_equipment']),
      reportCheckpoint: asJsonString(json['report_checkpoint']),
      depotName: asJsonString(json['depot_name']),
      workOrderId: asJsonInt(json['work_order_id']),
      workOrderTicket: asJsonString(json['work_order_ticket']),
      detectedAt: asJsonString(json['detected_at']) != null
          ? DateTime.tryParse(json['detected_at'].toString())
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        code,
        description,
        deficiencyFinding,
        status,
        severityLabel,
        sourceLabel,
        assetId,
        assetUniqueId,
        equipmentName,
        reportAssetEquipment,
        reportCheckpoint,
        depotName,
        workOrderId,
        workOrderTicket,
        detectedAt,
      ];
}
