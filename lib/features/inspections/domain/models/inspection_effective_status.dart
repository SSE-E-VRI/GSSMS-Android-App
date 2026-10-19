import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Computed aggregate status across all points + active Job Works.
/// Mirrors `InspectionService.compute_effective_status` (DOC-CMMS-INSP-001 §12)
/// and web `renderEffectiveStatusBadge` in InspectionListView/DetailView.
enum EffectiveInspectionStatus {
  open('OPEN', 'Open'),
  partiallyConverted('PARTIALLY_CONVERTED', 'Partially Converted'),
  assigned('ASSIGNED', 'Assigned'),
  inProgress('IN_PROGRESS', 'In Progress'),
  underSupervisorReview('UNDER_SUPERVISOR_REVIEW', 'Under Review'),
  reworkRequired('REWORK_REQUIRED', 'Rework Required'),
  replacementPendingApproval(
      'REPLACEMENT_PENDING_APPROVAL', 'Replacement Pending'),
  replacementApproved('REPLACEMENT_APPROVED', 'Replacement Approved'),
  closed('CLOSED', 'Closed'),
  unknown('UNKNOWN', 'Unknown');

  const EffectiveInspectionStatus(this.code, this.displayName);
  final String code;
  final String displayName;

  static EffectiveInspectionStatus fromString(String? code) {
    if (code == null) return EffectiveInspectionStatus.unknown;
    final upper = code.toUpperCase().trim();
    for (final s in EffectiveInspectionStatus.values) {
      if (s.code == upper) return s;
    }
    return EffectiveInspectionStatus.unknown;
  }
}

/// Single Job Work clubbed to an inspection (web `get_job_works`).
class InspectionJobWorkRef extends Equatable {
  const InspectionJobWorkRef({
    this.id,
    this.ticketNumber,
    this.title,
    this.status,
    this.priority,
    this.assignedToId,
    this.assignedToName,
    this.createdAt,
  });

  final int? id;
  final String? ticketNumber;
  final String? title;
  final String? status;
  final String? priority;
  final int? assignedToId;
  final String? assignedToName;
  final DateTime? createdAt;

  factory InspectionJobWorkRef.fromJson(Map<String, dynamic> json) {
    return InspectionJobWorkRef(
      id: asJsonInt(json['id']),
      ticketNumber: asJsonString(json['ticket_number']),
      title: asJsonString(json['title']),
      status: asJsonString(json['status']),
      priority: asJsonString(json['priority']),
      assignedToId: asJsonInt(json['assigned_to']),
      assignedToName: asJsonString(json['assigned_to_name']),
      createdAt: asJsonDateTime(json['created_at']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        ticketNumber,
        title,
        status,
        priority,
        assignedToId,
        assignedToName,
        createdAt,
      ];
}
