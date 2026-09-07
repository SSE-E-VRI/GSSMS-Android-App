import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// A station or infrastructure row used by the reports type/item dropdowns.
class InfrastructureOption extends Equatable {
  const InfrastructureOption({required this.id, required this.name});

  final int id;
  final String name;

  factory InfrastructureOption.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final name = asJsonString(json['name']) ??
        asJsonString(json['station_name']) ??
        asJsonString(json['title']) ??
        asJsonString(json['code']) ??
        'Item #$id';
    return InfrastructureOption(id: id, name: name);
  }

  @override
  List<Object?> get props => [id, name];
}

/// Web ReportsView infrastructure types. `queryCode` is what the options
/// endpoint and register_report query params use (`null` means "All").
enum InfraFilterType {
  all(null, 'All'),
  station('STATION', 'Station'),
  lcGate('LC', 'LC Gate'),
  serviceBuilding('SB', 'Service Building'),
  staffQuarter('SQ', 'Staff Quarter');

  const InfraFilterType(this.queryCode, this.label);

  final String? queryCode;
  final String label;

  /// Query key consumed by `register_report` (`LEGACY_INFRA_ID_PARAMS`).
  String? get registerIdParam {
    switch (this) {
      case InfraFilterType.all:
        return null;
      case InfraFilterType.station:
        return 'station_id';
      case InfraFilterType.lcGate:
        return 'lc_gate_id';
      case InfraFilterType.serviceBuilding:
        return 'service_building_id';
      case InfraFilterType.staffQuarter:
        return 'staff_quarter_id';
    }
  }

  /// Value for `register_report`'s `infra_type` fallback param
  /// (`MAINTENANCE_INFRA_TYPE_TO_CODE` keys) — distinct from [queryCode],
  /// which is the short `type_code` the `/infrastructure/` options endpoint
  /// uses. `filter_legacy_infrastructure_params` only reads `infra_type` when
  /// no specific item id is present, so this is what makes "Type selected,
  /// no specific item" (i.e. "All LC Gates") actually filter anything —
  /// without it, that selection silently filtered nothing.
  String? get registerTypeParam {
    switch (this) {
      case InfraFilterType.all:
        return null;
      case InfraFilterType.station:
        return 'STATION';
      case InfraFilterType.lcGate:
        return 'LC_GATE';
      case InfraFilterType.serviceBuilding:
        return 'SERVICE_BUILDING';
      case InfraFilterType.staffQuarter:
        return 'STAFF_QUARTER';
    }
  }
}
