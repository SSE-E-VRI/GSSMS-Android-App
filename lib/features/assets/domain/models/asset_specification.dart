import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// One field from `GET /api/v1/assets/{id}/specifications/`'s `template.fields`
/// array (`get_asset_specifications_workspace` on the backend) — read-only on
/// mobile (editing specification values stays a web-only workflow, same
/// reasoning as Deficiencies being view-only here).
class AssetSpecificationField extends Equatable {
  const AssetSpecificationField({
    required this.label,
    this.unit,
    this.installedValue,
    this.notAvailableReason,
  });

  final String label;
  final String? unit;
  final String? installedValue;
  final String? notAvailableReason;

  factory AssetSpecificationField.fromJson(Map<String, dynamic> json) {
    return AssetSpecificationField(
      label: asJsonString(json['label']) ?? asJsonString(json['field_key']) ?? 'Field',
      unit: asJsonString(json['unit']),
      installedValue: json['installed_value']?.toString(),
      notAvailableReason: asJsonString(json['not_available_reason']),
    );
  }

  @override
  List<Object?> get props => [label, unit, installedValue, notAvailableReason];
}

/// `GET /api/v1/assets/{id}/specifications/` response — an
/// `assignment_state` (UNASSIGNED/ASSIGNED/CONFLICT/SUGGESTED) plus the
/// template's fields when one is assigned or suggested.
class AssetSpecificationWorkspace extends Equatable {
  const AssetSpecificationWorkspace({
    required this.assignmentState,
    this.templateName,
    this.fields = const [],
  });

  final String assignmentState;
  final String? templateName;
  final List<AssetSpecificationField> fields;

  factory AssetSpecificationWorkspace.fromJson(Map<String, dynamic> json) {
    final template = json['template'] is Map
        ? Map<String, dynamic>.from(json['template'] as Map)
        : null;
    final rawFields = json['fields'];
    return AssetSpecificationWorkspace(
      assignmentState: asJsonString(json['assignment_state']) ?? 'UNASSIGNED',
      templateName: template != null ? asJsonString(template['name']) : null,
      fields: rawFields is List
          ? rawFields
              .whereType<Map>()
              .map((e) => AssetSpecificationField.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  @override
  List<Object?> get props => [assignmentState, templateName, fields];
}
