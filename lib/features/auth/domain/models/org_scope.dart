import 'package:equatable/equatable.dart';

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
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}'),
      code: json['code'] as String?,
      name: json['name'] as String?,
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

  factory OrgScope.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OrgScope();
    return OrgScope(
      level: OrgScopeLevel.fromString(json['level'] as String?),
      zone: json['zone'] != null ? OrgUnitInfo.fromJson(json['zone'] as Map<String, dynamic>?) : null,
      division: json['division'] != null ? OrgUnitInfo.fromJson(json['division'] as Map<String, dynamic>?) : null,
      depot: json['depot'] != null ? OrgUnitInfo.fromJson(json['depot'] as Map<String, dynamic>?) : null,
    );
  }

  @override
  List<Object?> get props => [level, zone, division, depot];
}
