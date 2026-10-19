import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/severity_chip.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';

/// RESOLVED/CLOSED green, everything else amber — same two-bucket logic as
/// web's `deficiencyStatusBadgeClass` (OPEN/ASSIGNED/IN_PROGRESS all read
/// amber there too, not a distinct colour per status).
Color deficiencyStatusColor(BuildContext context, DeficiencyStatus status) {
  switch (status) {
    case DeficiencyStatus.resolved:
    case DeficiencyStatus.closed:
      return context.gssms.success.foreground;
    case DeficiencyStatus.open:
    case DeficiencyStatus.assigned:
    case DeficiencyStatus.inProgress:
    case DeficiencyStatus.unknown:
      return context.gssms.warning.foreground;
  }
}

extension DeficiencyStatusStyle on DeficiencyStatus {
  GssmsTone get tone {
    switch (this) {
      case DeficiencyStatus.resolved:
      case DeficiencyStatus.closed:
        return GssmsTone.success;
      case DeficiencyStatus.open:
      case DeficiencyStatus.assigned:
      case DeficiencyStatus.inProgress:
      case DeficiencyStatus.unknown:
        return GssmsTone.warning;
    }
  }

  IconData get icon {
    switch (this) {
      case DeficiencyStatus.resolved:
      case DeficiencyStatus.closed:
        return Icons.check_circle_outline;
      case DeficiencyStatus.open:
        return Icons.error_outline;
      case DeficiencyStatus.assigned:
        return Icons.assignment_ind_outlined;
      case DeficiencyStatus.inProgress:
        return Icons.pending_outlined;
      case DeficiencyStatus.unknown:
        return Icons.help_outline;
    }
  }
}

class DeficiencyStatusChip extends StatelessWidget {
  const DeficiencyStatusChip({super.key, required this.status});

  final DeficiencyStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: status.displayName,
      tone: status.tone,
      icon: status.icon,
      semanticPrefix: 'Deficiency status',
    );
  }
}

/// Parses raw deficiency severity label (e.g. 'CRITICAL', 'HIGH') into
/// [GssmsSeverity] enum.
GssmsSeverity? parseDeficiencySeverity(String? label) {
  if (label == null || label.trim().isEmpty) return null;
  final l = label.trim().toUpperCase();
  if (l.contains('CRIT')) return GssmsSeverity.critical;
  if (l.contains('HIGH')) return GssmsSeverity.high;
  if (l.contains('MED')) return GssmsSeverity.medium;
  if (l.contains('LOW')) return GssmsSeverity.low;
  return null;
}
