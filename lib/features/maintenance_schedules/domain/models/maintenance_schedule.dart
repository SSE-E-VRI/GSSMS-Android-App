import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Canonical values from `MaintenanceSchedule.STATUS_CHOICES` (backend
/// `maintenance/models.py`). Note this is the *schedule's* status, distinct
/// from `WorkOrderStatus` once it's converted.
enum ScheduleStatus {
  pending('PENDING', 'Pending'),
  inProgress('IN_PROGRESS', 'In Progress'),
  completed('COMPLETED', 'Completed'),
  overdue('OVERDUE', 'Overdue'),
  skipped('SKIPPED', 'Skipped'),
  unknown('UNKNOWN', 'Unknown');

  const ScheduleStatus(this.code, this.displayName);
  final String code;
  final String displayName;

  static ScheduleStatus fromString(String? code) {
    if (code == null) return ScheduleStatus.unknown;
    final upper = code.trim().toUpperCase();
    for (final s in ScheduleStatus.values) {
      if (s.code == upper) return s;
    }
    return ScheduleStatus.unknown;
  }
}

/// Eligibility result from `SchedulingService.check_occurrence_eligibility`.
class ScheduleEligibility {
  const ScheduleEligibility({
    required this.eligible,
    this.reason,
    this.code,
  });

  final bool eligible;
  final String? reason;
  final String? code;

  factory ScheduleEligibility.fromJson(Map<String, dynamic> json) {
    return ScheduleEligibility(
      eligible: json['eligible'] == true,
      reason: asJsonString(json['reason']),
      code: asJsonString(json['code']),
    );
  }
}

/// Template summary returned in upcoming/conversion-context payloads.
class TemplateRef {
  const TemplateRef({required this.id, required this.name, this.source});
  final int id;
  final String name;
  final String? source;

  factory TemplateRef.fromJson(Map<String, dynamic> json) {
    return TemplateRef(
      id: asJsonInt(json['id']) ?? 0,
      name: asJsonString(json['name']) ?? '',
      source: asJsonString(json['source']),
    );
  }
}

/// One row from `GET /api/v1/maintenance/schedules/pending/`
/// (`MaintenanceScheduleSerializer`) — a scheduled preventive-maintenance
/// task awaiting conversion into (or completion of) a Job Work.
///
/// Also used for Endpoint L (`upcoming`) which adds [periodStart],
/// [templateSource], [eligibility], and [defaultTemplate].
class MaintenanceSchedule extends Equatable {
  const MaintenanceSchedule({
    required this.id,
    required this.templateName,
    this.scheduleType,
    this.stationName,
    this.depotName,
    required this.status,
    this.dueDate,
    this.workOrderId,
    this.workOrderTicket,
    this.workOrderStatus,
    this.isBreakdown = false,
    // S7 fields
    this.periodStart,
    this.templateSource,
    this.eligibility,
    this.defaultTemplate,
    // C1 asset scope: present only for asset occurrences; null for
    // station/infrastructure occurrences (and for cached payloads that
    // predate these keys — parsing stays null-safe).
    this.assetId,
    this.assetName,
    this.assetUniqueId,
    this.terminationReason,
    this.skipSupported = false,
  });

  final int id;
  final String templateName;
  final String? scheduleType;
  final String? stationName;
  final String? depotName;
  final ScheduleStatus status;
  final DateTime? dueDate;

  /// From `work_order_id`/`work_order_ticket`/`work_order_status` — set once
  /// this schedule has already been converted (mirrors Inspection/Complaint's
  /// `isConverted`/`workOrderId` pattern, just derived from a non-null id
  /// here since the serializer has no separate boolean flag).
  final int? workOrderId;
  final String? workOrderTicket;
  final String? workOrderStatus;

  /// Backing row of a breakdown (corrective) job, not a scheduled task.
  final bool isBreakdown;
  // S7: present only when fetched via Endpoint L (upcoming).
  final DateTime? periodStart;
  final String? templateSource;
  final ScheduleEligibility? eligibility;
  final TemplateRef? defaultTemplate;

  // C1: the occurrence's asset when it has one (raw `asset` id on the wire),
  // its display name / unique id, and why a SKIPPED row was closed early.
  final int? assetId;
  final String? assetName;
  final String? assetUniqueId;
  final String? terminationReason;
  final bool skipSupported;

  bool get isConverted => workOrderId != null;
  bool get isEligible => eligibility?.eligible ?? false;

  /// Human label for [terminationReason] (`ASSET_TRANSFERRED` →
  /// 'Asset Transferred'); null when there is no reason.
  String? get terminationLabel {
    final raw = terminationReason;
    if (raw == null || raw.trim().isEmpty) return null;
    return raw
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }

  /// A skipped occurrence (owner/DIV_ADMIN-approved) must never be offered
  /// for batch conversion - the backend refuses it with 400 regardless, so
  /// this is what stops the UI from offering an action it knows will fail.
  bool get isSkipped => status == ScheduleStatus.skipped;

  factory MaintenanceSchedule.fromJson(Map<String, dynamic> json) {
    ScheduleEligibility? eligibility;
    if (json['eligibility'] is Map) {
      eligibility = ScheduleEligibility.fromJson(
          Map<String, dynamic>.from(json['eligibility'] as Map));
    }
    TemplateRef? defaultTemplate;
    if (json['default_template'] is Map) {
      defaultTemplate = TemplateRef.fromJson(
          Map<String, dynamic>.from(json['default_template'] as Map));
    }
    return MaintenanceSchedule(
      id: asJsonInt(json['id']) ?? 0,
      templateName: asJsonString(json['template_name']) ??
          asJsonString(json['maintenance_master_name']) ??
          'Maintenance Task',
      scheduleType: asJsonString(json['schedule_type']),
      stationName: asJsonString(json['station_name']),
      depotName: asJsonString(json['depot_name']),
      status: ScheduleStatus.fromString(asJsonString(json['status'])),
      dueDate: asJsonString(json['due_date']) != null
          ? asJsonDateTime(json['due_date'])
          : null,
      workOrderId: asJsonInt(json['work_order_id']),
      workOrderTicket: asJsonString(json['work_order_ticket']),
      workOrderStatus: asJsonString(json['work_order_status']),
      isBreakdown: asJsonBool(json['is_breakdown']) ?? false,
      periodStart: asJsonString(json['period_start']) != null
          ? asJsonDateTime(json['period_start'])
          : null,
      templateSource: asJsonString(json['template_source']),
      eligibility: eligibility,
      defaultTemplate: defaultTemplate,
      assetId: asJsonInt(json['asset']),
      assetName: asJsonString(json['asset_name']),
      assetUniqueId: asJsonString(json['asset_unique_id']),
      terminationReason: asJsonString(json['termination_reason']),
      skipSupported: asJsonBool(json['skip_supported']) ??
          (json['obligation_master'] != null),
    );
  }

  @override
  List<Object?> get props => [
        id,
        templateName,
        scheduleType,
        stationName,
        depotName,
        status,
        dueDate,
        workOrderId,
        workOrderTicket,
        workOrderStatus,
        isBreakdown,
        periodStart,
        templateSource,
        assetId,
        assetName,
        assetUniqueId,
        terminationReason,
        skipSupported,
      ];
}
