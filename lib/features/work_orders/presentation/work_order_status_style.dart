import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/severity_chip.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

/// Display semantics for Work Order (Job Work) statuses.
///
/// Tones follow the Web Job Work register (`JobWorkListView.getStatusColor`):
/// NEW needs action (danger), ASSIGNED is waiting to start (warning),
/// REWORK_REQUIRED is a return (danger), TECH_COMPLETED awaits sign-off
/// (info), VERIFIED is done (success), CLOSED/ON_HOLD/CANCELLED are inactive
/// (neutral). IN_PROGRESS uses the GSSMS orange accent — the colour the Home
/// "In Progress" banner already uses — so it stays distinguishable from
/// TECH_COMPLETED's blue in a mixed list. The API value is never changed.
extension WorkOrderStatusStyle on WorkOrderStatus {
  GssmsTone get tone {
    switch (this) {
      case WorkOrderStatus.newOrder:
      case WorkOrderStatus.reworkRequired:
        return GssmsTone.danger;
      case WorkOrderStatus.assigned:
        return GssmsTone.warning;
      case WorkOrderStatus.inProgress:
        return GssmsTone.accent;
      case WorkOrderStatus.techCompleted:
        return GssmsTone.info;
      case WorkOrderStatus.verified:
        return GssmsTone.success;
      case WorkOrderStatus.closed:
      case WorkOrderStatus.onHold:
      case WorkOrderStatus.cancelled:
      case WorkOrderStatus.unknown:
        return GssmsTone.neutral;
    }
  }

  IconData get icon {
    switch (this) {
      case WorkOrderStatus.newOrder:
        return Icons.fiber_new_outlined;
      case WorkOrderStatus.assigned:
        return Icons.assignment_ind_outlined;
      case WorkOrderStatus.inProgress:
        return Icons.construction_outlined;
      case WorkOrderStatus.techCompleted:
        return Icons.pending_actions_outlined;
      case WorkOrderStatus.verified:
        return Icons.verified_outlined;
      case WorkOrderStatus.reworkRequired:
        return Icons.replay;
      case WorkOrderStatus.onHold:
        return Icons.pause_circle_outline;
      case WorkOrderStatus.closed:
        return Icons.lock_outline;
      case WorkOrderStatus.cancelled:
        return Icons.cancel_outlined;
      case WorkOrderStatus.unknown:
        return Icons.help_outline;
    }
  }
}

extension WorkOrderPriorityStyle on WorkOrderPriority {
  GssmsSeverity get severity {
    switch (this) {
      case WorkOrderPriority.critical:
        return GssmsSeverity.critical;
      case WorkOrderPriority.high:
        return GssmsSeverity.high;
      case WorkOrderPriority.medium:
        return GssmsSeverity.medium;
      case WorkOrderPriority.low:
        return GssmsSeverity.low;
    }
  }
}

class WorkOrderStatusChip extends StatelessWidget {
  const WorkOrderStatusChip({super.key, required this.status, this.filled = false});

  final WorkOrderStatus status;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: status.displayName,
      tone: status.tone,
      icon: status.icon,
      filled: filled,
      semanticPrefix: 'Status',
    );
  }
}

class WorkOrderPriorityChip extends StatelessWidget {
  const WorkOrderPriorityChip({super.key, required this.priority});

  final WorkOrderPriority priority;

  @override
  Widget build(BuildContext context) {
    return SeverityChip(
      severity: priority.severity,
      label: priority.displayName,
    );
  }
}

/// Plain-language progress of the Job Work linked to a converted Complaint or
/// Inspection, from the serializer's `wo_status` — the same buckets the Web
/// Complaint/Inspection registers show (Completed / In Progress / On Hold /
/// Rework Required / Cancelled / Closed).
({String label, GssmsTone tone, IconData icon}) linkedJobWorkProgress(
    String? woStatus) {
  switch (WorkOrderStatus.fromString(woStatus)) {
    case WorkOrderStatus.techCompleted:
    case WorkOrderStatus.verified:
      return (
        label: 'Job Work Completed',
        tone: GssmsTone.success,
        icon: Icons.check_circle_outline
      );
    case WorkOrderStatus.closed:
      return (label: 'Job Work Closed', tone: GssmsTone.neutral, icon: Icons.lock_outline);
    case WorkOrderStatus.cancelled:
      return (
        label: 'Job Work Cancelled',
        tone: GssmsTone.danger,
        icon: Icons.cancel_outlined
      );
    case WorkOrderStatus.onHold:
      return (
        label: 'Job Work On Hold',
        tone: GssmsTone.warning,
        icon: Icons.pause_circle_outline
      );
    case WorkOrderStatus.reworkRequired:
      return (label: 'Rework Required', tone: GssmsTone.warning, icon: Icons.replay);
    case WorkOrderStatus.newOrder:
    case WorkOrderStatus.assigned:
    case WorkOrderStatus.inProgress:
      return (
        label: 'Job Work In Progress',
        tone: GssmsTone.info,
        icon: Icons.construction_outlined
      );
    case WorkOrderStatus.unknown:
      return (label: 'Job Work Linked', tone: GssmsTone.info, icon: Icons.link);
  }
}
