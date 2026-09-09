import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';

void main() {
  group('SyncStatusBadge Widget Tests', () {
    testWidgets('renders nothing when online and all items are synced', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncManagerProvider.overrideWith(() => _TestSyncManager(
                  const SyncState(mode: SyncConnectivityMode.online, pendingCount: 0),
                )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(child: SyncStatusBadge()),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('sync_status_badge')), findsNothing);
    });

    testWidgets('renders Offline queued count when offline with pending actions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncManagerProvider.overrideWith(() => _TestSyncManager(
                  const SyncState(mode: SyncConnectivityMode.offline, pendingCount: 3),
                )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(child: SyncStatusBadge()),
            ),
          ),
        ),
      );

      expect(find.text('Offline — 3 changes queued'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    });

    testWidgets('renders Syncing indicator when synchronizing', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncManagerProvider.overrideWith(() => _TestSyncManager(
                  const SyncState(mode: SyncConnectivityMode.syncing, pendingCount: 2),
                )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(child: SyncStatusBadge()),
            ),
          ),
        ),
      );

      expect(find.text('Syncing — 2 changes queued'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('stays hidden when online with only a failed command counted separately',
        (tester) async {
      // Regression: attentionCount used to be folded into pendingCount, which
      // left the amber strip up permanently — reading "Syncing" — on an online,
      // idle app that had one rejected command.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncManagerProvider.overrideWith(() => _TestSyncManager(
                  const SyncState(
                    mode: SyncConnectivityMode.online,
                    pendingCount: 0,
                    attentionCount: 1,
                  ),
                )),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: SyncStatusBadge())),
          ),
        ),
      );

      expect(
        find.byKey(const Key('sync_status_badge')),
        findsNothing,
        reason: 'stuck work is not queued work and must not claim to be syncing',
      );
      expect(find.textContaining('Syncing'), findsNothing);
      expect(find.textContaining('Offline'), findsNothing);
    });

    testWidgets('renders an actionable attention strip for stuck commands',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncManagerProvider.overrideWith(() => _TestSyncManager(
                  const SyncState(
                    mode: SyncConnectivityMode.online,
                    pendingCount: 0,
                    attentionCount: 2,
                  ),
                )),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: SyncStatusBadge())),
          ),
        ),
      );

      expect(find.byKey(const Key('sync_status_badge_attention')), findsOneWidget);
      expect(find.text('2 changes need attention — tap to retry'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('singularises the count', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncManagerProvider.overrideWith(() => _TestSyncManager(
                  const SyncState(
                    mode: SyncConnectivityMode.offline,
                    pendingCount: 1,
                  ),
                )),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: SyncStatusBadge())),
          ),
        ),
      );

      expect(find.text('Offline — 1 change queued'), findsOneWidget);
    });
  });
}

class _TestSyncManager extends SyncManager {
  _TestSyncManager(this._initialState);

  final SyncState _initialState;

  @override
  SyncState build() => _initialState;
}
