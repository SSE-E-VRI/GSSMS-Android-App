import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/date_range_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:intl/intl.dart';

class WorkOrderListScreen extends ConsumerStatefulWidget {
  const WorkOrderListScreen({super.key});

  @override
  ConsumerState<WorkOrderListScreen> createState() => _WorkOrderListScreenState();
}

class _WorkOrderListScreenState extends ConsumerState<WorkOrderListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(workOrderListControllerProvider.notifier).fetchWorkOrders();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(workOrderListControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final session = authState is Authenticated ? authState.session : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Orders'),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SyncStatusBadge(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref
                .read(workOrderListControllerProvider.notifier)
                .fetchWorkOrders(forceRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (session != null) _buildOrgScope(listState, session),
          _buildDateRange(listState),
          _buildFilterChips(listState),
          Expanded(
            child: _buildListBody(listState),
          ),
        ],
      ),
    );
  }

  Widget _buildOrgScope(WorkOrderListState state, UserSession session) {
    final loaded = state is WorkOrderListLoaded ? state : null;
    return OrgScopeFilterBar(
      scope: session.scope,
      selection: loaded?.orgScope ?? OrgScopeSelection.empty,
      onChanged: (selection) {
        ref.read(workOrderListControllerProvider.notifier).setOrgScope(selection);
      },
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

  Widget _buildFilterChips(WorkOrderListState state) {
    final selectedFilter =
        state is WorkOrderListLoaded ? state.selectedStatusFilter : null;

    final filterOptions = [
      (null, 'All'),
      (WorkOrderStatus.assigned, 'Assigned'),
      (WorkOrderStatus.inProgress, 'In Progress'),
      (WorkOrderStatus.reworkRequired, 'Rework'),
      (WorkOrderStatus.techCompleted, 'Completed'),
      (WorkOrderStatus.newOrder, 'New'),
      (WorkOrderStatus.onHold, 'On Hold'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: filterOptions.map((opt) {
          final isSelected = selectedFilter == opt.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              key: Key('filter_chip_${opt.$2.toLowerCase().replaceAll(' ', '_')}'),
              selected: isSelected,
              label: Text(opt.$2),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppTheme.railwayBlue,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              selectedColor: AppTheme.railwayBlue,
              backgroundColor: Colors.white,
              checkmarkColor: Colors.white,
              onSelected: (_) {
                ref.read(workOrderListControllerProvider.notifier).setStatusFilter(opt.$1);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildListBody(WorkOrderListState state) {
    if (state is WorkOrderListLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is WorkOrderListError) {
      return Center(
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
      );
    }

    if (state is WorkOrderListLoaded) {
      final orders = state.filteredOrders;
      if (orders.isEmpty) {
        return RefreshIndicator(
          onRefresh: () => ref
              .read(workOrderListControllerProvider.notifier)
              .fetchWorkOrders(forceRefresh: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 100),
              Center(
                child: Column(
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
            ],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: () => ref
            .read(workOrderListControllerProvider.notifier)
            .fetchWorkOrders(forceRefresh: true),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final order = orders[index];
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
        ),
      );
    }

    return const SizedBox.shrink();
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
                      Row(
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
                          const SizedBox(width: 8),
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
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              workOrder.status.displayName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (workOrder.dueDate != null)
                            Text(
                              'Due: ${dateFormat.format(workOrder.dueDate!)}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            )
                          else
                            const SizedBox.shrink(),
                          if (workOrder.assignedToName != null)
                            Row(
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
