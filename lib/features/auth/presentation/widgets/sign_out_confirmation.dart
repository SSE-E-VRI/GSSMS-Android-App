import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';

/// Asks before signing out, and says what will be lost.
///
/// Sign-out deliberately wipes this device's operational cache — including the
/// offline outbox — so a shared phone never leaks one user's queued work to the
/// next (see `clearOperationalSession`). That makes an accidental tap on the
/// app-bar icon destructive whenever work is still queued, so the dialog counts
/// unsynced changes and names the consequence instead of asking "Are you sure?".
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final sync = ref.read(syncManagerProvider.notifier);
  try {
    await sync.refreshPendingCount();
  } catch (_) {
    // Storage unavailable: fall back to the last known counts.
  }
  if (!context.mounted) return;

  final syncState = ref.read(syncManagerProvider);
  final unsynced = syncState.pendingCount + syncState.attentionCount;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _SignOutDialog(unsynced: unsynced),
  );
  if (confirmed != true) return;
  await ref.read(authControllerProvider.notifier).logout();
}

class _SignOutDialog extends StatelessWidget {
  const _SignOutDialog({required this.unsynced});

  final int unsynced;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final hasUnsynced = unsynced > 0;
    final changes = unsynced == 1 ? '1 change' : '$unsynced changes';

    return AlertDialog(
      icon: Icon(
        hasUnsynced ? Icons.cloud_off_outlined : Icons.logout,
        color: hasUnsynced ? tokens.danger.foreground : null,
      ),
      title: const Text('Sign out?'),
      content: hasUnsynced
          ? Container(
              key: const Key('sign_out_unsynced_warning'),
              padding: const EdgeInsets.all(GssmsSpacing.s12),
              decoration: BoxDecoration(
                color: tokens.danger.background,
                borderRadius: BorderRadius.circular(GssmsRadius.r8),
                border: Border.all(color: tokens.danger.border),
              ),
              child: Text(
                '$changes saved on this device ${unsynced == 1 ? 'has' : 'have'} '
                'not reached the server yet. Signing out removes '
                '${unsynced == 1 ? 'it' : 'them'} from this device and '
                '${unsynced == 1 ? 'it' : 'they'} cannot be recovered.\n\n'
                'Connect to the network and let the changes sync first.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: tokens.danger.foreground),
              ),
            )
          : const Text(
              'You will need to sign in again to continue working on this device.',
            ),
      actions: [
        TextButton(
          key: const Key('sign_out_cancel_button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(hasUnsynced ? 'Stay signed in' : 'Cancel'),
        ),
        FilledButton(
          key: const Key('sign_out_confirm_button'),
          style: hasUnsynced
              ? FilledButton.styleFrom(
                  backgroundColor: tokens.danger.solid,
                  foregroundColor: tokens.danger.onSolid,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(hasUnsynced ? 'Discard and sign out' : 'Sign out'),
        ),
      ],
    );
  }
}
