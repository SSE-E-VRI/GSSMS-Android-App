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
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:gssms_mobile/features/inspections/presentation/inspection_status_style.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_create_screen.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_detail_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/linked_job_work_line.dart';
import 'package:intl/intl.dart';

class InspectionListScreen extends ConsumerStatefulWidget {
  const InspectionListScreen({
    super.key,
    this.isEmbedded = false,
  });

  final bool isEmbedded;

  @override
  ConsumerState<InspectionListScreen> createState() =>
      _InspectionListScreenState();
}

class _InspectionListScreenState extends ConsumerState<InspectionListScreen> {
  final TextEditingController _searchController = TextEditingController();

  InspectionListController get _controller =>
      ref.read(inspectionListControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)),
          'inspections.view')) {
        return;
      }
      final current = ref.read(inspectionListControllerProvider);
      if (current is InspectionListLoaded) {
        _searchController.text = current.searchQuery;
      }
      _controller.fetchInspections();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _hasActiveFilters(InspectionListLoaded? s) =>
      s != null &&
      (s.selectedStatus != null ||
          s.searchQuery.isNotEmpty ||
          s.dateFrom != null ||
          s.dateTo != null);

  static int _activeFilterCount(InspectionListLoaded? s) {
    if (s == null) return 0;
    var count = 0;
    if (s.dateFrom != null || s.dateTo != null) count++;
    if (s.selectedStatus != null) count++;
    return count;
  }

  Future<void> _clearFilters() async {
    _searchController.clear();
    await _controller.clearFilters();
  }

  void _openFilterSheet(BuildContext context, InspectionListLoaded? loaded) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InspectionFilterSheet(
        state: loaded,
        controller: _controller,
        onClearAll: _clearFilters,
      ),
    );
  }

  Future<void> _open(Inspection inspection) async {
    // The detail screen stays open after a successful convert (so its "View
    // Linked Job Work" link is reachable), so refresh whenever the user comes
    // back rather than plumbing a result through the back button.
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InspectionDetailScreen(inspection: inspection),
      ),
    );
    if (mounted) unawaited(_controller.fetchInspections(forceRefresh: true));
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(inspectionListControllerProvider);
    final session = sessionFromAuth(ref.watch(authControllerProvider));

    if (!sessionAllows(session, 'inspections.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inspections')),
        body: const PermissionDeniedView(),
      );
    }

    final loaded = listState is InspectionListLoaded
        ? listState
        : (listState is InspectionListError ? listState.previousLoaded : null);
    final filterCount = _activeFilterCount(loaded);

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('Inspections'),
              actions: [
                if (session != null)
                  OrgScopeAppBarFilter(
                    scope: session.scope,
                    selection: loaded?.orgScope ?? OrgScopeSelection.empty,
                    enableStation: false,
                    onChanged: _controller.setOrgScope,
                  ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: () => _controller.fetchInspections(forceRefresh: true),
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
                            hintText: 'Search number, title, place',
                            onChanged: _controller.setSearchQuery,
                          ),
                        ),
                        const SizedBox(width: GssmsSpacing.s8),
                        _InspectionFiltersButton(
                          activeCount: filterCount,
                          onPressed: () => _openFilterSheet(context, loaded),
                        ),
                      ],
                    ),
                    if (loaded != null && filterCount > 0) ...[
                      const SizedBox(height: GssmsSpacing.s8),
                      _InspectionActiveFilterChips(
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
                  shown: loaded.filteredInspections.length,
                  total: loaded.inspections.length,
                  noun: 'Inspections',
                  nounSingular: 'Inspection',
                  onClearFilters: _hasActiveFilters(loaded) ? _clearFilters : null,
                ),
              ),
            ..._buildListSlivers(listState),
          ],
        ),
      ),
      // rbac/registry.py builds permission codes from CRUD actions — there is
      // no "add" action, so the FAB is gated on `inspections.create`.
      floatingActionButton: sessionAllows(session, 'inspections.create')
          ? FloatingActionButton.extended(
              key: const Key('fab_create_inspection'),
              icon: const Icon(Icons.add_task_outlined),
              label: const Text('Log Inspection'),
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                        builder: (_) => const InspectionCreateScreen()));
                if (created == true && mounted) {
                  unawaited(_controller.fetchInspections(forceRefresh: true));
                }
              },
            )
          : null,
    );
  }

  List<Widget> _buildListSlivers(InspectionListState state) {
    if (state is InspectionListInitial || state is InspectionListLoading) {
      return const [SliverSkeletonList()];
    }
    if (state is InspectionListError) {
      final previous = state.previousLoaded;
      if (previous != null) {
        return [
          SliverToBoxAdapter(
            child: ErrorBanner(
              message: state.message,
              onRetry: () => _controller.fetchInspections(forceRefresh: true),
            ),
          ),
          ..._buildLoadedSlivers(previous),
        ];
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateView.error(
            title: 'Could not load inspections',
            message: state.message,
            onRetry: () => _controller.fetchInspections(forceRefresh: true),
          ),
        ),
      ];
    }
    if (state is InspectionListLoaded) {
      return _buildLoadedSlivers(state);
    }
    return const [SliverToBoxAdapter(child: SizedBox.shrink())];
  }

  List<Widget> _buildLoadedSlivers(InspectionListLoaded state) {
    final inspections = state.filteredInspections;
    if (inspections.isEmpty) {
      final filtered = _hasActiveFilters(state);
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateView.noResults(
            title: filtered
                ? 'No inspections match these filters'
                : 'No inspections logged yet',
            icon: Icons.fact_check_outlined,
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
            (context, i) => _InspectionCard(
              inspection: inspections[i],
              onTap: () => _open(inspections[i]),
            ),
            childCount: inspections.length,
          ),
        ),
      ),
    ];
  }
}

class _InspectionFiltersButton extends StatelessWidget {
  const _InspectionFiltersButton({
    required this.activeCount,
    required this.onPressed,
  });

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final button = OutlinedButton.icon(
      key: const Key('inspection_filters_button'),
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
      key: const Key('inspection_filters_badge'),
      label: Text('$activeCount'),
      backgroundColor: tokens.link,
      child: button,
    );
  }
}

class _InspectionActiveFilterChips extends StatelessWidget {
  const _InspectionActiveFilterChips({
    required this.state,
    required this.controller,
    required this.onClearAll,
  });

  final InspectionListLoaded state;
  final InspectionListController controller;
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
          key: const Key('chip_inspection_date_range'),
          label: Text(dateLabel),
          onDeleted: () => controller.setDateRange(null, null),
        ),
      );
    }

    if (state.selectedStatus != null) {
      final status = state.selectedStatus!;
      final label = status == InspectionStatus.converted
          ? 'Converted'
          : status.displayName;
      chips.add(
        InputChip(
          key: const Key('chip_inspection_status'),
          label: Text('Status: $label'),
          onDeleted: () => controller.setStatusFilter(null),
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
          key: const Key('clear_all_inspection_filters_button'),
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

class _InspectionFilterSheet extends StatelessWidget {
  const _InspectionFilterSheet({
    required this.state,
    required this.controller,
    required this.onClearAll,
  });

  final InspectionListLoaded? state;
  final InspectionListController controller;
  final VoidCallback onClearAll;

  static const _statuses = [
    InspectionStatus.open,
    InspectionStatus.actionRequired,
    InspectionStatus.converted,
    InspectionStatus.closed,
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;

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
                from: state?.dateFrom,
                to: state?.dateTo,
                padding: EdgeInsets.zero,
                onChanged: controller.setDateRange,
              ),
              const SizedBox(height: GssmsSpacing.s12),
              DropdownButtonFormField<InspectionStatus?>(
                key: const Key('inspection_status_filter_dropdown'),
                isExpanded: true,
                initialValue: state?.selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: GssmsSpacing.s12,
                    vertical: GssmsSpacing.s12,
                  ),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  for (final status in _statuses)
                    DropdownMenuItem(
                      value: status,
                      child: Text(
                        status == InspectionStatus.converted
                            ? 'Converted'
                            : status.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: controller.setStatusFilter,
              ),
              const SizedBox(height: GssmsSpacing.s16),
              FilledButton(
                key: const Key('apply_inspection_filters_button'),
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

class _InspectionCard extends StatelessWidget {
  const _InspectionCard({required this.inspection, required this.onTap});

  final Inspection inspection;
  final VoidCallback onTap;

  static final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat _dateOnlyFormat = DateFormat('dd MMM yyyy');

  static String _formatWhen(DateTime when) {
    final local = when.toLocal();
    if (local.hour == 0 && local.minute == 0 && local.second == 0) {
      return _dateOnlyFormat.format(local);
    }
    return _dateTimeFormat.format(local);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final metaStyle = textTheme.bodySmall?.copyWith(color: tokens.textSecondary);
    final when = inspection.inspectionDate ?? inspection.createdAt;
    final linkedJobWork = inspection.jobWorks.firstOrNull;
    final effectiveWorkOrderId = inspection.workOrderId ?? linkedJobWork?.id;
    final effectiveTicketNumber = linkedJobWork?.ticketNumber;
    final location = inspection.locationLabel ?? inspection.depotName;

    final semanticsLabel = [
      'Inspection ${inspection.reference}',
      'status: ${inspection.status.displayName}',
      if (inspection.pointsCount > 0) '${inspection.pointsCount} points',
      if (location != null && location.isNotEmpty) location,
      inspection.title,
      if (inspection.createdByName != null &&
          inspection.createdByName!.trim().isNotEmpty)
        'created by ${inspection.createdByName!.trim()}',
      if (when != null) _formatWhen(when),
    ].join(', ');

    return Semantics(
      container: true,
      button: true,
      onTap: onTap,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Card(
      key: Key('inspection_card_${inspection.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(GssmsSpacing.s16),
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
                      inspection.reference,
                      style: textTheme.labelMedium?.copyWith(color: tokens.link),
                    ),
                    if (inspection.pointsCount > 0)
                      InspectionPointsBadge(inspection: inspection),
                  ],
                ),
              ),
              const SizedBox(height: GssmsSpacing.s4),
              InspectionStatusChip(inspection: inspection),
              const SizedBox(height: GssmsSpacing.s8),
              Text(
                inspection.title,
                style: textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (inspection.notes != null && inspection.notes!.isNotEmpty) ...[
                const SizedBox(height: GssmsSpacing.s4),
                Text(
                  inspection.notes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
                ),
              ],
              const SizedBox(height: GssmsSpacing.s12),
              Wrap(
                spacing: GssmsSpacing.s16,
                runSpacing: GssmsSpacing.s4,
                children: [
                  _Meta(
                    icon: Icons.location_on_outlined,
                    text: inspection.locationLabel ??
                        inspection.depotName ??
                        'Location not set',
                    style: metaStyle,
                  ),
                  if (inspection.createdByName != null &&
                      inspection.createdByName!.trim().isNotEmpty)
                    _Meta(
                      icon: Icons.person_outline,
                      text: inspection.createdByName!.trim(),
                      style: metaStyle,
                    ),
                  if (when != null)
                    _Meta(
                      icon: Icons.schedule,
                      text: _formatWhen(when),
                      style: metaStyle,
                    ),
                ],
              ),
              if ((inspection.isConverted || inspection.jobWorks.isNotEmpty) &&
                  effectiveWorkOrderId != null) ...[
                const SizedBox(height: GssmsSpacing.s8),
                LinkedJobWorkLine(
                  workOrderId: effectiveWorkOrderId,
                  ticketNumber: effectiveTicketNumber,
                  workOrderStatus: inspection.workOrderStatus ?? linkedJobWork?.status,
                ),
              ],
            ],
          ),
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
        Flexible(
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
