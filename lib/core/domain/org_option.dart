import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// A zone/division/depot/station row from the org-hierarchy endpoints
/// (`/api/v1/zones/`, `/api/v1/divisions/`, `/api/v1/depots/`,
/// `/api/v1/stations/`) — each serializer returns a plain `{id, name, ...}`
/// shape ([org/serializers.py](GSSMS/backend/org/serializers.py)), so one
/// model covers all four option lists used by [OrgScopeFilterBar].
class OrgOption extends Equatable {
  const OrgOption({required this.id, required this.name});

  final int id;
  final String name;

  factory OrgOption.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final name = asJsonString(json['name']) ?? 'Item #$id';
    return OrgOption(id: id, name: name);
  }

  @override
  List<Object?> get props => [id, name];
}
