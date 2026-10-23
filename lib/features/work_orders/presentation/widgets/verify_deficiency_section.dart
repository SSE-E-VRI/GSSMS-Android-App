import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/feedback.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/deficiency_severity_option.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';

/// "Deficiency Severity Assessment": one row per checklist deficiency (plus
/// flagged remark deficiencies) with a severity dropdown for roles allowed to
/// triage. Web: JobWorkListView.jsx:3010-3058.
class VerifyDeficiencySection extends StatelessWidget {
  const VerifyDeficiencySection({
    super.key,
    required this.rows,
    required this.severities,
    required this.canTriage,
    required this.busy,
    required this.onSeverityChanged,
  });

  final List<VerificationDeficiencyRow> rows;
  final List<DeficiencySeverityOption> severities;
  final bool canTriage;
  final bool busy;

  /// Returns null on success, otherwise an error message.
  final Future<String?> Function(VerificationDeficiencyRow row, int severityId)
      onSeverityChanged;

  static const _lockedStatuses = {'VERIFIED', 'CLOSED'};

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final tokens = context.gssms;
    return SectionCard(
      key: const Key('verify_deficiency_section'),
      title: 'Deficiency Severity Assessment',
      icon: Icons.warning_amber_outlined,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(color: tokens.border, height: GssmsSpacing.s16),
          _row(context, rows[i]),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, VerificationDeficiencyRow row) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final heading = [row.asset ?? '', row.checkpoint]
        .where((s) => s.trim().isNotEmpty)
        .join(' - ');
    final status = (row.deficiencyStatus ?? '').toUpperCase();
    final canChange = canTriage &&
        row.deficiencyId != null &&
        row.deficiencyVersion != null &&
        !_lockedStatuses.contains(status) &&
        severities.isNotEmpty;

    final Widget severityWidget;
    if (row.willRaiseOnVerification) {
      severityWidget = const Align(
        alignment: Alignment.centerLeft,
        child: StatusChip(
          label: 'Will be raised on verification',
          tone: GssmsTone.warning,
          icon: Icons.schedule_outlined,
        ),
      );
    } else if (row.deficiencyId == null) {
      severityWidget = const Align(
        alignment: Alignment.centerLeft,
        child: StatusChip(label: 'Pending review', tone: GssmsTone.neutral),
      );
    } else if (canChange) {
      final selected =
          severities.any((s) => s.id == row.severityId) ? row.severityId : null;
      severityWidget = DropdownButtonFormField<int>(
        key: Key('severity_dropdown_${row.rowKey}'),
        isExpanded: true,
        initialValue: selected,
        decoration: const InputDecoration(labelText: 'Severity'),
        items: [
          for (final s in severities)
            DropdownMenuItem<int>(value: s.id, child: Text(s.label)),
        ],
        onChanged: busy
            ? null
            : (v) async {
                if (v == null || v == row.severityId) return;
                final error = await onSeverityChanged(row, v);
                if (error != null && context.mounted) {
                  showGssmsSnackBar(context, error, tone: GssmsTone.danger);
                }
              },
      );
    } else {
      severityWidget = Text(
        'Severity: ${(row.severity ?? '').trim().isEmpty ? '—' : row.severity}',
        key: Key('severity_text_${row.rowKey}'),
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      );
    }

    return Column(
      key: Key('verify_deficiency_${row.rowKey}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heading.isNotEmpty) Text(heading, style: textTheme.titleSmall),
        if (row.finding.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: GssmsSpacing.s4),
            child: Text(row.finding, style: textTheme.bodyMedium),
          ),
        if (row.action.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: GssmsSpacing.s2),
            child: Text(
              'Action: ${row.action}',
              style:
                  textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
          ),
        const SizedBox(height: GssmsSpacing.s8),
        severityWidget,
      ],
    );
  }
}
