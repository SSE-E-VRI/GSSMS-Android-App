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

  Future<void> _clearFilters() async {
    _searchController.clear();
    await _controller.clearFilters();
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
                  children: [
                    GssmsSearchField(
                      controller: _searchController,
                      hintText: 'Search by #, title, location, inspector…',
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
                    _StatusFilter(
                      state: loaded,
                      onChanged: _controller.setStatusFilter,
                    ),
                  ],
                ),
              ),
            ),
            if (loaded != null)
              SliverToBoxAdapter(
                child: ListResultHeader(
                  shown: loaded.filteredInspections.length,
                  total: loaded.inspections.length,
                  noun: 'inspections',
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

/// Status filter as a dropdown: a chip row clipped "Action Required" at 360dp.
class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.state, required this.onChanged});

  final InspectionListLoaded? state;
  final ValueChanged<InspectionStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = state;
    int countFor(InspectionStatus? status) {
      if (s == null) return 0;
      if (status == null) return s.inspections.length;
      return s.inspections.where((i) => i.status == status).length;
    }

    const statuses = [
      InspectionStatus.open,
      InspectionStatus.actionRequired,
      InspectionStatus.converted,
      InspectionStatus.closed,
    ];

    return DropdownButtonFormField<InspectionStatus?>(
      key: const Key('inspection_status_filter_dropdown'),
      isExpanded: true,
      value: s?.selectedStatus,
      decoration: const InputDecoration(
        labelText: 'Status',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: GssmsSpacing.s12,
          vertical: GssmsSpacing.s12,
        ),
      ),
      items: [
        DropdownMenuItem(
          value: null,
          child: Text('All (${countFor(null)})'),
        ),
        for (final status in statuses)
          DropdownMenuItem(
            value: status,
            child: Text(
              '${status == InspectionStatus.converted ? 'Converted' : status.displayName}'
              ' (${countFor(status)})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _InspectionCard extends StatelessWidget {
  const _InspectionCard({required this.inspection, required this.onTap});

  final Inspection inspection;
  final VoidCallback onTap;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final metaStyle = textTheme.bodySmall?.copyWith(color: tokens.textSecondary);
    final when = inspection.inspectionDate ?? inspection.createdAt;

    return Card(
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
                    InspectionStatusChip(inspection: inspection),
                  ],
                ),
              ),
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
                  if (inspection.createdByName != null)
                    _Meta(
                      icon: Icons.person_outline,
                      text: inspection.createdByName!,
                      style: metaStyle,
                    ),
                  if (when != null)
                    _Meta(
                      icon: Icons.schedule,
                      text: _dateFormat.format(when),
                      style: metaStyle,
                    ),
                ],
              ),
              if (inspection.isConverted) ...[
                const SizedBox(height: GssmsSpacing.s8),
                InspectionJobWorkChip(inspection: inspection),
              ],
            ],
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
