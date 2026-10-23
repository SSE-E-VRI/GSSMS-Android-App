import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';

/// One row of the "Deficiency Severity Assessment" / "Technician Remarks"
/// lists (`deficiency_rows[]` and `remark_deficiency_rows[]`). Remark rows
/// carry a `remark-N` string id.
class VerificationDeficiencyRow extends Equatable {
  const VerificationDeficiencyRow({
    required this.rowKey,
    this.remarkIndex,
    this.asset,
    this.checkpoint = '',
    this.finding = '',
    this.action = '',
    this.flaggedBy,
    this.severity,
    this.deficiencyId,
    this.deficiencyVersion,
    this.severityId,
    this.deficiencyStatus,
    this.willRaiseOnVerification = false,
    this.isRemark = false,
    this.isFlagged = false,
  });

  /// The row `id` as a string (int for checklist rows, `remark-N` for remarks).
  final String rowKey;
  final int? remarkIndex;
  final String? asset;
  final String checkpoint;
  final String finding;
  final String action;
  final String? flaggedBy;
  final String? severity;
  final int? deficiencyId;
  final int? deficiencyVersion;
  final int? severityId;
  final String? deficiencyStatus;
  final bool willRaiseOnVerification;
  final bool isRemark;
  final bool isFlagged;

  factory VerificationDeficiencyRow.fromJson(
    Map<String, dynamic> json, {
    bool isRemark = false,
  }) {
    final deficiencyId = asJsonInt(json['deficiency_id']);
    return VerificationDeficiencyRow(
      rowKey: asJsonString(json['id']) ?? '',
      remarkIndex: asJsonInt(json['remark_index']),
      asset: asJsonString(json['asset']),
      checkpoint: asJsonString(json['checkpoint']) ?? '',
      finding: asJsonString(json['finding']) ?? '',
      action: asJsonString(json['action']) ?? '',
      flaggedBy: asJsonString(json['flagged_by']),
      severity: asJsonString(json['severity']),
      deficiencyId: deficiencyId,
      deficiencyVersion: asJsonInt(json['deficiency_version']),
      severityId: asJsonInt(json['severity_id']),
      deficiencyStatus: asJsonString(json['deficiency_status']),
      willRaiseOnVerification:
          asJsonBool(json['will_raise_on_verification']) ?? false,
      isRemark: asJsonBool(json['is_remark']) ?? isRemark,
      isFlagged:
          asJsonBool(json['is_flagged']) ?? (isRemark && deficiencyId != null),
    );
  }

  @override
  List<Object?> get props => [
        rowKey,
        remarkIndex,
        asset,
        checkpoint,
        finding,
        action,
        flaggedBy,
        severity,
        deficiencyId,
        deficiencyVersion,
        severityId,
        deficiencyStatus,
        willRaiseOnVerification,
        isRemark,
        isFlagged,
      ];
}

/// `remark_asset_options[]`: `{key: <asset_unique_id>, label}`.
class RemarkAssetOption extends Equatable {
  const RemarkAssetOption({required this.key, required this.label});

  final String key;
  final String label;

  factory RemarkAssetOption.fromJson(Map<String, dynamic> json) =>
      RemarkAssetOption(
        key: asJsonString(json['key']) ?? '',
        label: asJsonString(json['label']) ?? asJsonString(json['key']) ?? '',
      );

  @override
  List<Object?> get props => [key, label];
}

/// `asset_groups[]` of the workspace (checklist group check-out state).
class VerificationAssetGroup extends Equatable {
  const VerificationAssetGroup({
    required this.key,
    this.assetCategoryId,
    this.assetName = '',
    this.displayName = '',
    this.checkedOut = false,
    this.checkoutSource = '',
  });

  final String key;
  final int? assetCategoryId;
  final String assetName;
  final String displayName;
  final bool checkedOut;

  /// `SUPERVISOR`, `TECHNICIAN` or empty.
  final String checkoutSource;

  factory VerificationAssetGroup.fromJson(Map<String, dynamic> json) {
    final assetName = asJsonString(json['asset_name']) ?? '';
    return VerificationAssetGroup(
      key: asJsonString(json['key']) ?? '',
      assetCategoryId: asJsonInt(json['asset_category_id']),
      assetName: assetName,
      displayName: asJsonString(json['display_name']) ?? assetName,
      checkedOut: asJsonBool(json['checked_out']) ?? false,
      checkoutSource: asJsonString(json['checkout_source']) ?? '',
    );
  }

  @override
  List<Object?> get props =>
      [key, assetCategoryId, assetName, displayName, checkedOut, checkoutSource];
}

/// Payload of `GET /maintenance/work-orders/{id}/verification-workspace/`.
///
/// Mirrors the web review modal's decision fields (`can_verify`,
/// `disabled_reasons`, `deficiencies`), the same `record` serializer the
/// checklist already parses, and the severity / remark / group check-out /
/// mode-execution projections added in web v1.9.
class VerificationWorkspace extends Equatable {
  const VerificationWorkspace({
    this.record,
    this.canVerify = false,
    this.disabledReasons = const [],
    this.deficiencies = const [],
    this.deficiencyCount = 0,
    this.workOrderStatus,
    this.executionMode,
    this.recordId,
    this.deficiencyRows = const [],
    this.remarkDeficiencyRows = const [],
    this.remarkAssetOptions = const [],
    this.assetGroups = const [],
    this.complaintExecution,
    this.rectification,
    this.inspectionExecution,
  });

  /// `work_order.status`, e.g. `TECH_COMPLETED`.
  final String? workOrderStatus;

  /// `work_order.execution_mode` (null/empty means CHECKLIST).
  final String? executionMode;

  /// `record.id`.
  final int? recordId;
  final List<VerificationDeficiencyRow> deficiencyRows;
  final List<VerificationDeficiencyRow> remarkDeficiencyRows;
  final List<RemarkAssetOption> remarkAssetOptions;
  final List<VerificationAssetGroup> assetGroups;
  final ComplaintExecution? complaintExecution;
  final RectificationPayload? rectification;
  final PointwiseInspectionExecution? inspectionExecution;

  /// Upper-case execution mode; CHECKLIST when absent.
  String get mode {
    final m = (executionMode ?? '').trim().toUpperCase();
    return m.isEmpty ? 'CHECKLIST' : m;
  }

  final MaintenanceRecord? record;
  final bool canVerify;
  final List<String> disabledReasons;

  /// Human-readable `count severity` summaries, e.g. "2 CRITICAL".
  final List<String> deficiencies;

  /// Total deficiency count across all severities — the server returns one
  /// aggregate row per severity (`{'severity': ..., 'count': ...}`), not one
  /// row per deficiency, so this sums `count` rather than counting rows.
  final int deficiencyCount;

  factory VerificationWorkspace.fromJson(Map<String, dynamic> json) {
    MaintenanceRecord? record;
    final rawRecord = json['record'];
    if (rawRecord is Map) {
      record = MaintenanceRecord.fromJson(Map<String, dynamic>.from(rawRecord));
    }

    final deficiencySummary = _deficiencySummary(json['deficiencies']);

    final rawWo = json['work_order'];
    final wo = rawWo is Map ? Map<String, dynamic>.from(rawWo) : null;
    final rawInspection = wo?['inspection_execution'];
    final rawComplaint = json['complaint_execution'];
    final rawRectification = json['rectification'];

    return VerificationWorkspace(
      record: record,
      canVerify: asJsonBool(json['can_verify']) ?? false,
      disabledReasons: _stringList(json['disabled_reasons']),
      deficiencies: deficiencySummary.labels,
      deficiencyCount: deficiencySummary.total,
      workOrderStatus: asJsonString(wo?['status']),
      executionMode: asJsonString(wo?['execution_mode']),
      recordId: rawRecord is Map ? asJsonInt(rawRecord['id']) : null,
      deficiencyRows:
          _mapList(json['deficiency_rows'], VerificationDeficiencyRow.fromJson),
      remarkDeficiencyRows: _mapList(
        json['remark_deficiency_rows'],
        (m) => VerificationDeficiencyRow.fromJson(m, isRemark: true),
      ),
      remarkAssetOptions:
          _mapList(json['remark_asset_options'], RemarkAssetOption.fromJson),
      assetGroups:
          _mapList(json['asset_groups'], VerificationAssetGroup.fromJson),
      complaintExecution: rawComplaint is Map
          ? ComplaintExecution.fromJson(Map<String, dynamic>.from(rawComplaint))
          : null,
      rectification: rawRectification is Map
          ? RectificationPayload.fromJson(
              Map<String, dynamic>.from(rawRectification))
          : null,
      inspectionExecution: rawInspection is Map
          ? PointwiseInspectionExecution.fromJson(
              Map<String, dynamic>.from(rawInspection))
          : null,
    );
  }

  @override
  List<Object?> get props => [
        record,
        canVerify,
        disabledReasons,
        deficiencies,
        deficiencyCount,
        workOrderStatus,
        executionMode,
        recordId,
        deficiencyRows,
        remarkDeficiencyRows,
        remarkAssetOptions,
        assetGroups,
        complaintExecution,
        rectification,
        inspectionExecution,
      ];
}

List<T> _mapList<T>(dynamic raw, T Function(Map<String, dynamic>) parse) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => parse(Map<String, dynamic>.from(e)))
      .toList();
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map(asJsonString)
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Parses the `deficiencies` list the workspace endpoint actually returns:
/// one aggregate row per severity, `{'severity': <label>, 'count': <int>}`
/// (see `ExecutionChecklistService.get_verification_workspace`) — not one
/// row per deficient line. Falls back to a per-item label for any other
/// shape rather than dropping the row silently.
({List<String> labels, int total}) _deficiencySummary(dynamic raw) {
  if (raw is! List) return (labels: const [], total: 0);

  final labels = <String>[];
  var total = 0;
  for (final item in raw) {
    if (item is String) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty) {
        labels.add(trimmed);
        total += 1;
      }
      continue;
    }
    if (item is Map) {
      final map = Map<String, dynamic>.from(item);
      final severity = asJsonString(map['severity']);
      final count = asJsonInt(map['count']);
      if (severity != null && severity.trim().isNotEmpty && count != null) {
        labels.add('$count ${severity.trim()}');
        total += count;
        continue;
      }
      // Unexpected shape: fall back to whatever label-ish field is present
      // so a deficiency is still visible rather than silently dropped.
      final label = asJsonString(map['label']) ??
          asJsonString(map['item_name']) ??
          asJsonString(map['inspection_point']) ??
          asJsonString(map['name']) ??
          asJsonString(map['description']);
      if (label != null && label.trim().isNotEmpty) {
        labels.add(label.trim());
        total += 1;
      }
    }
  }
  return (labels: labels, total: total);
}
