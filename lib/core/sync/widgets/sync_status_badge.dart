import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Inverted sync status banner.
///
/// Renders nothing when online and fully synchronized.
/// Renders a full-width amber "Offline — N changes queued" strip when offline
/// or when changes are pending background synchronization.
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncManagerProvider);

    // Render nothing when online and synced.
    if (syncState.mode == SyncConnectivityMode.online &&
        syncState.pendingCount == 0) {
      return const SizedBox.shrink();
    }

    final message = syncState.mode == SyncConnectivityMode.offline
        ? 'Offline — ${syncState.pendingCount} changes queued'
        : 'Syncing — ${syncState.pendingCount} changes queued';

    return InkWell(
      key: const Key('sync_status_badge'),
      onTap: () {
        ref.read(syncManagerProvider.notifier).drainOutbox();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              syncState.pendingCount > 0
                  ? 'Syncing ${syncState.pendingCount} pending items...'
                  : 'Connectivity: ${syncState.mode.label}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppTheme.warningAmber,
        child: Row(
          children: [
            if (syncState.mode == SyncConnectivityMode.syncing)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black87,
                ),
              )
            else
              const Icon(
                Icons.cloud_off_outlined,
                size: 16,
                color: Colors.black87,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ) ??
                    const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
