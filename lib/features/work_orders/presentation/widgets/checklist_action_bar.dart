import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';

/// Single primary action bar for the checklist screen.
///
/// The CTA is always "Sign & Submit" so technicians can find it; while
/// required items remain, the remaining count shows as a helper line above
/// the button instead of replacing its label, and tapping jumps to the
/// first incomplete required line (see `onIncompleteTap`) rather than
/// opening the completion sheet.
class ChecklistActionBar extends ConsumerWidget {
  const ChecklistActionBar({
    super.key,
    required this.state,
    required this.onSignAndSubmit,
    required this.onIncompleteTap,
    this.onSaveProgress,
    this.isSavingProgress = false,
  });

  final ChecklistLoaded state;
  final VoidCallback onSignAndSubmit;

  /// Tapped while [ChecklistLoaded.remainingRequired] > 0: the screen
  /// scrolls to and highlights the first incomplete required line.
  final VoidCallback onIncompleteTap;

  /// Saves pending edits, confirms what is saved/queued and leaves the
  /// screen. When null the button is not shown.
  final VoidCallback? onSaveProgress;
  final bool isSavingProgress;

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
    final offlineOnly =
        sessionFromAuth(ref.watch(authControllerProvider))?.isOffline == true;
    final localStatuses = state.record.lines
        .map((line) => line.localSyncStatus)
        .whereType<OutboxCommandStatus>();
    final needsAttention = localStatuses.any((status) =>
        status == OutboxCommandStatus.failed ||
        status == OutboxCommandStatus.conflict);
    final lastSyncedText = needsAttention
        ? 'Saved on this phone – needs attention'
        : localStatuses.isNotEmpty
            ? 'Saved on this phone – waiting to sync'
            : _formatLastSyncTime(syncState.lastSyncTime);
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
                  style: textTheme.labelSmall
                      ?.copyWith(color: tokens.textSecondary),
                ),
                const SizedBox(height: GssmsSpacing.s6),
              ],
              if (remaining > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: GssmsSpacing.s6),
                  child: Text(
                    '$remaining required ${remaining == 1 ? 'item' : 'items'} left',
                    key: const Key('checklist_remaining_hint'),
                    style: textTheme.labelSmall
                        ?.copyWith(color: tokens.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              Row(
                children: [
                  if (onSaveProgress != null) ...[
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        key: const Key('save_progress_button'),
                        style: OutlinedButton.styleFrom(
                          minimumSize:
                              const Size.fromHeight(GssmsSize.primaryAction),
                          padding: const EdgeInsets.symmetric(
                              horizontal: GssmsSpacing.s8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(GssmsRadius.r8),
                          ),
                        ),
                        onPressed: (state.isSubmitting || isSavingProgress)
                            ? null
                            : onSaveProgress,
                        icon: isSavingProgress
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined,
                                size: GssmsSize.iconMd),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Save progress',
                            maxLines: 1,
                            style: textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: GssmsSpacing.s8),
                  ],
                  Expanded(
                    flex: 3,
                    child: Semantics(
                      liveRegion: true,
                      child: FilledButton.icon(
                        key: const Key('complete_checklist_button'),
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.success.solid,
                          foregroundColor: tokens.success.onSolid,
                          disabledBackgroundColor: tokens.border,
                          disabledForegroundColor: tokens.textSecondary,
                          minimumSize:
                              const Size.fromHeight(GssmsSize.primaryAction),
                          padding: const EdgeInsets.symmetric(
                              horizontal: GssmsSpacing.s8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(GssmsRadius.r8),
                          ),
                        ),
                        onPressed: (offlineOnly ||
                                state.isSubmitting ||
                                isSavingProgress)
                            ? null
                            : (state.canSubmit
                                ? onSignAndSubmit
                                : onIncompleteTap),
                        icon: state.isSubmitting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: tokens.success.onSolid,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline,
                                size: GssmsSize.iconMd),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            offlineOnly ? 'Connect to submit' : 'Sign & Submit',
                            maxLines: 1,
                            style: textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
