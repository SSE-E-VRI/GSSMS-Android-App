import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_action_bar.dart';

class _RecentlySynced extends SyncManager {
  @override
  SyncState build() => SyncState(lastSyncTime: DateTime.now(), pendingCount: 1);
}

void main() {
  for (final status in [
    OutboxCommandStatus.pending,
    OutboxCommandStatus.failed,
    OutboxCommandStatus.conflict
  ]) {
    testWidgets('$status suppresses earlier last-sync wording', (tester) async {
      await tester.pumpWidget(ProviderScope(
          overrides: [
            syncManagerProvider.overrideWith(_RecentlySynced.new),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: ChecklistActionBar(
            state: ChecklistLoaded(
                record: MaintenanceRecord(id: 1, lines: [
              MaintenanceRecordLine(
                  id: 2,
                  itemName: 'Reading',
                  recordedValue: '12.5',
                  localSyncStatus: status),
            ])),
            onSignAndSubmit: () {},
            onIncompleteTap: () {},
          )))));
      await tester.pumpAndSettle();
      expect(find.textContaining('Last synced'), findsNothing);
      expect(find.textContaining('Saved on this phone'), findsOneWidget);
      expect(
          find.textContaining(status == OutboxCommandStatus.pending
              ? 'waiting to sync'
              : 'needs attention'),
          findsOneWidget);
    });
  }
}
