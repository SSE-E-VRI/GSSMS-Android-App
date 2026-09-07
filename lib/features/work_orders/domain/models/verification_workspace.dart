import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';

/// Payload of `GET /maintenance/work-orders/{id}/verification-workspace/`.
///
/// Mirrors the web review modal's *decision* fields (`can_verify`,
/// `disabled_reasons`, `deficiencies`) plus the same `record` serializer the
/// checklist already parses. Web-only presentation projections
/// (`certificate_groups`, `asset_groups`) are ignored.
class VerificationWorkspace extends Equatable {
  const VerificationWorkspace({
    this.record,
    this.canVerify = false,
    this.disabledReasons = const [],
    this.deficiencies = const [],
    this.deficiencyCount = 0,
  });

  final MaintenanceRecord? record;
  final bool canVerify;
  final List<String> disabledReasons;

  /// Human-readable "<count> <severity>" summaries, e.g. "2 CRITICAL".
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

    return VerificationWorkspace(
      record: record,
      canVerify: asJsonBool(json['can_verify']) ?? false,
      disabledReasons: _stringList(json['disabled_reasons']),
      deficiencies: deficiencySummary.labels,
      deficiencyCount: deficiencySummary.total,
    );
  }

  @override
  List<Object?> get props =>
      [record, canVerify, disabledReasons, deficiencies, deficiencyCount];
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
