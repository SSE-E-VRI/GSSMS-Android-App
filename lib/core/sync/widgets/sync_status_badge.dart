import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncManagerProvider);

    Color badgeColor;
    IconData badgeIcon;
    String badgeText;

    switch (syncState.mode) {
      case SyncConnectivityMode.online:
        if (syncState.pendingCount == 0) {
          badgeColor = AppTheme.railwayGreen;
          badgeIcon = Icons.cloud_done_outlined;
          badgeText = 'Online';
        } else {
          badgeColor = AppTheme.warningAmber;
          badgeIcon = Icons.cloud_upload_outlined;
          badgeText = '${syncState.pendingCount} Pending';
        }
        break;
      case SyncConnectivityMode.syncing:
        badgeColor = AppTheme.railwayBlue;
        badgeIcon = Icons.sync;
        badgeText = 'Syncing...';
        break;
      case SyncConnectivityMode.offline:
        badgeColor = AppTheme.warningAmber;
        badgeIcon = Icons.cloud_off_outlined;
        badgeText = syncState.pendingCount > 0
            ? '${syncState.pendingCount} Queued'
            : 'Offline';
        break;
    }

    return InkWell(
      key: const Key('sync_status_badge'),
      borderRadius: BorderRadius.circular(16),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor.withOpacity(0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: badgeColor.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (syncState.mode == SyncConnectivityMode.syncing)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: badgeColor,
                ),
              )
            else
              Icon(badgeIcon, size: 14, color: badgeColor),
            const SizedBox(width: 4),
            Text(
              badgeText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: badgeColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
