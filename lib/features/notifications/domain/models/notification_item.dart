import 'package:equatable/equatable.dart';

import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

enum NotificationType {
  assignment('ASSIGNMENT', 'Work Order Assigned'),
  rework('REWORK', 'Rework Required'),
  overdue('OVERDUE', 'Overdue Work'),
  slaBreach('SLA', 'SLA At Risk'),
  complaint('COMPLAINT', 'New Complaint Logged'),
  schedule('SCHEDULE', 'Upcoming Schedule'),
  alert('ALERT', 'System Alert');

  const NotificationType(this.code, this.displayName);
  final String code;
  final String displayName;
}

/// An actionable item derived from operational data.
///
/// GSSMS has no notification service, so rather than showing invented alerts
/// the app derives these from work orders the server actually returned:
/// assignments, returns for rework, overdue work and SLA risk — the same set
/// the SSOT asks mobile to surface.
class NotificationItem extends Equatable {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.targetEntityId,
    this.targetEntityType,
  });

  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;
  final int? targetEntityId;
  final String? targetEntityType;

  NotificationItem copyWith({bool? isRead}) {
    return NotificationItem(
      id: id,
      title: title,
      message: message,
      type: type,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      targetEntityId: targetEntityId,
      targetEntityType: targetEntityType,
    );
  }

  /// Derives the alerts a work order warrants, most urgent first.
  ///
  /// A work order can raise more than one (an overdue rework, say), and each
  /// gets a stable id so its read state survives a refresh.
  static List<NotificationItem> fromWorkOrder(WorkOrder wo, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final items = <NotificationItem>[];
    final when = wo.createdAt ?? wo.dueDate ?? reference;

    void add(NotificationType type, String title, String message, DateTime at) {
      items.add(NotificationItem(
        id: '${type.code}_${wo.id}',
        title: title,
        message: message,
        type: type,
        timestamp: at,
        targetEntityId: wo.id,
        targetEntityType: 'WORK_ORDER',
      ));
    }

    if (wo.status == WorkOrderStatus.reworkRequired) {
      add(
        NotificationType.rework,
        'Rework Required',
        '${wo.displayReference} — ${wo.displayTitle} was returned for rework.',
        wo.latestEventSummary?.createdAt ?? when,
      );
    } else if (wo.status == WorkOrderStatus.assigned) {
      add(
        NotificationType.assignment,
        'Work Order Assigned',
        '${wo.displayReference} — ${wo.displayTitle}'
            '${wo.stationName != null ? ' at ${wo.stationName}' : ''}.',
        when,
      );
    }

    final due = wo.dueDate;
    if (due != null && due.isBefore(reference) && _isOpen(wo.status)) {
      add(
        NotificationType.overdue,
        'Overdue Work Order',
        '${wo.displayReference} was due on ${_formatDate(due)} and is still ${wo.status.displayName}.',
        due,
      );
    }

    if (wo.isSlaAtRisk && _isOpen(wo.status)) {
      add(
        NotificationType.slaBreach,
        'SLA ${wo.slaStatus}',
        '${wo.displayReference} — ${wo.displayTitle} needs attention.',
        when,
      );
    }

    return items;
  }

  static bool _isOpen(WorkOrderStatus status) {
    return status != WorkOrderStatus.closed &&
        status != WorkOrderStatus.cancelled &&
        status != WorkOrderStatus.verified;
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  List<Object?> get props => [
        id,
        title,
        message,
        type,
        timestamp,
        isRead,
        targetEntityId,
        targetEntityType,
      ];
}
