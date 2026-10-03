import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';

/// "Asset Group Checkout" list of the verify screen. A checked-out group can
/// be un-checked by roles holding `maintenance.group_uncheckout` while the
/// Job Work is TECH_COMPLETED, which returns it to the technician.
class VerifyAssetGroupsSection extends StatelessWidget {
  const VerifyAssetGroupsSection({
    super.key,
    required this.groups,
    required this.canUncheck,
    required this.busy,
    required this.onUncheck,
  });

  final List<VerificationAssetGroup> groups;

  /// Permission + TECH_COMPLETED + record present.
  final bool canUncheck;
  final bool busy;
  final void Function(VerificationAssetGroup group) onUncheck;

  static String checkoutLabel(VerificationAssetGroup g) {
    if (!g.checkedOut) return 'Not checked out';
    switch (g.checkoutSource.toUpperCase()) {
      case 'SUPERVISOR':
        return 'Checked out by supervisor';
      case 'TECHNICIAN':
        return 'Checked out by technician';
      default:
        return 'Checked out';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    return SectionCard(
      key: const Key('verify_asset_groups_section'),
      title: 'Asset Group Checkout',
      icon: Icons.inventory_2_outlined,
      children: [
        Text(
          'A checked-out group\'s checklist is part of this record. '
          'Un-checking one here returns the Job Work to the technician for rework.',
          style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: GssmsSpacing.s8),
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) Divider(color: tokens.border, height: GssmsSpacing.s16),
          Row(
            key: Key('verify_group_${groups[i].key}'),
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(groups[i].displayName, style: textTheme.titleSmall),
                    Text(
                      checkoutLabel(groups[i]),
                      style: textTheme.bodySmall?.copyWith(
                        color: groups[i].checkedOut
                            ? tokens.success.foreground
                            : tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (groups[i].checkedOut && canUncheck)
                OutlinedButton(
                  key: Key('uncheck_group_${groups[i].key}'),
                  onPressed: busy ? null : () => onUncheck(groups[i]),
                  child: const Text('Un-check'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
