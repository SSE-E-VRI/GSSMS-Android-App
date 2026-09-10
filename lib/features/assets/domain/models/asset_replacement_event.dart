import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// One event from `GET /api/v1/assets/{id}/replacement-history/`
/// (`get_asset_replacement_history`) — a unified projection across three
/// backend sources (`ASSET_REPLACEMENT`/`SET_COMPONENT_REPLACEMENT`/
/// `INSTALLED_COMPONENT_REPLACEMENT`), all sharing this same event shape.
class AssetReplacementEvent extends Equatable {
  const AssetReplacementEvent({
    required this.sourceType,
    this.date,
    this.oldIdentity,
    this.newIdentity,
    this.reason,
    this.actor,
  });

  final String sourceType;
  final DateTime? date;

  /// Free-form identity map (make/model/serial_number, or name/unique_id,
  /// depending on [sourceType]) — rendered generically rather than assuming
  /// one fixed key set, since the three source types don't share identical
  /// identity fields.
  final Map<String, dynamic>? oldIdentity;
  final Map<String, dynamic>? newIdentity;
  final String? reason;
  final String? actor;

  String get displayLabel {
    switch (sourceType) {
      case 'ASSET_REPLACEMENT':
        return 'Asset Replaced';
      case 'SET_COMPONENT_REPLACEMENT':
        return 'Component Replaced (Set)';
      case 'INSTALLED_COMPONENT_REPLACEMENT':
        return 'Component Replaced';
      default:
        return sourceType;
    }
  }

  static String? _identitySummary(Map<String, dynamic>? identity) {
    if (identity == null) return null;
    final parts = [
      identity['name'],
      identity['unique_id'],
      identity['make'],
      identity['model'],
      identity['serial_number'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' ');
  }

  String? get oldIdentitySummary => _identitySummary(oldIdentity);
  String? get newIdentitySummary => _identitySummary(newIdentity);

  factory AssetReplacementEvent.fromJson(Map<String, dynamic> json) {
    return AssetReplacementEvent(
      sourceType: asJsonString(json['source_type']) ?? 'REPLACEMENT',
      date: asJsonString(json['date']) != null
          ? DateTime.tryParse(json['date'].toString())
          : null,
      oldIdentity: json['old_identity'] is Map
          ? Map<String, dynamic>.from(json['old_identity'] as Map)
          : null,
      newIdentity: json['new_identity'] is Map
          ? Map<String, dynamic>.from(json['new_identity'] as Map)
          : null,
      reason: asJsonString(json['reason']),
      actor: asJsonString(json['actor']),
    );
  }

  @override
  List<Object?> get props =>
      [sourceType, date, oldIdentity, newIdentity, reason, actor];
}
