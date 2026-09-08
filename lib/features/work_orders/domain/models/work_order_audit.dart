import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// One entry in a work order's history, from
/// `GET /maintenance/work-orders/{id}/audit/`.
class WorkOrderAuditEvent extends Equatable {
  const WorkOrderAuditEvent({
    required this.eventId,
    required this.eventType,
    this.fromState,
    this.toState,
    this.actor,
    this.actorRole,
    this.reason,
    this.timestamp,
    this.isReturn = false,
  });

  final String eventId;
  final String eventType;
  final String? fromState;
  final String? toState;
  final String? actor;
  final String? actorRole;
  final String? reason;
  final DateTime? timestamp;

  /// Server marks transitions that sent the work order back for rework.
  final bool isReturn;

  factory WorkOrderAuditEvent.fromJson(Map<String, dynamic> json) {
    final ts = json['timestamp'] ?? json['created_at'];
    return WorkOrderAuditEvent(
      eventId: asJsonString(json['event_id']) ?? '',
      eventType: asJsonString(json['event_type']) ?? 'EVENT',
      fromState: asJsonString(json['from_state']),
      toState: asJsonString(json['to_state']),
      actor: asJsonString(json['actor']),
      actorRole: asJsonString(json['actor_role']),
      reason: asJsonString(json['reason']) ?? asJsonString(json['remarks']),
      timestamp: ts is String && ts.isNotEmpty ? DateTime.tryParse(ts) : null,
      isReturn: asJsonBool(json['is_return']) ?? false,
    );
  }

  @override
  List<Object?> get props => [
        eventId,
        eventType,
        fromState,
        toState,
        actor,
        actorRole,
        reason,
        timestamp,
        isReturn,
      ];
}

class WorkOrderAudit extends Equatable {
  const WorkOrderAudit({
    required this.workOrderId,
    this.ticketNumber,
    this.currentStatus,
    this.events = const [],
    this.returnCount = 0,
    this.currentlyReturned = false,
  });

  final int workOrderId;
  final String? ticketNumber;
  final String? currentStatus;
  final List<WorkOrderAuditEvent> events;
  final int returnCount;
  final bool currentlyReturned;

  /// Newest first, which is how a field technician reads a history.
  List<WorkOrderAuditEvent> get eventsNewestFirst {
    final sorted = [...events];
    sorted.sort((a, b) {
      final at = a.timestamp;
      final bt = b.timestamp;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return sorted;
  }

  factory WorkOrderAudit.fromJson(Map<String, dynamic> json) {
    final raw = json['events'];
    final list = raw is List ? raw : const [];
    return WorkOrderAudit(
      workOrderId: asJsonInt(json['work_order_id'] ?? json['work_order']) ?? 0,
      ticketNumber: asJsonString(json['ticket_number']),
      currentStatus: asJsonString(json['current_status']),
      events: list
          .whereType<Map>()
          .map((e) => WorkOrderAuditEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      returnCount: asJsonInt(json['return_count']) ?? 0,
      currentlyReturned: asJsonBool(json['currently_returned']) ?? false,
    );
  }

  @override
  List<Object?> get props => [
        workOrderId,
        ticketNumber,
        currentStatus,
        events,
        returnCount,
        currentlyReturned,
      ];
}
