import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/notifications/domain/models/notification_item.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_navigation.dart';
import 'package:intl/intl.dart';

/// Alerts derived from the work orders the server returned.
///
/// GSSMS exposes no notification service, so this reads the work order list
/// rather than inventing alerts, and keeps only the read/dismissed state of its
/// own. Read state is per session: there is nowhere on the server to record it.
final notificationsListProvider =
    NotifierProvider<NotificationsNotifier, List<NotificationItem>>(() {
  return NotificationsNotifier();
});

class NotificationsNotifier extends Notifier<List<NotificationItem>> {
  final Set<String> _readIds = {};

  @override
  List<NotificationItem> build() {
    final listState = ref.watch(workOrderListControllerProvider);
    if (listState is! WorkOrderListLoaded) return const [];

    final items = <NotificationItem>[];
    for (final wo in listState.workOrders) {
      items.addAll(NotificationItem.fromWorkOrder(wo));
    }

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return [
      for (final item in items)
        if (_readIds.contains(item.id)) item.copyWith(isRead: true) else item,
    ];
  }

  int get unreadCount => state.where((n) => !n.isRead).length;

  void markAsRead(String id) {
    _readIds.add(id);
    state = state
        .map((item) => item.id == id ? item.copyWith(isRead: true) : item)
        .toList();
  }

  void markAllAsRead() {
    _readIds.addAll(state.map((n) => n.id));
    state = state.map((item) => item.copyWith(isRead: true)).toList();
  }

  /// Re-reads the work orders these alerts are derived from.
  Future<void> refresh() {
    return ref
        .read(workOrderListControllerProvider.notifier)
        .fetchWorkOrders(forceRefresh: true);
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Alerts come from the work order list, so make sure it has been loaded
    // when this screen is opened directly from Home.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)), 'maintenance.view')) {
        return;
      }
      final listState = ref.read(workOrderListControllerProvider);
      if (listState is! WorkOrderListLoaded) {
        ref.read(workOrderListControllerProvider.notifier).fetchWorkOrders();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = sessionOf(ref);
    if (!sessionAllows(session, 'maintenance.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications & Alerts')),
        body: const PermissionDeniedView(),
      );
    }

    final notifications = ref.watch(notificationsListProvider);
    final listState = ref.watch(workOrderListControllerProvider);
    final dateFormat = DateFormat('dd MMM, hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications & Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all as read',
            onPressed: () =>
                ref.read(notificationsListProvider.notifier).markAllAsRead(),
          ),
        ],
      ),
      body: _buildBody(notifications, listState, dateFormat, session),
    );
  }

  Widget _buildBody(
    List<NotificationItem> notifications,
    WorkOrderListState listState,
    DateFormat dateFormat,
    UserSession? session,
  ) {
    if (listState is WorkOrderListLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (listState is WorkOrderListError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: context.gssms.danger.foreground),
              const SizedBox(height: 12),
              Text(
                listState.message,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.gssms.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.read(notificationsListProvider.notifier).refresh(),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(notificationsListProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(
              child: Column(
                children: [
                  const Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    'No active notifications.',
                    style: TextStyle(fontSize: 16, color: context.gssms.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(notificationsListProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: notifications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = notifications[index];

          return Card(
            key: Key('notification_item_${item.id}'),
            elevation: item.isRead ? 1 : 3,
            color: item.isRead
                ? Theme.of(context).cardTheme.color
                : context.gssms.info.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: item.isRead
                    ? Colors.transparent
                    : context.gssms.info.border,
              ),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: _iconTone(item.type).solid,
                child: Icon(_getIconData(item.type),
                    color: _iconTone(item.type).onSolid, size: 20),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontWeight:
                            item.isRead ? FontWeight.w600 : FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    dateFormat.format(item.timestamp),
                    style: TextStyle(
                        fontSize: 11, color: context.gssms.textSecondary),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  item.message,
                  style: TextStyle(
                      fontSize: 13, color: context.gssms.textSecondary),
                ),
              ),
              onTap: () {
                ref.read(notificationsListProvider.notifier).markAsRead(item.id);
                if (item.targetEntityType == 'WORK_ORDER' &&
                    item.targetEntityId != null) {
                  openWorkOrderGuarded(
                    context: context,
                    session: session,
                    workOrderId: item.targetEntityId!,
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }

  IconData _getIconData(NotificationType type) {
    switch (type) {
      case NotificationType.assignment:
        return Icons.assignment_turned_in;
      case NotificationType.rework:
        return Icons.replay_outlined;
      case NotificationType.overdue:
        return Icons.schedule_outlined;
      case NotificationType.slaBreach:
        return Icons.warning_amber_rounded;
      case NotificationType.complaint:
        return Icons.report_problem;
      case NotificationType.schedule:
        return Icons.schedule;
      case NotificationType.alert:
        return Icons.notifications_active;
    }
  }

  GssmsTonePalette _iconTone(NotificationType type) {
    final tokens = context.gssms;
    switch (type) {
      case NotificationType.assignment:
      case NotificationType.alert:
        return tokens.info;
      case NotificationType.rework:
        return tokens.danger;
      case NotificationType.overdue:
      case NotificationType.complaint:
        return tokens.accent;
      case NotificationType.slaBreach:
        return tokens.warning;
      case NotificationType.schedule:
        return tokens.success;
    }
  }
}
