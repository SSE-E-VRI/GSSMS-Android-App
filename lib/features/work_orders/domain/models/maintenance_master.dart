import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Checklist/template schedule frequency, matching
/// `MaintenanceMaster.SCHEDULE_TYPE_CHOICES` in the Django backend.
///
/// Deliberately does NOT include a "fortnightly" option — the backend has no
/// such choice today (SSOT open item), so a client-side value here would be
/// unsendable/unfilterable against anything the server actually returns.
enum MaintenanceScheduleType {
  daily('DAILY', 'Daily'),
  weekly('WEEKLY', 'Weekly'),
  monthly('MONTHLY', 'Monthly'),
  quarterly('QUARTERLY', 'Quarterly'),
  halfYearly('HALF_YEARLY', 'Half Yearly'),
  yearly('YEARLY', 'Yearly'),
  unknown('UNKNOWN', 'Unknown');

  const MaintenanceScheduleType(this.code, this.displayName);

  final String code;
  final String displayName;

  static MaintenanceScheduleType fromString(String? code) {
    if (code == null) return MaintenanceScheduleType.unknown;
    final normalized = code.trim().toUpperCase();
    for (final type in MaintenanceScheduleType.values) {
      if (type.code == normalized) return type;
    }
    return MaintenanceScheduleType.unknown;
  }
}

/// Template category, matching `MaintenanceMaster.TEMPLATE_KIND_CHOICES`.
///
/// The backend/web term for `STATION_TEMPLATE` is "Station Template"; it is
/// labelled "Station / Batch Template" here since that scope — one template
/// applied across a whole station/infrastructure rather than one specific
/// asset — is what "batch job work" refers to. The API value sent/received
/// is always `STATION_TEMPLATE`; only the display label differs (SSOT Rule 4).
enum MaintenanceTemplateKind {
  assetTemplate('ASSET_TEMPLATE', 'Asset Template'),
  stationTemplate('STATION_TEMPLATE', 'Station / Batch Template'),
  // S-V4: the backend sends four more kinds since checklist versioning
  // (S-V1/S-V2/S-V3). AMC is listed by default and must render correctly;
  // the ad hoc kinds (handover/takeover/specialDrive) stay server-side
  // opt-in until S-V5, but they parse explicitly so a future response
  // naming them never silently misclassifies as Asset.
  amc('AMC', 'AMC'),
  handover('HANDOVER', 'Handing Over'),
  takeover('TAKEOVER', 'Taking Over'),
  specialDrive('SPECIAL_DRIVE', 'Special Drive'),
  unknown('UNKNOWN', 'Unknown');

  const MaintenanceTemplateKind(this.code, this.displayName);

  final String code;
  final String displayName;

  static MaintenanceTemplateKind fromString(String? code) {
    if (code == null) return MaintenanceTemplateKind.assetTemplate;
    final normalized = code.trim().toUpperCase();
    for (final kind in MaintenanceTemplateKind.values) {
      if (kind.code == normalized) return kind;
    }
    // Rows predating template_kind default to Asset Template server-side
    // (backend comment: "Any row missing template_kind ... falls into Asset
    // Templates") — mirrored here so an unrecognised/missing value doesn't
    // get dropped from either filter tab.
    return MaintenanceTemplateKind.assetTemplate;
  }
}

/// A maintenance checklist template (`MaintenanceMaster`), as offered when
/// picking a Template/Checklist during Job Work creation.
class MaintenanceMaster extends Equatable {
  const MaintenanceMaster({
    required this.id,
    required this.name,
    required this.scheduleType,
    required this.templateKind,
    this.active = true,
    // S-V1 checklist version ("1.2.0"), surfaced in S-V4. Null for legacy
    // or unversioned rows — parsing must never break on its absence.
    this.version,
  });

  final int id;
  final String name;
  final MaintenanceScheduleType scheduleType;
  final MaintenanceTemplateKind templateKind;
  final bool active;
  final String? version;

  /// "Name (Schedule)" plus " vX.Y.Z" when the server sent a version —
  /// the label the template picker shows per row.
  String get displayLabel {
    final base = '$name (${scheduleType.displayName})';
    final v = version?.trim();
    if (v == null || v.isEmpty) return base;
    return '$base v$v';
  }

  factory MaintenanceMaster.fromJson(Map<String, dynamic> json) {
    return MaintenanceMaster(
      id: asJsonInt(json['id']) ?? 0,
      name: asJsonString(json['name']) ?? 'Untitled Template',
      scheduleType: MaintenanceScheduleType.fromString(
          asJsonString(json['schedule_type'])),
      templateKind: MaintenanceTemplateKind.fromString(
          asJsonString(json['template_kind'])),
      active: asJsonBool(json['active']) ?? true,
      version: asJsonString(json['version']),
    );
  }

  @override
  List<Object?> get props =>
      [id, name, scheduleType, templateKind, active, version];
}
