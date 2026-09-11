import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';

/// Critical / High / Medium / Low badge (non-interactive metadata).
///
/// Only for entities whose API actually carries a priority (Work Orders —
/// SSOT §13). Complaints and Inspections have no severity/priority field.
enum GssmsSeverity {
  critical(GssmsTone.danger, Icons.keyboard_double_arrow_up, 'Critical'),
  high(GssmsTone.accent, Icons.keyboard_arrow_up, 'High'),
  medium(GssmsTone.warning, Icons.drag_handle, 'Medium'),
  low(GssmsTone.neutral, Icons.keyboard_arrow_down, 'Low');

  const GssmsSeverity(this.tone, this.icon, this.defaultLabel);
  final GssmsTone tone;
  final IconData icon;
  final String defaultLabel;
}

class SeverityChip extends StatelessWidget {
  const SeverityChip({
    super.key,
    required this.severity,
    this.label,
  });

  final GssmsSeverity severity;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: label ?? severity.defaultLabel,
      tone: severity.tone,
      icon: severity.icon,
      semanticPrefix: 'Priority',
    );
  }
}
