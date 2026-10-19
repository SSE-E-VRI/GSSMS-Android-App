import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Skip-request reason codes accepted by the backend, with display labels.
/// `OTHER` requires remarks of at least 20 characters.
const kSkipReasonChoices = {
  'ASSET_UNAVAILABLE': 'Asset Unavailable',
  'LOCATION_INACCESSIBLE': 'Location Inaccessible',
  'SUPERSEDED_BY_NEXT_CYCLE': 'Superseded by Next Cycle',
  'OTHER': 'Other',
};

/// An alternative checklist template for a schedule
/// (`conversion-context` -> `template.alternatives[]`).
class ScheduleAlternative extends Equatable {
  const ScheduleAlternative({
    required this.id,
    this.name = '',
    this.scheduleType,
  });

  final int id;
  final String name;
  final String? scheduleType;

  factory ScheduleAlternative.fromJson(Map<String, dynamic> json) {
    return ScheduleAlternative(
      id: asJsonInt(json['id']) ?? 0,
      name: asJsonString(json['name']) ?? '',
      scheduleType: asJsonString(json['schedule_type']),
    );
  }

  @override
  List<Object?> get props => [id, name, scheduleType];
}

/// Response of a PM skip / checklist-change request (HTTP 201).
class ApprovalRequestSummary extends Equatable {
  const ApprovalRequestSummary({
    required this.id,
    this.requestType,
    this.status,
  });

  final int id;
  final String? requestType;
  final String? status;

  factory ApprovalRequestSummary.fromJson(Map<String, dynamic> json) {
    return ApprovalRequestSummary(
      id: asJsonInt(json['id']) ?? 0,
      requestType: asJsonString(json['request_type']),
      status: asJsonString(json['status']),
    );
  }

  @override
  List<Object?> get props => [id, requestType, status];
}
