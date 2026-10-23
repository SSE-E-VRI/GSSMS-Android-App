import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/feedback.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/deficiency_severity_option.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';

/// "Technician Remarks" list of the verify screen. Lets an authorised
/// supervisor flag a remark as a deficiency (while TECH_COMPLETED) or un-flag
/// an OPEN one. Not shown for INSPECTION mode (caller decides).
class VerifyRemarksSection extends StatelessWidget {
  const VerifyRemarksSection({
    super.key,
    required this.rows,
    required this.assetOptions,
    required this.severities,
    required this.canFlag,
    required this.busy,
    required this.onFlag,
    required this.onUnflag,
  });

  final List<VerificationDeficiencyRow> rows;
  final List<RemarkAssetOption> assetOptions;
  final List<DeficiencySeverityOption> severities;

  /// Role gate AND status gate (Job Work is TECH_COMPLETED).
  final bool canFlag;
  final bool busy;

  /// Returns null on success, otherwise an error message.
  final Future<String?> Function(
    VerificationDeficiencyRow row, {
    String? assetUniqueId,
    int? severityId,
  }) onFlag;
  final Future<String?> Function(VerificationDeficiencyRow row) onUnflag;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final tokens = context.gssms;
    return SectionCard(
      key: const Key('verify_remarks_section'),
      title: 'Technician Remarks',
      icon: Icons.notes_outlined,
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
    final assetLabel = (row.asset ?? '').trim();
    return Column(
      key: Key('verify_remark_${row.rowKey}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(row.finding, style: textTheme.bodyMedium),
        if (row.isFlagged) ...[
          const SizedBox(height: GssmsSpacing.s4),
          Text(
            [
              'Asset: ${assetLabel.isEmpty ? 'Station-level' : assetLabel}',
              if ((row.severity ?? '').trim().isNotEmpty)
                'Severity: ${row.severity}',
            ].join('  |  '),
            style:
                textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: GssmsSpacing.s4),
          Row(
            children: [
              const StatusChip(
                label: 'Flagged as deficiency',
                tone: GssmsTone.warning,
                icon: Icons.flag_outlined,
              ),
              const Spacer(),
              if ((row.deficiencyStatus ?? '').toUpperCase() == 'OPEN' &&
                  canFlag)
                TextButton(
                  key: Key('unflag_remark_${row.rowKey}'),
                  onPressed: busy ? null : () => _unflag(context, row),
                  child: const Text('Un-flag'),
                ),
            ],
          ),
        ] else if (canFlag) ...[
          const SizedBox(height: GssmsSpacing.s4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: Key('flag_remark_${row.rowKey}'),
              onPressed: busy ? null : () => _flag(context, row),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Flag as deficiency'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _unflag(
    BuildContext context,
    VerificationDeficiencyRow row,
  ) async {
    final error = await onUnflag(row);
    if (error != null && context.mounted) {
      showGssmsSnackBar(context, error, tone: GssmsTone.danger);
    }
  }

  Future<void> _flag(BuildContext context, VerificationDeficiencyRow row) async {
    final result = await showDialog<_FlagChoice>(
      context: context,
      builder: (ctx) => _FlagDialog(
        assetOptions: assetOptions,
        severities: severities,
      ),
    );
    if (result == null || !context.mounted) return;
    final error = await onFlag(
      row,
      assetUniqueId: result.assetKey,
      severityId: result.severityId,
    );
    if (error != null && context.mounted) {
      showGssmsSnackBar(context, error, tone: GssmsTone.danger);
    }
  }
}

class _FlagChoice {
  const _FlagChoice(this.assetKey, this.severityId);

  final String? assetKey;
  final int? severityId;
}

class _FlagDialog extends StatefulWidget {
  const _FlagDialog({required this.assetOptions, required this.severities});

  final List<RemarkAssetOption> assetOptions;
  final List<DeficiencySeverityOption> severities;

  @override
  State<_FlagDialog> createState() => _FlagDialogState();
}

class _FlagDialogState extends State<_FlagDialog> {
  String? _assetKey;
  int? _severityId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Flag as deficiency'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String?>(
              key: const Key('flag_asset_dropdown'),
              isExpanded: true,
              initialValue: _assetKey,
              decoration: const InputDecoration(labelText: 'Asset'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Station-level (not asset-specific)'),
                ),
                for (final o in widget.assetOptions)
                  DropdownMenuItem<String?>(
                    value: o.key,
                    child: Text(o.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _assetKey = v),
            ),
            const SizedBox(height: GssmsSpacing.s12),
            DropdownButtonFormField<int?>(
              key: const Key('flag_severity_dropdown'),
              isExpanded: true,
              initialValue: _severityId,
              decoration: const InputDecoration(labelText: 'Severity'),
              items: [
                for (final s in widget.severities)
                  DropdownMenuItem<int?>(value: s.id, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _severityId = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('flag_confirm_button'),
          onPressed: () =>
              Navigator.of(context).pop(_FlagChoice(_assetKey, _severityId)),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
