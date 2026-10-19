import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';

/// Heading of one asset group in the checklist, with the check-out switch.
///
/// Every group starts unchecked; the technician checks it out to begin its
/// checklist (web `MaintenanceRecordForm.jsx`).
class ChecklistGroupHeader extends StatelessWidget {
  const ChecklistGroupHeader({
    super.key,
    required this.group,
    required this.canCheckOut,
    required this.canUncheck,
    required this.saving,
    required this.onToggle,
    this.isPastTechCompleted = false,
  });

  final ChecklistAssetGroup group;
  final bool canCheckOut;
  final bool canUncheck;
  final bool saving;
  final bool isPastTechCompleted;
  final ValueChanged<bool> onToggle;

  bool get _disabled {
    if (saving || isPastTechCompleted || !canCheckOut) return true;
    if (group.checkedOut && !canUncheck) return true;
    if (group.supervisorExcluded && !canUncheck) return true;
    return false;
  }

  String get _switchLabel {
    if (!group.checkedOut) return 'Check out this asset group';
    switch (group.checkoutSource) {
      case 'SUPERVISOR':
        return 'Checked out by supervisor';
      case 'TECHNICIAN':
        return 'Checked out by technician';
      default:
        return 'Checked out';
    }
  }

  String get _notCheckedOutText {
    if (isPastTechCompleted) {
      return 'This asset group was not checked out during this maintenance';
    }
    if (group.supervisorExcluded) {
      return 'Skipped by the supervisor before START.';
    }
    if (group.applicability == 'OPTIONAL_ABSENT') {
      return 'Not recorded at this station in the asset register — check out '
          'this asset group if it is present';
    }
    return 'Not yet checked out — check out this asset group to begin its '
        'checklist';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.gssms;
    final unique = group.assetUniqueId?.trim();

    return Container(
      key: Key('group_header_${group.key}'),
      padding: const EdgeInsets.symmetric(
        horizontal: GssmsSpacing.s12,
        vertical: GssmsSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceInset,
        borderRadius: BorderRadius.circular(GssmsRadius.r8),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (unique == null || unique.isEmpty)
                      ? group.displayTitle
                      : '${group.displayTitle} ($unique)',
                  style: textTheme.titleMedium,
                ),
              ),
              if (saving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          MergeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _switchLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: group.checkedOut
                          ? tokens.success.foreground
                          : tokens.textSecondary,
                    ),
                  ),
                ),
                Switch(
                  key: Key('group_checkout_${group.key}'),
                  value: group.checkedOut,
                  onChanged: _disabled ? null : onToggle,
                ),
              ],
            ),
          ),
          if (!group.checkedOut)
            Padding(
              padding: const EdgeInsets.only(bottom: GssmsSpacing.s4),
              child: Text(
                _notCheckedOutText,
                key: Key('group_unchecked_text_${group.key}'),
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
