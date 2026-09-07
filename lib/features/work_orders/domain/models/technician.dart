import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// A depot-scoped maintenance staff member from `GET /api/v1/users/?role=MAINTENANCE_STAFF`.
class Technician extends Equatable {
  const Technician({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;

  factory Technician.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final parsedId = id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0;

    final fullName = asJsonString(json['full_name']);
    final name = asJsonString(json['name']);
    final first = asJsonString(json['first_name'])?.trim() ?? '';
    final last = asJsonString(json['last_name'])?.trim() ?? '';
    final combined = [first, last].where((p) => p.isNotEmpty).join(' ');
    final username = asJsonString(json['username']);

    final display = [
      if (fullName != null && fullName.trim().isNotEmpty) fullName.trim(),
      if (name != null && name.trim().isNotEmpty) name.trim(),
      if (combined.isNotEmpty) combined,
      if (username != null && username.trim().isNotEmpty) username.trim(),
    ].firstWhere((s) => s.isNotEmpty, orElse: () => 'User #$parsedId');

    return Technician(id: parsedId, name: display);
  }

  @override
  List<Object?> get props => [id, name];
}
