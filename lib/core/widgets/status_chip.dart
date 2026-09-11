import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Compact, non-interactive status/priority badge.
///
/// Meaning is carried by the [icon] and [label]; the tone colour is
/// supplementary (never colour alone). Colours come from [GssmsColors], so the
/// chip reads correctly in light and dark themes.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = GssmsTone.neutral,
    this.icon,
    this.filled = false,
    this.semanticPrefix,
  });

  final String label;
  final GssmsTone tone;
  final IconData? icon;

  /// Solid background for the one badge that must dominate (e.g. the detail
  /// header's current status). Tinted otherwise.
  final bool filled;

  /// Spoken before the label, e.g. `'Status'` → "Status: In Progress".
  final String? semanticPrefix;

  @override
  Widget build(BuildContext context) {
    final palette = context.gssms.tone(tone);
    final fg = filled ? palette.onSolid : palette.foreground;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        );

    return Semantics(
      label: semanticPrefix == null ? label : '$semanticPrefix: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: GssmsSpacing.s8,
          vertical: GssmsSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: filled ? palette.solid : palette.background,
          borderRadius: BorderRadius.circular(GssmsRadius.r12),
          border: Border.all(color: filled ? palette.solid : palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: GssmsSpacing.s4),
            ],
            Flexible(
              child: Text(
                label,
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
