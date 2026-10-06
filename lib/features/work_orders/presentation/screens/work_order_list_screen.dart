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
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_create_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/job_work_report_screen.dart';
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

  static int _activeFilterCount(WorkOrderListLoaded? s) {
    if (s == null) return 0;
    var count = 0;
    if (s.dateFrom != null || s.dateTo != null) count++;
    if (s.selectedStatusFilter != null) count++;
    if (s.selectedTypeFilter != null) count++;
    if (s.infraType != InfraFilterType.all) count++;
    if (s.infraName != null && s.infraName!.isNotEmpty) count++;
    return count;
  }

  Future<void> _clearFilters() async {
    _searchController.clear();
    _controller
      ..setStatusFilter(null)
      ..setTypeFilter(null)
      ..clearInfraFilters()
      ..setSearchQuery('');
    await _controller.setDateRange(null, null);
  }

  void _openFilterSheet(BuildContext context, WorkOrderListLoaded? loaded) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WorkOrderFilterSheet(
        state: loaded,
        controller: _controller,
        onClearAll: _clearFilters,
      ),
    );
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
    final filterCount = _activeFilterCount(loaded);

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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GssmsSearchField(
                            controller: _searchController,
                            hintText: 'Search ticket, title, asset',
                            onChanged: _controller.setSearchQuery,
                          ),
                        ),
                        const SizedBox(width: GssmsSpacing.s8),
                        _FiltersButton(
                          activeCount: filterCount,
                          onPressed: () => _openFilterSheet(context, loaded),
                        ),
                      ],
                    ),
                    if (loaded != null && filterCount > 0) ...[
                      const SizedBox(height: GssmsSpacing.s8),
                      _WorkOrderActiveFilterChips(
                        state: loaded,
                        controller: _controller,
                        onClearAll: _clearFilters,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (loaded != null)
              SliverToBoxAdapter(
                child: ListResultHeader(
                  shown: loaded.filteredOrders.length,
                  total: loaded.workOrders.length,
                  noun: 'Job Works',
                  nounSingular: 'Job Work',
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
    final session = sessionFromAuth(ref.watch(authControllerProvider));
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
                session: session,
                onViewReport: JobWorkReportScreen.canShow(order, session)
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                JobWorkReportScreen(workOrder: order),
                          ),
                        )
                    : null,
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

class _FiltersButton extends StatelessWidget {
  const _FiltersButton({
    required this.activeCount,
    required this.onPressed,
  });

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final button = OutlinedButton.icon(
      key: const Key('filters_button'),
      onPressed: onPressed,
      icon: const Icon(Icons.filter_list, size: 20),
      label: const Text('Filters'),
      style: OutlinedButton.styleFrom(
        foregroundColor: activeCount > 0 ? tokens.link : tokens.textPrimary,
        side: BorderSide(
          color: activeCount > 0 ? tokens.link : tokens.borderStrong,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: GssmsSpacing.s12,
          vertical: GssmsSpacing.s12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r12),
        ),
      ),
    );

    if (activeCount == 0) return button;

    return Badge(
      key: const Key('filters_badge'),
      label: Text('$activeCount'),
      backgroundColor: tokens.link,
      child: button,
    );
  }
}

class _WorkOrderActiveFilterChips extends StatelessWidget {
  const _WorkOrderActiveFilterChips({
    required this.state,
    required this.controller,
    required this.onClearAll,
  });

  final WorkOrderListLoaded state;
  final WorkOrderListController controller;
  final VoidCallback onClearAll;

  static final DateFormat _dateFormat = DateFormat('dd MMM');

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final chips = <Widget>[];

    if (state.dateFrom != null || state.dateTo != null) {
      final String dateLabel;
      if (state.dateFrom != null && state.dateTo != null) {
        dateLabel =
            '${_dateFormat.format(state.dateFrom!)} - ${_dateFormat.format(state.dateTo!)}';
      } else if (state.dateFrom != null) {
        dateLabel = 'From ${_dateFormat.format(state.dateFrom!)}';
      } else {
        dateLabel = 'To ${_dateFormat.format(state.dateTo!)}';
      }
      chips.add(
        InputChip(
          key: const Key('chip_date_range'),
          label: Text(dateLabel),
          onDeleted: () => controller.setDateRange(null, null),
        ),
      );
    }

    if (state.selectedStatusFilter != null) {
      chips.add(
        InputChip(
          key: const Key('chip_status_filter'),
          label: Text('Status: ${state.selectedStatusFilter!.displayName}'),
          onDeleted: () => controller.setStatusFilter(null),
        ),
      );
    }

    if (state.selectedTypeFilter != null) {
      chips.add(
        InputChip(
          key: const Key('chip_type_filter'),
          label: Text(
            'Type: ${state.selectedTypeFilter == WorkOrderType.corrective ? 'Corrective' : 'Preventive'}',
          ),
          onDeleted: () => controller.setTypeFilter(null),
        ),
      );
    }

    if (state.infraType != InfraFilterType.all) {
      chips.add(
        InputChip(
          key: const Key('chip_infra_type'),
          label: Text('Infra Type: ${state.infraType.label}'),
          onDeleted: () => controller.setInfraFilter(InfraFilterType.all, null),
        ),
      );
    }

    if (state.infraName != null && state.infraName!.isNotEmpty) {
      chips.add(
        InputChip(
          key: const Key('chip_infra_name'),
          label: Text('Infra: ${state.infraName}'),
          onDeleted: () => controller.setInfraName(null),
        ),
      );
    }

    return Wrap(
      spacing: GssmsSpacing.s8,
      runSpacing: GssmsSpacing.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...chips,
        TextButton(
          key: const Key('clear_all_filters_button'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: GssmsSpacing.s8),
            visualDensity: VisualDensity.compact,
            foregroundColor: tokens.link,
          ),
          onPressed: onClearAll,
          child: const Text('Clear all'),
        ),
      ],
    );
  }
}

class _WorkOrderFilterSheet extends StatelessWidget {
  const _WorkOrderFilterSheet({
    required this.state,
    required this.controller,
    required this.onClearAll,
  });

  final WorkOrderListLoaded? state;
  final WorkOrderListController controller;
  final VoidCallback onClearAll;

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

  static const _infraOptions = [
    InfraFilterType.all,
    InfraFilterType.station,
    InfraFilterType.lcGate,
    InfraFilterType.serviceBuilding,
    InfraFilterType.staffQuarter,
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final s = state;
    final infraType = s?.infraType ?? InfraFilterType.all;
    final infraName = s?.infraName;
    final names = s?.availableInfraNames ?? const <String>[];

    const dense = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: GssmsSpacing.s12,
        vertical: GssmsSpacing.s12,
      ),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: GssmsSpacing.s16,
          right: GssmsSpacing.s16,
          top: GssmsSpacing.s16,
          bottom: MediaQuery.of(context).viewInsets.bottom + GssmsSpacing.s16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Filters', style: textTheme.titleMedium),
                  TextButton(
                    onPressed: () {
                      onClearAll();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: GssmsSpacing.s12),
              DateRangeFilterBar(
                from: s?.dateFrom,
                to: s?.dateTo,
                padding: EdgeInsets.zero,
                onChanged: controller.setDateRange,
              ),
              const SizedBox(height: GssmsSpacing.s12),
              DropdownButtonFormField<WorkOrderStatus?>(
                key: const Key('wo_status_filter_dropdown'),
                isExpanded: true,
                value: s?.selectedStatusFilter,
                decoration: dense.copyWith(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  for (final status in _statuses)
                    DropdownMenuItem(
                      value: status,
                      child: Text(
                        status.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: controller.setStatusFilter,
              ),
              const SizedBox(height: GssmsSpacing.s12),
              DropdownButtonFormField<WorkOrderType?>(
                key: const Key('wo_type_filter_dropdown'),
                isExpanded: true,
                value: s?.selectedTypeFilter,
                decoration: dense.copyWith(labelText: 'Job Work type'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All Types')),
                  DropdownMenuItem(value: WorkOrderType.corrective, child: Text('Corrective')),
                  DropdownMenuItem(value: WorkOrderType.preventive, child: Text('Preventive')),
                ],
                onChanged: controller.setTypeFilter,
              ),
              const SizedBox(height: GssmsSpacing.s12),
              DropdownButtonFormField<InfraFilterType>(
                key: const Key('wo_infra_type_dropdown'),
                isExpanded: true,
                value: infraType,
                decoration: dense.copyWith(labelText: 'Infrastructure type'),
                items: [
                  for (final t in _infraOptions)
                    DropdownMenuItem(
                      value: t,
                      child: Text(
                        t == InfraFilterType.all ? 'All Types' : t.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (t) {
                  if (t == null) return;
                  controller.setInfraFilter(t, null);
                },
              ),
              const SizedBox(height: GssmsSpacing.s12),
              DropdownButtonFormField<String>(
                key: const Key('wo_infra_name_dropdown'),
                isExpanded: true,
                value: names.contains(infraName) ? infraName : null,
                decoration: dense.copyWith(labelText: 'Infrastructure'),
                hint: const Text('All'),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('All')),
                  for (final n in names)
                    DropdownMenuItem(
                      value: n,
                      child: Text(n, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: infraType == InfraFilterType.all
                    ? null
                    : controller.setInfraName,
              ),
              const SizedBox(height: GssmsSpacing.s16),
              FilledButton(
                key: const Key('apply_filters_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.link,
                  padding: const EdgeInsets.symmetric(vertical: GssmsSpacing.s12),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkOrderCard extends StatelessWidget {
  const _WorkOrderCard({
    required this.workOrder,
    required this.onTap,
    this.session,
    this.onViewReport,
  });

  final WorkOrder workOrder;
  final VoidCallback onTap;
  final UserSession? session;

  /// Non-null only for an assigned technician on a reportable Job Work.
  final VoidCallback? onViewReport;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  String _formatTypeChip(WorkOrder wo) {
    switch (executionRouteFor(wo)) {
      case ExecutionRoute.complaint:
        return 'Breakdown';
      case ExecutionRoute.rectification:
        return 'Rectification';
      case ExecutionRoute.inspection:
        return 'Inspection';
      case ExecutionRoute.checklist:
        return wo.type == WorkOrderType.corrective ? 'Corrective' : 'Preventive';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final metaStyle = textTheme.bodySmall?.copyWith(color: tokens.textSecondary);

    final isBreakdown = executionRouteFor(workOrder) == ExecutionRoute.complaint;
    const terminalStatuses = {
      WorkOrderStatus.techCompleted,
      WorkOrderStatus.verified,
      WorkOrderStatus.closed,
      WorkOrderStatus.cancelled,
    };
    final isTerminal = terminalStatuses.contains(workOrder.status);

    // Overdue evaluated against today in IST (UTC+5:30)
    final nowIst = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final todayIst = DateTime(nowIst.year, nowIst.month, nowIst.day);
    final isDueDatePast = workOrder.dueDate != null && workOrder.dueDate!.isBefore(todayIst);
    final isOverdue = !isBreakdown && !isTerminal && (workOrder.isSlaAtRisk || isDueDatePast);

    // Location formatting: omit depot if single depot scope
    final isSingleDepot = session?.scope.level == OrgScopeLevel.depot ||
        (session?.depotId != null &&
            session?.scope.level != OrgScopeLevel.global &&
            session?.scope.level != OrgScopeLevel.zone &&
            session?.scope.level != OrgScopeLevel.division);

    final locationPrimary = workOrder.stationName ?? workOrder.infrastructureName;
    final location = isSingleDepot
        ? (locationPrimary ?? '')
        : [locationPrimary, workOrder.depotName]
            .where((s) => s != null && s.isNotEmpty)
            .join(' • ');

    return Card(
      key: Key('work_order_card_${workOrder.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // Left accent bar: Indicates overdue (danger) state only; neutral cards
        // have no accent border so the indicator has a single, unambiguous meaning.
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: isOverdue
                  ? BorderSide(color: tokens.danger.solid, width: 5)
                  : BorderSide.none,
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
                    StatusChip(label: _formatTypeChip(workOrder)),
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
                      _Meta(
                        icon: Icons.location_on_outlined,
                        text: location,
                        style: metaStyle,
                        maxLines: 2,
                      ),
                    if (workOrder.dueDate != null)
                      _Meta(
                        icon: Icons.event_outlined,
                        text: isOverdue
                            ? 'Overdue · due ${_dateFormat.format(workOrder.dueDate!)}'
                            : 'Due ${_dateFormat.format(workOrder.dueDate!)}',
                        style: isOverdue
                            ? metaStyle?.copyWith(
                                color: tokens.danger.foreground,
                                fontWeight: FontWeight.w600,
                              )
                            : metaStyle,
                      ),
                    if (workOrder.assignedToName != null &&
                        workOrder.assignedToName!.trim().isNotEmpty)
                      _Meta(
                        icon: Icons.person_outline,
                        text: workOrder.assignedToName!.trim(),
                        style: metaStyle?.copyWith(color: tokens.link),
                      )
                    else
                      _Meta(
                        icon: Icons.person_outline,
                        text: 'Unassigned',
                        style: metaStyle,
                      ),
                  ],
                ),
                if (onViewReport != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: Key('work_order_card_report_${workOrder.id}'),
                      onPressed: onViewReport,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('View Report'),
                    ),
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
  const _Meta({
    required this.icon,
    required this.text,
    this.style,
    this.maxLines = 1,
  });

  final IconData icon;
  final String text;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.only(top: maxLines > 1 ? 2.0 : 0.0),
          child: Icon(icon, size: 14, color: style?.color),
        ),
        const SizedBox(width: GssmsSpacing.s4),
        Flexible(
          child: Text(
            text,
            style: style,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

