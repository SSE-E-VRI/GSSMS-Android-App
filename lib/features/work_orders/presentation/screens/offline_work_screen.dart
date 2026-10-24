import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/sign_out_confirmation.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/downloaded_checklist_access.dart';
import 'checklist_screen.dart';

final offlineWorkProvider =
    FutureProvider.autoDispose<List<WorkOrder>>((ref) async {
  final session = sessionFromAuth(ref.watch(authControllerProvider));
  if (session?.isOffline != true || session?.userId == null) return [];
  final cache = ref.read(localCacheServiceProvider);
  if (await cache.getCacheOwnerUserId() != session!.userId) return [];
  final orders = await cache.getCachedWorkOrders();
  final downloaded = <WorkOrder>[];
  for (final row in orders) {
    final order = await cache.getCachedWorkOrderDetail(row.id) ?? row;
    if (await ref.watch(downloadedChecklistAccessProvider(order).future)) {
      downloaded.add(order);
    }
  }
  return await cache.getCacheOwnerUserId() == session.userId ? downloaded : [];
});

class OfflineWorkScreen extends ConsumerStatefulWidget {
  const OfflineWorkScreen({super.key});
  @override
  ConsumerState<OfflineWorkScreen> createState() => _OfflineWorkScreenState();
}

class _OfflineWorkScreenState extends ConsumerState<OfflineWorkScreen> {
  Timer? _expiry;
  bool _reconnecting = false;
  @override
  void initState() {
    super.initState();
    final deadline =
        sessionFromAuth(ref.read(authControllerProvider))?.offlineUntil;
    final remaining = deadline?.difference(DateTime.now()) ?? Duration.zero;
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (mounted) {
        unawaited(
            ref.read(authControllerProvider.notifier).expireOfflineSession());
      }
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  Future<void> _reconnect() async {
    setState(() => _reconnecting = true);
    try {
      await ref.read(authControllerProvider.notifier).reconnectOfflineSession();
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(offlineWorkProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Saved checklists'), actions: [
        IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => confirmAndSignOut(context, ref)),
      ]),
      body: Column(children: [
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'Offline access – saved checklists and queued readings only. '
                'Available for up to 8 hours after online verification.')),
        FilledButton(
            onPressed: _reconnecting ? null : _reconnect,
            child:
                Text(_reconnecting ? 'Reconnecting…' : 'Reconnect and sync')),
        Expanded(
            child: orders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(
              child: Text(
                  'Saved checklists are unavailable. Reconnect to retry.')),
          data: (rows) => rows.isEmpty
              ? const Center(
                  child: Text(
                      'No assigned checklists downloaded. Connect to prepare work.'))
              : ListView(children: [
                  for (final order in rows)
                    ListTile(
                      title: Text(order.displayTitle),
                      subtitle: Text(order.displayReference),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => ChecklistScreen(
                                  recordId: order.linkedRecordId!))),
                    ),
                ]),
        )),
      ]),
    );
  }
}
