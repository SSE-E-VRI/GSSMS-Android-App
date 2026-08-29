import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';

void main() {
  group('SyncStatusBadge Widget Tests', () {
    testWidgets('renders Online state when all items are synced', (tester) async {
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

      expect(find.text('Online'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
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

      expect(find.text('3 Queued'), findsOneWidget);
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

      expect(find.text('Syncing...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

class _TestSyncManager extends SyncManager {
  _TestSyncManager(this._initialState);

  final SyncState _initialState;

  @override
  SyncState build() => _initialState;
}
