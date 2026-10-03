import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

int? _fk(dynamic v) => v is Map ? asJsonInt(v['id']) : asJsonInt(v);

/// A supervisor INCLUDE / EXCLUDE decision for one checklist asset group of a
/// preventive Job Work, taken before START (`GET|POST .../supervisor-mandate/`).
class SupervisorMandate extends Equatable {
  const SupervisorMandate({
    required this.id,
    this.assetCategoryId,
    this.assetCategoryName,
    this.assetName = '',
    this.action = 'INCLUDE',
    this.reason = '',
    this.mandatedByName,
    this.updatedAt,
  });

  final int id;
  final int? assetCategoryId;
  final String? assetCategoryName;
  final String assetName;

  /// `INCLUDE` or `EXCLUDE`.
  final String action;
  final String reason;
  final String? mandatedByName;
  final DateTime? updatedAt;

  bool get isExclude => action.toUpperCase() == 'EXCLUDE';

  factory SupervisorMandate.fromJson(Map<String, dynamic> json) {
    final updated = json['updated_at'];
    return SupervisorMandate(
      id: asJsonInt(json['id']) ?? 0,
      assetCategoryId: _fk(json['asset_category']),
      assetCategoryName: asJsonString(json['asset_category_name']),
      assetName: asJsonString(json['asset_name']) ?? '',
      action: (asJsonString(json['action']) ?? 'INCLUDE').toUpperCase(),
      reason: asJsonString(json['reason']) ?? '',
      mandatedByName: asJsonString(json['mandated_by_name']),
      updatedAt: updated is String && updated.isNotEmpty
          ? asJsonDateTime(updated)
          : null,
    );
  }

  /// Parses a bare list or a `{results: [...]}` envelope.
  static List<SupervisorMandate> listFromJson(dynamic data) {
    final raw = data is List
        ? data
        : (data is Map && data['results'] is List
            ? data['results'] as List
            : const []);
    return raw
        .whereType<Map>()
        .map((e) => SupervisorMandate.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  List<Object?> get props => [
        id,
        assetCategoryId,
        assetCategoryName,
        assetName,
        action,
        reason,
        mandatedByName,
        updatedAt,
      ];
}

/// One asset group of a checklist master, shown in the pre-START preview
/// (`GET /maintenance/masters/{id}/workspace/`).
class ChecklistGroupPreview extends Equatable {
  const ChecklistGroupPreview({
    this.assetCategoryId,
    this.assetCategoryName,
    this.assetName = '',
    this.itemCount = 0,
  });

  final int? assetCategoryId;
  final String? assetCategoryName;
  final String assetName;

  /// `points.length + parameters.length`.
  final int itemCount;

  String get title =>
      assetCategoryName ?? (assetName.isNotEmpty ? assetName : 'General Items');

  bool get canMandate => assetCategoryId != null || assetName.isNotEmpty;

  factory ChecklistGroupPreview.fromJson(Map<String, dynamic> json) {
    int len(dynamic v) => v is List ? v.length : 0;
    return ChecklistGroupPreview(
      assetCategoryId: _fk(json['asset_category']),
      assetCategoryName: asJsonString(json['asset_category_name']),
      assetName: asJsonString(json['asset_name']) ?? '',
      itemCount: len(json['points']) + len(json['parameters']),
    );
  }

  @override
  List<Object?> get props =>
      [assetCategoryId, assetCategoryName, assetName, itemCount];
}

/// Result of `POST .../prepare-checklist/`. `preview == true` means no record
/// was created yet (NEW/ASSIGNED PM Job Work); [masterId] then drives the
/// group preview.
class PrepareChecklistResult extends Equatable {
  const PrepareChecklistResult({
    this.recordId,
    this.created = false,
    this.lineCount = 0,
    this.preview = false,
    this.masterId,
    this.executionMode,
  });

  final int? recordId;
  final bool created;
  final int lineCount;
  final bool preview;
  final int? masterId;
  final String? executionMode;

  factory PrepareChecklistResult.fromJson(Map<String, dynamic> json) {
    return PrepareChecklistResult(
      recordId: asJsonInt(json['record_id']),
      created: asJsonBool(json['created']) ?? false,
      lineCount: asJsonInt(json['line_count']) ?? 0,
      preview: asJsonBool(json['preview']) ?? false,
      masterId: asJsonInt(json['master_id']),
      executionMode: asJsonString(json['execution_mode']),
    );
  }

  @override
  List<Object?> get props =>
      [recordId, created, lineCount, preview, masterId, executionMode];
}
