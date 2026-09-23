import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

enum OrgScopeLevel {
  global('GLOBAL'),
  zone('ZONE'),
  division('DIVISION'),
  depot('DEPOT'),
  self('SELF'),
  unknown('UNKNOWN');

  const OrgScopeLevel(this.value);
  final String value;

  static OrgScopeLevel fromString(String? val) {
    if (val == null) return OrgScopeLevel.unknown;
    final upper = val.trim().toUpperCase();
    for (final level in OrgScopeLevel.values) {
      if (level.value == upper) return level;
    }
    return OrgScopeLevel.unknown;
  }
}

class OrgUnitInfo extends Equatable {
  const OrgUnitInfo({
    this.id,
    this.code,
    this.name,
  });

  final int? id;
  final String? code;
  final String? name;

  factory OrgUnitInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OrgUnitInfo();
    return OrgUnitInfo(
      id: asJsonInt(json['id']),
      code: asJsonString(json['code']),
      name: asJsonString(json['name']),
    );
  }

  @override
  List<Object?> get props => [id, code, name];
}

class OrgScope extends Equatable {
  const OrgScope({
    this.level = OrgScopeLevel.unknown,
    this.zone,
    this.division,
    this.depot,
  });

  final OrgScopeLevel level;
  final OrgUnitInfo? zone;
  final OrgUnitInfo? division;
  final OrgUnitInfo? depot;

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  factory OrgScope.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OrgScope();
    final zoneMap = _asMap(json['zone']);
    final divisionMap = _asMap(json['division']);
    final depotMap = _asMap(json['depot']);
    return OrgScope(
      level: OrgScopeLevel.fromString(asJsonString(json['level'])),
      zone: zoneMap == null && json['zone'] == null
          ? null
          : OrgUnitInfo.fromJson(zoneMap),
      division: divisionMap == null && json['division'] == null
          ? null
          : OrgUnitInfo.fromJson(divisionMap),
      depot: depotMap == null && json['depot'] == null
          ? null
          : OrgUnitInfo.fromJson(depotMap),
    );
  }

  @override
  List<Object?> get props => [level, zone, division, depot];
}
