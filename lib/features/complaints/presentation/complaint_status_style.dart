import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_status_style.dart';

/// Web register semantics: OPEN is waiting for action (warning), CONVERTED
/// has become a Job Work (info), CLOSED is done (success).
extension ComplaintStatusStyle on ComplaintStatus {
  GssmsTone get tone {
    switch (this) {
      case ComplaintStatus.open:
        return GssmsTone.warning;
      case ComplaintStatus.converted:
        return GssmsTone.info;
      case ComplaintStatus.closed:
        return GssmsTone.success;
      case ComplaintStatus.unknown:
        return GssmsTone.neutral;
    }
  }

  IconData get icon {
    switch (this) {
      case ComplaintStatus.open:
        return Icons.mark_email_unread_outlined;
      case ComplaintStatus.converted:
        return Icons.build_circle_outlined;
      case ComplaintStatus.closed:
        return Icons.check_circle_outline;
      case ComplaintStatus.unknown:
        return Icons.help_outline;
    }
  }
}

class ComplaintStatusChip extends StatelessWidget {
  const ComplaintStatusChip({super.key, required this.complaint});

  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final status = complaint.status;
    return StatusChip(
      label: status.displayName,
      tone: status.tone,
      icon: status.icon,
      semanticPrefix: 'Status',
    );
  }
}

/// Linked Job Work progress for a converted complaint (Web "Completed /
/// Active / Job Work Linked" badges), or nothing when not converted.
class ComplaintJobWorkChip extends StatelessWidget {
  const ComplaintJobWorkChip({super.key, required this.complaint});

  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    if (!complaint.isConverted) return const SizedBox.shrink();
    final progress = linkedJobWorkProgress(complaint.workOrderStatus);
    return StatusChip(
      label: progress.label,
      tone: progress.tone,
      icon: progress.icon,
    );
  }
}
