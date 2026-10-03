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
      semanticPrefix: 'Record status',
    );
  }
}

/// Live aggregate status (linked Job Work status once converted) — mirrors
/// web's `effective_status` alongside `record_status`. Shown only when it
/// carries information beyond the record chip.
class ComplaintEffectiveChip extends StatelessWidget {
  const ComplaintEffectiveChip({super.key, required this.complaint});

  final Complaint complaint;

  static String pretty(String code) {
    final words = code.trim().replaceAll('_', ' ').toLowerCase().split(' ');
    return words
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final effective = complaint.effectiveStatus?.trim();
    if (effective == null || effective.isEmpty) {
      return const SizedBox.shrink();
    }
    if (effective.toUpperCase() == complaint.status.code) {
      return const SizedBox.shrink();
    }
    return StatusChip(
      label: pretty(effective),
      tone: GssmsTone.info,
      icon: Icons.sync_outlined,
      semanticPrefix: 'Effective status',
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
