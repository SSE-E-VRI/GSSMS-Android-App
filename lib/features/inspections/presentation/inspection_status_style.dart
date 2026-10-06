import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_effective_status.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_point.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_status_style.dart';

/// OPEN waits for action (warning), ACTION_REQUIRED is escalated (danger),
/// CONVERTED has become a Job Work (info), CLOSED is done (success).
extension InspectionStatusStyle on InspectionStatus {
  String get webLabel {
    switch (this) {
      case InspectionStatus.open:
        return 'Open';
      case InspectionStatus.actionRequired:
        return 'Action Required';
      case InspectionStatus.converted:
        return 'Converted';
      case InspectionStatus.closed:
        return 'Closed';
      case InspectionStatus.unknown:
        return 'Unknown';
    }
  }

  GssmsTone get tone {
    switch (this) {
      case InspectionStatus.open:
        return GssmsTone.warning;
      case InspectionStatus.actionRequired:
        return GssmsTone.danger;
      case InspectionStatus.converted:
        return GssmsTone.info;
      case InspectionStatus.closed:
        return GssmsTone.success;
      case InspectionStatus.unknown:
        return GssmsTone.neutral;
    }
  }

  IconData get icon {
    switch (this) {
      case InspectionStatus.open:
        return Icons.fact_check_outlined;
      case InspectionStatus.actionRequired:
        return Icons.report_gmailerrorred_outlined;
      case InspectionStatus.converted:
        return Icons.build_circle_outlined;
      case InspectionStatus.closed:
        return Icons.check_circle_outline;
      case InspectionStatus.unknown:
        return Icons.help_outline;
    }
  }
}

/// Web `renderEffectiveStatusBadge` tones.
extension EffectiveInspectionStatusStyle on EffectiveInspectionStatus {
  GssmsTone get tone {
    switch (this) {
      case EffectiveInspectionStatus.open:
        return GssmsTone.info;
      case EffectiveInspectionStatus.partiallyConverted:
        return GssmsTone.warning;
      case EffectiveInspectionStatus.assigned:
        return GssmsTone.info;
      case EffectiveInspectionStatus.inProgress:
        return GssmsTone.info;
      case EffectiveInspectionStatus.underSupervisorReview:
        return GssmsTone.warning;
      case EffectiveInspectionStatus.reworkRequired:
        return GssmsTone.danger;
      case EffectiveInspectionStatus.replacementPendingApproval:
        return GssmsTone.warning;
      case EffectiveInspectionStatus.replacementApproved:
        return GssmsTone.success;
      case EffectiveInspectionStatus.closed:
        return GssmsTone.success;
      case EffectiveInspectionStatus.unknown:
        return GssmsTone.neutral;
    }
  }

  IconData get icon {
    switch (this) {
      case EffectiveInspectionStatus.open:
        return Icons.fact_check_outlined;
      case EffectiveInspectionStatus.partiallyConverted:
        return Icons.timelapse_outlined;
      case EffectiveInspectionStatus.assigned:
        return Icons.assignment_ind_outlined;
      case EffectiveInspectionStatus.inProgress:
        return Icons.construction_outlined;
      case EffectiveInspectionStatus.underSupervisorReview:
        return Icons.pending_actions_outlined;
      case EffectiveInspectionStatus.reworkRequired:
        return Icons.replay;
      case EffectiveInspectionStatus.replacementPendingApproval:
        return Icons.report_gmailerrorred_outlined;
      case EffectiveInspectionStatus.replacementApproved:
        return Icons.verified_outlined;
      case EffectiveInspectionStatus.closed:
        return Icons.check_circle_outline;
      case EffectiveInspectionStatus.unknown:
        return Icons.help_outline;
    }
  }
}

/// Web `renderDispositionBadge` tones.
extension PointDispositionStyle on PointDispositionStatus {
  GssmsTone get tone {
    switch (this) {
      case PointDispositionStatus.unassigned:
        return GssmsTone.neutral;
      case PointDispositionStatus.assigned:
        return GssmsTone.info;
      case PointDispositionStatus.resolved:
        return GssmsTone.success;
      case PointDispositionStatus.disposed:
        return GssmsTone.neutral;
      case PointDispositionStatus.unresolved:
        return GssmsTone.danger;
      case PointDispositionStatus.approvedForJw2:
        return GssmsTone.warning;
      case PointDispositionStatus.unknown:
        return GssmsTone.neutral;
    }
  }

  IconData get icon {
    switch (this) {
      case PointDispositionStatus.unassigned:
        return Icons.radio_button_unchecked;
      case PointDispositionStatus.assigned:
        return Icons.assignment_ind_outlined;
      case PointDispositionStatus.resolved:
        return Icons.check_circle_outline;
      case PointDispositionStatus.disposed:
        return Icons.archive_outlined;
      case PointDispositionStatus.unresolved:
        return Icons.error_outline;
      case PointDispositionStatus.approvedForJw2:
        return Icons.verified_outlined;
      case PointDispositionStatus.unknown:
        return Icons.help_outline;
    }
  }
}

extension InspectionPointPriorityStyle on InspectionPointPriority {
  GssmsTone get tone {
    switch (this) {
      case InspectionPointPriority.high:
        return GssmsTone.danger;
      case InspectionPointPriority.medium:
        return GssmsTone.warning;
      case InspectionPointPriority.low:
        return GssmsTone.info;
      case InspectionPointPriority.unknown:
        return GssmsTone.neutral;
    }
  }

  IconData get icon {
    switch (this) {
      case InspectionPointPriority.high:
        return Icons.priority_high;
      case InspectionPointPriority.medium:
        return Icons.signal_cellular_alt_2_bar_outlined;
      case InspectionPointPriority.low:
        return Icons.low_priority;
      case InspectionPointPriority.unknown:
        return Icons.help_outline;
    }
  }
}

class InspectionStatusChip extends StatelessWidget {
  const InspectionStatusChip({super.key, required this.inspection});

  final Inspection inspection;

  @override
  Widget build(BuildContext context) {
    final status = inspection.status;
    return StatusChip(
      label: status.webLabel,
      tone: status.tone,
      icon: status.icon,
      semanticPrefix: 'Record status',
    );
  }
}

class InspectionEffectiveStatusChip extends StatelessWidget {
  const InspectionEffectiveStatusChip({super.key, required this.inspection});

  final Inspection inspection;

  @override
  Widget build(BuildContext context) {
    final status = inspection.effectiveStatus;
    if (status == EffectiveInspectionStatus.unknown) {
      return const SizedBox.shrink();
    }
    return StatusChip(
      label: status.displayName,
      tone: status.tone,
      icon: status.icon,
      semanticPrefix: 'Effective status',
    );
  }
}

class InspectionPointsBadge extends StatelessWidget {
  const InspectionPointsBadge({super.key, required this.inspection});

  final Inspection inspection;

  @override
  Widget build(BuildContext context) {
    final count = inspection.pointsCount;
    return StatusChip(
      label: '$count ${count == 1 ? 'Point' : 'Points'}',
      tone: GssmsTone.neutral,
      icon: Icons.pin_drop_outlined,
      semanticPrefix: 'Points',
    );
  }
}

class PointDispositionChip extends StatelessWidget {
  const PointDispositionChip({super.key, required this.status});

  final PointDispositionStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: status.displayName,
      tone: status.tone,
      icon: status.icon,
      semanticPrefix: 'Point',
    );
  }
}

class PointPriorityChip extends StatelessWidget {
  const PointPriorityChip({super.key, required this.priority});

  final InspectionPointPriority priority;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: priority.displayName,
      tone: priority.tone,
      icon: priority.icon,
      semanticPrefix: 'Priority',
    );
  }
}

class InspectionJobWorkChip extends StatelessWidget {
  const InspectionJobWorkChip({super.key, required this.inspection});

  final Inspection inspection;

  @override
  Widget build(BuildContext context) {
    if (!inspection.isConverted) return const SizedBox.shrink();
    final progress = linkedJobWorkProgress(inspection.workOrderStatus);
    return StatusChip(
      label: progress.label,
      tone: progress.tone,
      icon: progress.icon,
    );
  }
}
