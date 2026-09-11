import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';

/// Single primary action bar for the checklist screen.
///
/// Replaces the horizontal multi-button toolbar with one full-width CTA
/// and a passive sync status indicator.
class ChecklistActionBar extends ConsumerWidget {
  const ChecklistActionBar({
    super.key,
    required this.state,
    required this.onSignAndSubmit,
  });

  final ChecklistLoaded state;
  final VoidCallback onSignAndSubmit;

  String? _formatLastSyncTime(DateTime? lastSync) {
    if (lastSync == null) return null;
    final diff = DateTime.now().difference(lastSync);
    if (diff.inMinutes < 1) {
      return 'Last synced just now';
    } else if (diff.inHours < 1) {
      final mins = diff.inMinutes;
      return 'Last synced $mins ${mins == 1 ? 'min' : 'mins'} ago';
    } else if (diff.inDays < 1) {
      final hours = diff.inHours;
      return 'Last synced $hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else {
      final days = diff.inDays;
      return 'Last synced $days ${days == 1 ? 'day' : 'days'} ago';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncManagerProvider);
    final lastSyncedText = _formatLastSyncTime(syncState.lastSyncTime);
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.gssms;
    final remaining = state.remainingRequired;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GssmsSpacing.s16,
            GssmsSpacing.s8,
            GssmsSpacing.s16,
            GssmsSpacing.s12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lastSyncedText != null) ...[
                Text(
                  lastSyncedText,
                  style: textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
                ),
                const SizedBox(height: GssmsSpacing.s6),
              ],
              Semantics(
                liveRegion: true,
                child: FilledButton.icon(
                  key: const Key('complete_checklist_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.success.solid,
                    foregroundColor: tokens.success.onSolid,
                    disabledBackgroundColor: tokens.border,
                    disabledForegroundColor: tokens.textSecondary,
                    minimumSize: const Size.fromHeight(GssmsSize.primaryAction),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GssmsRadius.r8),
                    ),
                  ),
                  onPressed: (state.canSubmit && !state.isSubmitting)
                      ? onSignAndSubmit
                      : null,
                  icon: state.isSubmitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.success.onSolid,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline, size: GssmsSize.iconMd),
                  label: Text(
                    state.canSubmit
                        ? 'Sign & Submit'
                        : '$remaining required ${remaining == 1 ? 'item' : 'items'} left',
                    style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
