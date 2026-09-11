import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Inverted sync status banner.
///
/// Three states, in priority order:
///  * Stuck work (FAILED/CONFLICT) — red strip, tap to retry. Shown first
///    because it is the only state that needs the user to do something.
///  * Queued work (PENDING/SYNCING) — amber strip, tap to drain now.
///  * Everything synced and online — renders nothing.
///
/// The stuck and queued counts are deliberately separate: a permanently
/// rejected command never drains on its own, so folding it into the queued
/// count would leave an "Offline"/"Syncing" strip on screen forever on an
/// online, idle app.
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  static String _changes(int n) => n == 1 ? '1 change' : '$n changes';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncManagerProvider);
    final tokens = context.gssms;

    if (syncState.attentionCount > 0) {
      return _Strip(
        badgeKey: const Key('sync_status_badge_attention'),
        background: tokens.danger.solid,
        foreground: tokens.danger.onSolid,
        icon: Icons.error_outline,
        message:
            '${_changes(syncState.attentionCount)} need attention — tap to retry',
        semanticLabel:
            'Sync problem. ${_changes(syncState.attentionCount)} could not be sent. '
            'Activate to retry.',
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          await ref.read(syncManagerProvider.notifier).retryAllFailed();
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Retrying changes that could not be sent...'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      );
    }

    // Nothing queued and nothing stuck: the connection is not worth screen space.
    if (syncState.mode == SyncConnectivityMode.online &&
        syncState.pendingCount == 0) {
      return const SizedBox.shrink();
    }

    final syncing = syncState.mode == SyncConnectivityMode.syncing;
    final offline = syncState.mode == SyncConnectivityMode.offline;
    final changes = _changes(syncState.pendingCount);
    // Online with work still queued (e.g. just after a restart, before the
    // resume drain finishes) is not "Offline" — say what is actually true.
    final message = syncing
        ? 'Syncing — $changes queued'
        : offline
            ? 'Offline — $changes queued'
            : '$changes waiting to sync — tap to sync now';
    final palette = offline ? tokens.warning : tokens.info;

    return _Strip(
      badgeKey: const Key('sync_status_badge'),
      background: palette.solid,
      foreground: palette.onSolid,
      icon: offline ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined,
      showSpinner: syncing,
      message: message,
      semanticLabel: syncing
          ? 'Syncing $changes.'
          : offline
              ? 'Offline. $changes saved on this device. Activate to retry now.'
              : '$changes saved on this device, waiting to sync. Activate to sync now.',
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        await ref.read(syncManagerProvider.notifier).drainOutbox();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Syncing ${_changes(syncState.pendingCount)}...'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.badgeKey,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.message,
    required this.semanticLabel,
    required this.onTap,
    this.showSpinner = false,
  });

  final Key badgeKey;
  final Color background;
  final Color foreground;
  final IconData icon;
  final String message;
  final String semanticLabel;
  final Future<void> Function() onTap;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      liveRegion: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: InkWell(
          key: badgeKey,
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: background,
            child: Row(
              children: [
                if (showSpinner)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                else
                  Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
