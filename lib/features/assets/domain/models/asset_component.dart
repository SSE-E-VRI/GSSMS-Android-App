import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// One row from `GET /api/v1/assets/{id}/components/` — a unified projection
/// of `AssetSetMember` (serialized sub-assets) and `InstalledComponent`
/// (minor parts), see `list_components` on the backend. Both source types
/// share this same field set (`serialize_asset_set_member`/
/// `serialize_installed_component`), so one model covers either.
class AssetComponent extends Equatable {
  const AssetComponent({
    required this.sourceId,
    required this.name,
    this.componentCode,
    this.make,
    this.model,
    this.serialNumber,
    this.status,
    this.installedOn,
    this.sourceType,
  });

  final String sourceId;
  final String name;
  final String? componentCode;
  final String? make;
  final String? model;
  final String? serialNumber;
  final String? status;
  final DateTime? installedOn;

  /// `INSTALLED_COMPONENT` or `ASSET_SET_MEMBER` (`source_type`).
  final String? sourceType;

  bool get isActive => status == 'IN_SERVICE';

  /// Only active installed components can be replaced through
  /// `installed-components/{id}/replace/` (web MaintenanceRecordForm filter).
  bool get isReplaceableInstalled =>
      sourceType == 'INSTALLED_COMPONENT' && status == 'IN_SERVICE';

  factory AssetComponent.fromJson(Map<String, dynamic> json) {
    return AssetComponent(
      sourceId: asJsonString(json['source_id']) ?? '',
      name: asJsonString(json['name']) ??
          asJsonString(json['unique_id']) ??
          'Component',
      componentCode: asJsonString(json['component_code']),
      make: asJsonString(json['make']),
      model: asJsonString(json['model']),
      serialNumber: asJsonString(json['serial_number']),
      status: asJsonString(json['status']),
      installedOn: asJsonString(json['installed_on']) != null
          ? asJsonDateTime(json['installed_on'])
          : null,
      sourceType: asJsonString(json['source_type']),
    );
  }

  @override
  List<Object?> get props =>
      [
        sourceId,
        name,
        componentCode,
        make,
        model,
        serialNumber,
        status,
        installedOn,
        sourceType,
      ];
}
