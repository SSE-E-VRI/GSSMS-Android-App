import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Semantic operational-status chip (non-interactive metadata).
enum GssmsStatusTone { critical, high, medium, low, success }

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = GssmsStatusTone.low,
  });

  final String label;
  final GssmsStatusTone tone;

  Color get _color {
    switch (tone) {
      case GssmsStatusTone.critical:
        return AppTheme.statusCritical;
      case GssmsStatusTone.high:
        return AppTheme.statusHigh;
      case GssmsStatusTone.medium:
        return AppTheme.statusMedium;
      case GssmsStatusTone.low:
        return AppTheme.statusLow;
      case GssmsStatusTone.success:
        return AppTheme.statusSuccess;
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
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
