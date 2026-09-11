import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Titled group of related fields on a detail screen.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    required this.children,
    this.padding = const EdgeInsets.all(GssmsSpacing.s16),
  });

  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: GssmsSize.iconMd, color: tokens.textSecondary),
                    const SizedBox(width: GssmsSpacing.s8),
                  ],
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title!,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: GssmsSpacing.s8),
              Divider(color: tokens.border, height: 1),
              const SizedBox(height: GssmsSpacing.s8),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Label/value row. Stacks vertically when the value is long or the text is
/// scaled up, so neither side gets squeezed into an unreadable column.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
    this.emptyText = '—',
  });

  final String label;
  final String? value;
  final TextStyle? valueStyle;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final shown = (value == null || value!.trim().isEmpty) ? emptyText : value!;
    final labelText = Text(
      label,
      style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
    );
    final valueText = Text(
      shown,
      style: (valueStyle ?? textTheme.bodyMedium)
          ?.copyWith(fontWeight: FontWeight.w500),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GssmsSpacing.s6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final stacked = constraints.maxWidth < 320 || scale > 1.25;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: GssmsSpacing.s2), valueText],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: constraints.maxWidth * 0.38, child: labelText),
              const SizedBox(width: GssmsSpacing.s8),
              Expanded(child: valueText),
            ],
          );
        },
      ),
    );
  }
}

/// Recessed block for long free text (descriptions, notes, remarks).
class TextWell extends StatelessWidget {
  const TextWell({super.key, required this.text, this.placeholder = 'None provided.'});

  final String? text;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final empty = text == null || text!.trim().isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(GssmsSpacing.s12),
      decoration: BoxDecoration(
        color: tokens.surfaceInset,
        borderRadius: BorderRadius.circular(GssmsRadius.r8),
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        empty ? placeholder : text!,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: empty ? tokens.textTertiary : tokens.textPrimary,
              fontStyle: empty ? FontStyle.italic : FontStyle.normal,
            ),
      ),
    );
  }
}
