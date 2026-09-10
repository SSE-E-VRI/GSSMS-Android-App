import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/date_range_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/org_scope_app_bar_filter.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'dart:async';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_create_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:intl/intl.dart';

class WorkOrderListScreen extends ConsumerStatefulWidget {
  const WorkOrderListScreen({
    super.key,
    this.isEmbedded = false,
  });

  final bool isEmbedded;

  @override
  ConsumerState<WorkOrderListScreen> createState() => _WorkOrderListScreenState();
}

class _WorkOrderListScreenState extends ConsumerState<WorkOrderListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)), 'maintenance.view')) {
        return;
      }
      ref.read(workOrderListControllerProvider.notifier).fetchWorkOrders();
    });
  }

  void _onSearchTextChanged() {
    // Rebuild so the clear button appears/disappears with the query.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(workOrderListControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final session = sessionFromAuth(authState);

    if (!sessionAllows(session, 'maintenance.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Work Orders')),
        body: const PermissionDeniedView(),
      );
    }

    final loaded = listState is WorkOrderListLoaded ? listState : null;

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('Work Orders'),
        actions: [
          if (session != null)
            OrgScopeAppBarFilter(
              scope: session.scope,
              selection: loaded?.orgScope ?? OrgScopeSelection.empty,
              // Station-level narrowing is dropped here: the in-body
              // "Infra Type / Infra Name" filter below the search bar
              // already covers picking one Station (Infra Type = Station +
              // a Location Name), so offering it a second time in this
              // sheet — via a different mechanism (server re-query vs the
              // in-body filter's client-side pass over the same depot-
              // scoped page) — was pure duplication for the common
              // depot-scoped user. Zone/Division/Depot stay: nothing else
              // on this screen covers that axis for multi-depot roles.
              enableStation: false,
              onChanged: (selection) {
                ref
                    .read(workOrderListControllerProvider.notifier)
                    .setOrgScope(selection);
              },
            ),
        ],
      ),
      // The filter block (search/date/status/type/infra) used to sit in a
      // fixed Column above an `Expanded` list, permanently eating ~40% of
      // the screen on a typical phone. It's now the scrollable content's own
      // leading slivers, so it scrolls away with the list instead of pinning
      // in place — scroll down and the whole filter stack moves up and off
      // screen, leaving the full viewport for work order cards; scroll back
      // to the top and the filters are still there, unchanged, not reset.
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(workOrderListControllerProvider.notifier)
            .fetchWorkOrders(forceRefresh: true),
        child: CustomScrollView(
          // Always scrollable so pull-to-refresh works even when the filter
          // block plus a short (or empty) results list don't fill the
          // viewport — same reasoning the old empty-state ListView had for
          // setting this explicitly.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SyncStatusBadge()),
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: _buildDateRange(listState)),
            SliverToBoxAdapter(child: _buildStatusTypeFilters(listState)),
            SliverToBoxAdapter(child: _buildInfraFilter(listState)),
            ..._buildListSlivers(listState),
          ],
        ),
      ),
      // Web "+ New Job Work". Unlike the complaint/inspection FABs,
      // `maintenance.create` alone is not enough here: the backend's
      // WorkOrderPermission.CREATE_ROLES restricts the generic create action
      // to DEPOT_INCHARGE/DEPOT_USER with no admin-tier bypass, so
      // SUPER_ADMIN/ZR_ADMIN/DIV_ADMIN/DIV_HQ_USER hold the permission but
      // would still 403 on submit — canCreateWorkOrder folds in that role
      // check (RBAC-05).
      floatingActionButton: canCreateWorkOrder(session)
          ? FloatingActionButton.extended(
              key: const Key('fab_create_work_order'),
              icon: const Icon(Icons.add_task_outlined),
              label: const Text('New Job Work'),
              backgroundColor: AppTheme.railwayBlue,
              foregroundColor: Colors.white,
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                        builder: (_) => const WorkOrderCreateScreen()));
                if (created == true && mounted) {
                  unawaited(ref
                      .read(workOrderListControllerProvider.notifier)
                      .fetchWorkOrders(forceRefresh: true));
                }
              },
            )
          : null,
    );
  }


  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by ID, title, asset, station...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    ref.read(workOrderListControllerProvider.notifier).setSearchQuery('');
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
        onChanged: (val) {
          ref.read(workOrderListControllerProvider.notifier).setSearchQuery(val);
        },
      ),
    );
  }

  Widget _buildDateRange(WorkOrderListState state) {
    final loaded = state is WorkOrderListLoaded ? state : null;
    return DateRangeFilterBar(
      from: loaded?.dateFrom,
      to: loaded?.dateTo,
      onChanged: (from, to) {
        ref.read(workOrderListControllerProvider.notifier).setDateRange(from, to);
      },
    );
  }

  /// Status + Type filters, as a dropdown pair rather than two rows of
  /// FilterChips. The chip rows wrapped/overflowed once every status
  /// (Assigned/In Progress/Rework/Completed/New/On Hold) was on screen at
  /// once — on a 360dp phone the last chip routinely got clipped mid-label
  /// — and cost two extra scrollable rows of vertical space. Matches the
  /// existing Infra Type/Infra Name dropdown row directly below it.
  Widget _buildStatusTypeFilters(WorkOrderListState state) {
    final selectedStatus =
        state is WorkOrderListLoaded ? state.selectedStatusFilter : null;
    final selectedType =
        state is WorkOrderListLoaded ? state.selectedTypeFilter : null;

    final statusOptions = [
      (null, 'All'),
      (WorkOrderStatus.assigned, 'Assigned'),
      (WorkOrderStatus.inProgress, 'In Progress'),
      (WorkOrderStatus.reworkRequired, 'Rework'),
      (WorkOrderStatus.techCompleted, 'Completed'),
      (WorkOrderStatus.newOrder, 'New'),
      (WorkOrderStatus.onHold, 'On Hold'),
    ];
    // "Closed" on web is a status, covered by the status dropdown above, so
    // only the two real type values plus "All Types" are offered here.
    final typeOptions = [
      (null, 'All Types'),
      (WorkOrderType.corrective, 'Corrective'),
      (WorkOrderType.preventive, 'Preventive'),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<WorkOrderStatus?>(
              key: const Key('wo_status_filter_dropdown'),
              isExpanded: true,
              value: selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Status',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              items: statusOptions
                  .map((opt) => DropdownMenuItem(
                      value: opt.$1,
                      child: Text(opt.$2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (status) {
                ref
                    .read(workOrderListControllerProvider.notifier)
                    .setStatusFilter(status);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<WorkOrderType?>(
              key: const Key('wo_type_filter_dropdown'),
              isExpanded: true,
              value: selectedType,
              decoration: const InputDecoration(
                labelText: 'Type',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              items: typeOptions
                  .map((opt) => DropdownMenuItem(
                      value: opt.$1,
                      child: Text(opt.$2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (type) {
                ref
                    .read(workOrderListControllerProvider.notifier)
                    .setTypeFilter(type);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Web filter row: Infra Type + Infra Name + Clear. Client-side until the
  /// API offers matching query params — filters the already-loaded page via
  /// [WorkOrderListLoaded.filteredOrders], so it works offline.
  Widget _buildInfraFilter(WorkOrderListState state) {
    final loaded = state is WorkOrderListLoaded
        ? state
        : (state is WorkOrderListError ? state.previousLoaded : null);
    final infraType = loaded?.infraType ?? InfraFilterType.all;
    final infraName = loaded?.infraName;
    final names = loaded?.availableInfraNames ?? const <String>[];
    const infraOptions = [
      InfraFilterType.all,
      InfraFilterType.station,
      InfraFilterType.lcGate,
      InfraFilterType.serviceBuilding,
      InfraFilterType.staffQuarter,
    ];
    String infraLabel(InfraFilterType t) =>
        t == InfraFilterType.all ? 'All Types' : t.label;
    final hasInfraFilter =
        infraType != InfraFilterType.all || (infraName?.isNotEmpty ?? false);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<InfraFilterType>(
              key: const Key('wo_infra_type_dropdown'),
              isExpanded: true,
              value: infraType,
              decoration: const InputDecoration(
                labelText: 'Infra Type',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              items: infraOptions
                  .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(infraLabel(t),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (t) {
                if (t == null) return;
                ref
                    .read(workOrderListControllerProvider.notifier)
                    .setInfraFilter(t, null);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<String>(
              key: const Key('wo_infra_name_dropdown'),
              isExpanded: true,
              value: names.contains(infraName) ? infraName : null,
              decoration: const InputDecoration(
                labelText: 'Infra Name',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              hint: const Text('All',
                  style: TextStyle(fontSize: 13)),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('All')),
                ...names.map((n) => DropdownMenuItem(
                    value: n,
                    child: Text(n,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)))),
              ],
              onChanged: (n) {
                ref
                    .read(workOrderListControllerProvider.notifier)
                    .setInfraName(n);
              },
            ),
          ),
          if (hasInfraFilter) ...[
            const SizedBox(width: 4),
            IconButton(
              key: const Key('wo_infra_clear_button'),
              tooltip: 'Clear infra filters',
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () {
                ref
                    .read(workOrderListControllerProvider.notifier)
                    .clearInfraFilters();
              },
            ),
          ],
        ],
      ),
    );
  }

  /// Slivers for the scrollable body below the filter block (see build()).
  /// One `RefreshIndicator` now wraps the whole `CustomScrollView` — filters
  /// included — so none of these branches carry their own.
  List<Widget> _buildListSlivers(WorkOrderListState state) {
    if (state is WorkOrderListLoading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (state is WorkOrderListError) {
      // A refresh that fails must not wipe the list the user was looking at:
      // keep showing the stale rows with an inline error and a retry.
      final previous = state.previousLoaded;
      if (previous != null) {
        return [
          SliverToBoxAdapter(
            child: Material(
              color: AppTheme.errorRed.withOpacity(0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, size: 18, color: AppTheme.errorRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.message,
                        style: const TextStyle(fontSize: 12, color: AppTheme.errorRed),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(workOrderListControllerProvider.notifier)
                          .fetchWorkOrders(forceRefresh: true),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ..._buildLoadedSlivers(previous),
        ];
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppTheme.errorRed),
                  const SizedBox(height: 12),
                  Text(
                    state.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => ref
                        .read(workOrderListControllerProvider.notifier)
                        .fetchWorkOrders(forceRefresh: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    if (state is WorkOrderListLoaded) {
      return _buildLoadedSlivers(state);
    }

    return const [SliverToBoxAdapter(child: SizedBox.shrink())];
  }

  List<Widget> _buildLoadedSlivers(WorkOrderListLoaded state) {
    final orders = state.filteredOrders;
    if (orders.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'No work orders found.',
                  style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              // Odd indices are the 12px separators between cards — same
              // spacing the old ListView.separated used.
              if (i.isOdd) return const SizedBox(height: 12);
              final order = orders[i ~/ 2];
              return _WorkOrderCard(
                workOrder: order,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WorkOrderDetailScreen(workOrderId: order.id),
                    ),
                  );
                },
              );
            },
            childCount: orders.length * 2 - 1,
          ),
        ),
      ),
    ];
  }
}

class _WorkOrderCard extends StatelessWidget {
  const _WorkOrderCard({
    required this.workOrder,
    required this.onTap,
  });

  final WorkOrder workOrder;
  final VoidCallback onTap;

  Color _getStatusColor(WorkOrderStatus status) {
    switch (status) {
      case WorkOrderStatus.newOrder:
        return Colors.blueGrey;
      case WorkOrderStatus.assigned:
        return Colors.blue;
      case WorkOrderStatus.inProgress:
        return Colors.orange;
      case WorkOrderStatus.techCompleted:
        return Colors.teal;
      case WorkOrderStatus.verified:
      case WorkOrderStatus.closed:
        return AppTheme.railwayGreen;
      case WorkOrderStatus.reworkRequired:
        return AppTheme.errorRed;
      case WorkOrderStatus.onHold:
        return Colors.amber.shade800;
      case WorkOrderStatus.cancelled:
        return Colors.grey;
      case WorkOrderStatus.unknown:
        return Colors.grey;
    }
  }

  Color _getPriorityColor(WorkOrderPriority priority) {
    switch (priority) {
      case WorkOrderPriority.critical:
        return Colors.red.shade900;
      case WorkOrderPriority.high:
        return AppTheme.errorRed;
      case WorkOrderPriority.medium:
        return Colors.orange.shade700;
      case WorkOrderPriority.low:
        return Colors.green;
    }
  }

  String _getStatusGlyph(WorkOrderStatus status) {
    switch (status) {
      case WorkOrderStatus.verified:
      case WorkOrderStatus.techCompleted:
      case WorkOrderStatus.closed:
        return '✓';
      case WorkOrderStatus.inProgress:
      case WorkOrderStatus.assigned:
      case WorkOrderStatus.newOrder:
      case WorkOrderStatus.onHold:
        return '!';
      case WorkOrderStatus.reworkRequired:
      case WorkOrderStatus.cancelled:
        return '✕';
      case WorkOrderStatus.unknown:
        return '•';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(workOrder.status);
    final priorityColor = _getPriorityColor(workOrder.priority);
    final dateFormat = DateFormat('dd MMM yyyy');

    return Card(
      key: Key('work_order_card_${workOrder.id}'),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Priority color strip
              Container(
                width: 6,
                color: priorityColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.railwayBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'WO #${workOrder.id}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.railwayBlue,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              workOrder.type.code,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_getStatusGlyph(workOrder.status)} ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                                Text(
                                  workOrder.status.displayName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        workOrder.displayTitle,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      if (workOrder.stationName != null || workOrder.depotName != null)
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                [workOrder.stationName, workOrder.depotName]
                                    .where((s) => s != null && s.isNotEmpty)
                                    .join(' • '),
                                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (workOrder.dueDate != null)
                            Text(
                              'Due: ${dateFormat.format(workOrder.dueDate!)}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          if (workOrder.assignedToName != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_outline, size: 14, color: AppTheme.railwayBlue),
                                const SizedBox(width: 4),
                                Text(
                                  workOrder.assignedToName!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.railwayBlue,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
