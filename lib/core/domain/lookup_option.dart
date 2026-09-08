import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// One selectable value from a lookup-options domain (e.g.
/// `complaint_department`) — `GET /api/v1/lookup-options/<domain>/`. [key] is
/// what gets submitted, [label] is what the user sees; the same split as
/// web's `LookupSelect`.
class LookupOption extends Equatable {
  const LookupOption({required this.key, required this.label});

  final String key;
  final String label;

  factory LookupOption.fromJson(Map<String, dynamic> json) {
    final key = asJsonString(json['key']) ?? '';
    return LookupOption(key: key, label: asJsonString(json['label']) ?? key);
  }

  @override
  List<Object?> get props => [key, label];
}
