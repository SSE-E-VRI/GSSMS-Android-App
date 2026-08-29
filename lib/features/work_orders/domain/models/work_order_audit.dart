import 'package:equatable/equatable.dart';

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
      eventId: json['event_id']?.toString() ?? '',
      eventType: json['event_type'] as String? ?? 'EVENT',
      fromState: json['from_state'] as String?,
      toState: json['to_state'] as String?,
      actor: json['actor'] as String?,
      actorRole: json['actor_role'] as String?,
      reason: json['reason'] as String? ?? json['remarks'] as String?,
      timestamp: ts is String && ts.isNotEmpty ? DateTime.tryParse(ts) : null,
      isReturn: json['is_return'] as bool? ?? false,
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
    final raw = json['events'] as List<dynamic>? ?? const [];
    return WorkOrderAudit(
      workOrderId: json['work_order_id'] as int? ?? 0,
      ticketNumber: json['ticket_number'] as String?,
      currentStatus: json['current_status'] as String?,
      events: raw
          .whereType<Map<String, dynamic>>()
          .map(WorkOrderAuditEvent.fromJson)
          .toList(),
      returnCount: json['return_count'] as int? ?? 0,
      currentlyReturned: json['currently_returned'] as bool? ?? false,
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
