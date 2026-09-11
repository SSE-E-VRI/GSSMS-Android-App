import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_status_style.dart';

/// OPEN waits for action (warning), ACTION_REQUIRED is escalated (danger),
/// CONVERTED has become a Job Work (info), CLOSED is done (success).
extension InspectionStatusStyle on InspectionStatus {
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

class InspectionStatusChip extends StatelessWidget {
  const InspectionStatusChip({super.key, required this.inspection});

  final Inspection inspection;

  @override
  Widget build(BuildContext context) {
    final status = inspection.status;
    return StatusChip(
      label: status.displayName,
      tone: status.tone,
      icon: status.icon,
      semanticPrefix: 'Status',
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
