import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/date_range_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/empty_state_view.dart';
import 'package:gssms_mobile/core/widgets/error_banner.dart';
import 'package:gssms_mobile/core/widgets/gssms_search_field.dart';
import 'package:gssms_mobile/core/widgets/org_scope_app_bar_filter.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/skeleton_list.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_create_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_status_style.dart';
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

  WorkOrderListController get _controller =>
      ref.read(workOrderListControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)), 'maintenance.view')) {
        return;
      }
      final current = ref.read(workOrderListControllerProvider);
      if (current is WorkOrderListLoaded) {
        _searchController.text = current.searchQuery;
      }
      _controller.fetchWorkOrders();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static bool _hasActiveFilters(WorkOrderListLoaded? s) =>
      s != null &&
      (s.selectedStatusFilter != null ||
          s.selectedTypeFilter != null ||
          s.searchQuery.isNotEmpty ||
          s.dateFrom != null ||
          s.dateTo != null ||
          s.infraType != InfraFilterType.all ||
          (s.infraName?.isNotEmpty ?? false));

  Future<void> _clearFilters() async {
    _searchController.clear();
    _controller
      ..setStatusFilter(null)
      ..setTypeFilter(null)
      ..clearInfraFilters()
      ..setSearchQuery('');
    await _controller.setDateRange(null, null);
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(workOrderListControllerProvider);
    final session = sessionFromAuth(ref.watch(authControllerProvider));

    if (!sessionAllows(session, 'maintenance.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job Works')),
        body: const PermissionDeniedView(),
      );
    }

    final loaded = listState is WorkOrderListLoaded
        ? listState
        : (listState is WorkOrderListError ? listState.previousLoaded : null);

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('Job Works'),
              actions: [
                if (session != null)
                  OrgScopeAppBarFilter(
                    scope: session.scope,
                    selection: loaded?.orgScope ?? OrgScopeSelection.empty,
                    // Station-level narrowing is covered by the in-body Infra
                    // Type / Infra Name filter; Zone/Division/Depot stay here
                    // for multi-depot roles.
                    enableStation: false,
                    onChanged: _controller.setOrgScope,
                  ),
              ],
            ),
      // The filter block is the scroll view's own leading slivers, so it
      // scrolls away with the list instead of permanently eating the screen.
      body: RefreshIndicator(
        onRefresh: () => _controller.fetchWorkOrders(forceRefresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SyncStatusBadge()),
            SliverToBoxAdapter(
              child: FilterStrip(
                child: Column(
                  children: [
                    GssmsSearchField(
                      controller: _searchController,
                      hintText: 'Search by ticket, title, asset, station…',
                      onChanged: _controller.setSearchQuery,
                    ),
                    const SizedBox(height: GssmsSpacing.s8),
                    DateRangeFilterBar(
                      from: loaded?.dateFrom,
                      to: loaded?.dateTo,
                      padding: EdgeInsets.zero,
                      onChanged: _controller.setDateRange,
                    ),
                    const SizedBox(height: GssmsSpacing.s8),
                    _StatusTypeFilters(state: loaded, controller: _controller),
                    const SizedBox(height: GssmsSpacing.s8),
                    _InfraFilters(state: loaded, controller: _controller),
                  ],
                ),
              ),
            ),
            if (loaded != null)
              SliverToBoxAdapter(
                child: ListResultHeader(
                  shown: loaded.filteredOrders.length,
                  total: loaded.workOrders.length,
                  noun: 'job works',
                  onClearFilters: _hasActiveFilters(loaded) ? _clearFilters : null,
                ),
              ),
            ..._buildListSlivers(listState),
          ],
        ),
      ),
      // `maintenance.create` alone is not enough: WorkOrderPermission.
      // CREATE_ROLES restricts create to DEPOT_INCHARGE/DEPOT_USER, which
      // canCreateWorkOrder folds in (RBAC-05).
      floatingActionButton: canCreateWorkOrder(session)
          ? FloatingActionButton.extended(
              key: const Key('fab_create_work_order'),
              icon: const Icon(Icons.add_task_outlined),
              label: const Text('New Job Work'),
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                        builder: (_) => const WorkOrderCreateScreen()));
                if (created == true && mounted) {
                  unawaited(_controller.fetchWorkOrders(forceRefresh: true));
                }
              },
            )
          : null,
    );
  }

  List<Widget> _buildListSlivers(WorkOrderListState state) {
    if (state is WorkOrderListLoading) {
      return const [SliverSkeletonList()];
    }

    if (state is WorkOrderListError) {
      // A refresh that fails must not wipe the list the user was looking at:
      // keep showing the stale rows with an inline error and a retry.
      final previous = state.previousLoaded;
      if (previous != null) {
        return [
          SliverToBoxAdapter(
            child: ErrorBanner(
              message: state.message,
              onRetry: () => _controller.fetchWorkOrders(forceRefresh: true),
            ),
          ),
          ..._buildLoadedSlivers(previous),
        ];
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateView.error(
            title: 'Could not load job works',
            message: state.message,
            onRetry: () => _controller.fetchWorkOrders(forceRefresh: true),
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
      final filtered = _hasActiveFilters(state);
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateView.noResults(
            title: filtered ? 'No job works match these filters' : 'No job works found',
            icon: Icons.assignment_outlined,
            onClearFilters: filtered ? _clearFilters : null,
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          0,
          GssmsSpacing.s4,
          0,
          GssmsSpacing.fabClearance,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final order = orders[i];
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
            childCount: orders.length,
          ),
        ),
      ),
    ];
  }
}

/// Status + Type as a dropdown pair: chip rows clipped mid-label at 360dp
/// and cost two extra rows of vertical space.
class _StatusTypeFilters extends StatelessWidget {
  const _StatusTypeFilters({required this.state, required this.controller});

  final WorkOrderListLoaded? state;
  final WorkOrderListController controller;

  // Every server status a user can filter by, in lifecycle order.
  static const _statuses = [
    WorkOrderStatus.newOrder,
    WorkOrderStatus.assigned,
    WorkOrderStatus.inProgress,
    WorkOrderStatus.reworkRequired,
    WorkOrderStatus.onHold,
    WorkOrderStatus.techCompleted,
    WorkOrderStatus.verified,
    WorkOrderStatus.closed,
    WorkOrderStatus.cancelled,
  ];

  @override
  Widget build(BuildContext context) {
    final s = state;
    int countFor(WorkOrderStatus? status) {
      if (s == null) return 0;
      if (status == null) return s.workOrders.length;
      return s.workOrders.where((w) => w.status == status).length;
    }

    const dense = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: GssmsSpacing.s12,
        vertical: GssmsSpacing.s12,
      ),
    );

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<WorkOrderStatus?>(
            key: const Key('wo_status_filter_dropdown'),
            isExpanded: true,
            value: s?.selectedStatusFilter,
            decoration: dense.copyWith(labelText: 'Status'),
            items: [
              DropdownMenuItem(value: null, child: Text('All (${countFor(null)})')),
              for (final status in _statuses)
                DropdownMenuItem(
                  value: status,
                  child: Text(
                    '${status.displayName} (${countFor(status)})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: controller.setStatusFilter,
          ),
        ),
        const SizedBox(width: GssmsSpacing.s8),
        Expanded(
          child: DropdownButtonFormField<WorkOrderType?>(
            key: const Key('wo_type_filter_dropdown'),
            isExpanded: true,
            value: s?.selectedTypeFilter,
            decoration: dense.copyWith(labelText: 'Type'),
            // Web Job Works chips: All / Corrective / Preventive.
            items: const [
              DropdownMenuItem(value: null, child: Text('All Types')),
              DropdownMenuItem(value: WorkOrderType.corrective, child: Text('Corrective')),
              DropdownMenuItem(value: WorkOrderType.preventive, child: Text('Preventive')),
            ],
            onChanged: controller.setTypeFilter,
          ),
        ),
      ],
    );
  }
}

/// Web filter row: Infra Type + Infra Name. Client-side over the loaded page
/// ([WorkOrderListLoaded.filteredOrders]), so it works offline.
class _InfraFilters extends StatelessWidget {
  const _InfraFilters({required this.state, required this.controller});

  final WorkOrderListLoaded? state;
  final WorkOrderListController controller;

  @override
  Widget build(BuildContext context) {
    final infraType = state?.infraType ?? InfraFilterType.all;
    final infraName = state?.infraName;
    final names = state?.availableInfraNames ?? const <String>[];
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

    const dense = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: GssmsSpacing.s12,
        vertical: GssmsSpacing.s12,
      ),
    );

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<InfraFilterType>(
            key: const Key('wo_infra_type_dropdown'),
            isExpanded: true,
            value: infraType,
            decoration: dense.copyWith(labelText: 'Infra Type'),
            items: [
              for (final t in infraOptions)
                DropdownMenuItem(
                  value: t,
                  child: Text(infraLabel(t), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (t) {
              if (t == null) return;
              controller.setInfraFilter(t, null);
            },
          ),
        ),
        const SizedBox(width: GssmsSpacing.s8),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const Key('wo_infra_name_dropdown'),
            isExpanded: true,
            value: names.contains(infraName) ? infraName : null,
            decoration: dense.copyWith(labelText: 'Infra Name'),
            hint: const Text('All'),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('All')),
              for (final n in names)
                DropdownMenuItem(
                  value: n,
                  child: Text(n, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: controller.setInfraName,
          ),
        ),
        if (hasInfraFilter)
          IconButton(
            key: const Key('wo_infra_clear_button'),
            tooltip: 'Clear infra filters',
            icon: const Icon(Icons.clear, size: 18),
            onPressed: controller.clearInfraFilters,
          ),
      ],
    );
  }
}

class _WorkOrderCard extends StatelessWidget {
  const _WorkOrderCard({
    required this.workOrder,
    required this.onTap,
  });

  final WorkOrder workOrder;
  final VoidCallback onTap;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final priorityTone = tokens.tone(workOrder.priority.severity.tone);
    final metaStyle = textTheme.bodySmall?.copyWith(color: tokens.textSecondary);
    final location = [workOrder.stationName ?? workOrder.infrastructureName, workOrder.depotName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' • ');

    return Card(
      key: Key('work_order_card_${workOrder.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // Priority edge: a left border instead of an IntrinsicHeight row —
        // same look without a second layout pass per card while scrolling.
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: priorityTone.solid, width: 5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              GssmsSpacing.s12,
              GssmsSpacing.s12,
              GssmsSpacing.s16,
              GssmsSpacing.s12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: GssmsSpacing.s8,
                    runSpacing: GssmsSpacing.s4,
                    children: [
                      Text(
                        workOrder.displayReference,
                        style: textTheme.labelMedium?.copyWith(color: tokens.link),
                      ),
                      WorkOrderStatusChip(status: workOrder.status),
                    ],
                  ),
                ),
                const SizedBox(height: GssmsSpacing.s8),
                Text(
                  workOrder.displayTitle,
                  style: textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: GssmsSpacing.s8),
                Wrap(
                  spacing: GssmsSpacing.s8,
                  runSpacing: GssmsSpacing.s4,
                  children: [
                    WorkOrderPriorityChip(priority: workOrder.priority),
                    StatusChip(label: workOrder.type.displayName),
                    if (workOrder.isSlaAtRisk)
                      StatusChip(
                        label: 'SLA ${workOrder.slaStatus!.replaceAll('_', ' ').toLowerCase()}',
                        tone: GssmsTone.danger,
                        icon: Icons.timer_off_outlined,
                      ),
                  ],
                ),
                const SizedBox(height: GssmsSpacing.s8),
                Wrap(
                  spacing: GssmsSpacing.s16,
                  runSpacing: GssmsSpacing.s4,
                  children: [
                    if (location.isNotEmpty)
                      _Meta(icon: Icons.location_on_outlined, text: location, style: metaStyle),
                    if (workOrder.dueDate != null)
                      _Meta(
                        icon: Icons.event_outlined,
                        text: 'Due ${_dateFormat.format(workOrder.dueDate!)}',
                        style: metaStyle,
                      ),
                    if (workOrder.assignedToName != null)
                      _Meta(
                        icon: Icons.person_outline,
                        text: workOrder.assignedToName!,
                        style: metaStyle?.copyWith(color: tokens.link),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.style});

  final IconData icon;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: style?.color),
        const SizedBox(width: GssmsSpacing.s4),
        Flexible(child: Text(text, style: style, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
