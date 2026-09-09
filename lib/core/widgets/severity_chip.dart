import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Critical / High / Medium / Low severity badge (non-interactive metadata).
enum GssmsSeverity { critical, high, medium, low }

class SeverityChip extends StatelessWidget {
  const SeverityChip({
    super.key,
    required this.severity,
    this.label,
  });

  final GssmsSeverity severity;
  final String? label;

  Color get _color {
    switch (severity) {
      case GssmsSeverity.critical:
        return AppTheme.statusCritical;
      case GssmsSeverity.high:
        return AppTheme.statusHigh;
      case GssmsSeverity.medium:
        return AppTheme.statusMedium;
      case GssmsSeverity.low:
        return AppTheme.statusLow;
    }
  }

  String get _defaultLabel {
    switch (severity) {
      case GssmsSeverity.critical:
        return 'Critical';
      case GssmsSeverity.high:
        return 'High';
      case GssmsSeverity.medium:
        return 'Medium';
      case GssmsSeverity.low:
        return 'Low';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GssmsSpacing.s8,
        vertical: GssmsSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(GssmsRadius.r12),
        border: Border.all(color: color),
      ),
      child: Text(
        label ?? _defaultLabel,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
