import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// An active deficiency severity (`GET /deficiency-severities/`).
class DeficiencySeverityOption extends Equatable {
  const DeficiencySeverityOption({
    required this.id,
    this.code = '',
    this.label = '',
  });

  final int id;
  final String code;
  final String label;

  factory DeficiencySeverityOption.fromJson(Map<String, dynamic> json) {
    final code = asJsonString(json['code']) ?? '';
    return DeficiencySeverityOption(
      id: asJsonInt(json['id']) ?? 0,
      code: code,
      label: asJsonString(json['label']) ?? code,
    );
  }

  /// Parses a bare list or a `{results: [...]}` envelope.
  static List<DeficiencySeverityOption> listFromJson(dynamic data) {
    final raw = data is List
        ? data
        : (data is Map && data['results'] is List
            ? data['results'] as List
            : const []);
    return raw
        .whereType<Map>()
        .map((e) =>
            DeficiencySeverityOption.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  List<Object?> get props => [id, code, label];
}

/// Subset of the Deficiency returned by `PATCH /deficiencies/{id}/`.
class DeficiencySeverityUpdate extends Equatable {
  const DeficiencySeverityUpdate({
    required this.id,
    this.severityId,
    this.severityLabel,
    this.version,
  });

  final int id;
  final int? severityId;
  final String? severityLabel;
  final int? version;

  factory DeficiencySeverityUpdate.fromJson(Map<String, dynamic> json) {
    final sev = json['severity'];
    return DeficiencySeverityUpdate(
      id: asJsonInt(json['id']) ?? 0,
      severityId: sev is Map ? asJsonInt(sev['id']) : asJsonInt(sev),
      severityLabel: asJsonString(json['severity_label']),
      version: asJsonInt(json['version']),
    );
  }

  @override
  List<Object?> get props => [id, severityId, severityLabel, version];
}

/// Response of `POST .../flag-remark-deficiency/`.
class RemarkFlagResult extends Equatable {
  const RemarkFlagResult({
    required this.id,
    this.remarkIndex,
    this.version,
    this.severityId,
    this.severityLabel,
    this.assetLabel,
    this.status,
  });

  final int id;
  final int? remarkIndex;
  final int? version;
  final int? severityId;
  final String? severityLabel;
  final String? assetLabel;
  final String? status;

  factory RemarkFlagResult.fromJson(Map<String, dynamic> json) {
    return RemarkFlagResult(
      id: asJsonInt(json['id']) ?? 0,
      remarkIndex: asJsonInt(json['remark_index']),
      version: asJsonInt(json['version']),
      severityId: asJsonInt(json['severity_id']),
      severityLabel: asJsonString(json['severity_label']),
      assetLabel: asJsonString(json['asset_label']),
      status: asJsonString(json['status']),
    );
  }

  @override
  List<Object?> get props =>
      [id, remarkIndex, version, severityId, severityLabel, assetLabel, status];
}
