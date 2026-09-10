import 'dart:async';
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
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)),
          'inspections.view')) {
        return;
      }
      ref.read(inspectionListControllerProvider.notifier).fetchInspections();
    });
  }

  void _onSearchTextChanged() {
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
    final listState = ref.watch(inspectionListControllerProvider);
    final session = sessionFromAuth(ref.watch(authControllerProvider));

    if (!sessionAllows(session, 'inspections.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inspections')),
        body: const PermissionDeniedView(),
      );
    }

    final loaded = listState is InspectionListLoaded ? listState : null;

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
              onChanged: (selection) {
                ref
                    .read(inspectionListControllerProvider.notifier)
                    .setOrgScope(selection);
              },
            ),
        ],
      ),
      // Filters are leading slivers ahead of the card list, not a fixed
      // Column above it, so the whole filter block (search/date/status)
      // scrolls away with the list instead of permanently eating screen
      // space — same change as WorkOrderListScreen.
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(inspectionListControllerProvider.notifier)
            .fetchInspections(forceRefresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SyncStatusBadge()),
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: _buildDateRange(listState)),
            SliverToBoxAdapter(child: _buildFilterChips(listState)),
            ..._buildListSlivers(listState),
          ],
        ),
      ),
      // rbac/registry.py MODULES builds every permission code as
      // `{module}.{action}` from CRUD = ["view", "create", "edit", "delete"] —
      // there is no "add" action, so `inspections.add` never appears in a real
      // JWT's permissions claim and this FAB was unconditionally hidden.
      floatingActionButton: sessionAllows(session, 'inspections.create')
              ? FloatingActionButton.extended(
                  key: const Key('fab_create_inspection'),
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('Log Inspection'),
                  backgroundColor: AppTheme.railwayBlue,
                  foregroundColor: Colors.white,
                  onPressed: () async {
                    final created = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                            builder: (_) => const InspectionCreateScreen()));
                    if (created == true && mounted) {
                      unawaited(ref
                          .read(inspectionListControllerProvider.notifier)
                          .fetchInspections(forceRefresh: true));
                    }
                  },
                )
              : null,
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by inspection #, asset, title...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    ref
                        .read(inspectionListControllerProvider.notifier)
                        .setSearchQuery('');
                  })
              : null,
          filled: true,
          fillColor: AppTheme.backgroundLight,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
        ),
        onChanged: (val) => ref
            .read(inspectionListControllerProvider.notifier)
            .setSearchQuery(val),
      ),
    );
  }


  Widget _buildDateRange(InspectionListState state) {
    final loaded = state is InspectionListLoaded ? state : null;
    return DateRangeFilterBar(
      from: loaded?.dateFrom,
      to: loaded?.dateTo,
      onChanged: (from, to) {
        ref
            .read(inspectionListControllerProvider.notifier)
            .setDateRange(from, to);
      },
    );
  }

  /// Status filter as a dropdown rather than a row of FilterChips — same
  /// reasoning as WorkOrderListScreen's status/type dropdown pair: a chip
  /// row costs a dedicated horizontally-scrolling band of screen space for
  /// what's fundamentally a single-choice selection (and "Action Required"
  /// was the one that routinely got clipped/scrolled off at 360dp).
  Widget _buildFilterChips(InspectionListState state) {
    final selected =
        state is InspectionListLoaded ? state.selectedStatus : null;
    final options = [
      (label: 'All', status: null),
      (label: 'Open', status: InspectionStatus.open),
      (label: 'Action Required', status: InspectionStatus.actionRequired),
      (label: 'Converted', status: InspectionStatus.converted),
      (label: 'Closed', status: InspectionStatus.closed),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: DropdownButtonFormField<InspectionStatus?>(
        key: const Key('inspection_status_filter_dropdown'),
        isExpanded: true,
        value: selected,
        decoration: const InputDecoration(
          labelText: 'Status',
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(),
        ),
        items: options
            .map((opt) => DropdownMenuItem(
                value: opt.status,
                child: Text(opt.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13))))
            .toList(),
        onChanged: (status) => ref
            .read(inspectionListControllerProvider.notifier)
            .setStatusFilter(status),
      ),
    );
  }

  /// Slivers for the scrollable body below the filter block (see build()).
  /// One `RefreshIndicator` wraps the whole `CustomScrollView` — filters
  /// included — so none of these branches carry their own.
  List<Widget> _buildListSlivers(InspectionListState state) {
    if (state is InspectionListLoading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (state is InspectionListError) {
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
                          .read(inspectionListControllerProvider.notifier)
                          .fetchInspections(forceRefresh: true),
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
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.error_outline, size: 48, color: AppTheme.errorRed),
                const SizedBox(height: 12),
                Text(state.message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                    onPressed: () => ref
                        .read(inspectionListControllerProvider.notifier)
                        .fetchInspections(forceRefresh: true),
                    child: const Text('Retry')),
              ]),
            ),
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
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('No inspections found matching criteria.')),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              // Odd indices are the 12px separators between cards — same
              // spacing the old ListView.separated used.
              if (i.isOdd) return const SizedBox(height: 12);
              final index = i ~/ 2;
              return _InspectionCard(
                inspection: inspections[index],
                onTap: () async {
                  // The detail screen stays open after a successful convert
                  // (so its own "View Linked Job Work" link is reachable)
                  // rather than popping with a result, so refresh
                  // unconditionally whenever the user comes back — cheap,
                  // and the alternative is plumbing a return value through
                  // the screen's back button too.
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => InspectionDetailScreen(
                          inspection: inspections[index]),
                    ),
                  );
                  if (mounted) {
                    unawaited(ref
                        .read(inspectionListControllerProvider.notifier)
                        .fetchInspections(forceRefresh: true));
                  }
                },
              );
            },
            childCount: inspections.length * 2 - 1,
          ),
        ),
      ),
    ];
  }
}

class _InspectionCard extends StatelessWidget {
  const _InspectionCard({required this.inspection, required this.onTap});
  final Inspection inspection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    Color priorityColor(InspectionPriority p) {
      switch (p) {
        case InspectionPriority.critical:
          return Colors.red.shade900;
        case InspectionPriority.high:
          return AppTheme.errorRed;
        case InspectionPriority.medium:
          return Colors.orange.shade700;
        case InspectionPriority.low:
          return Colors.green;
      }
    }

    return Card(
      key: Key('inspection_card_${inspection.id}'),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(inspection.inspectionNumber,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color:
                          priorityColor(inspection.priority).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: priorityColor(inspection.priority))),
                  child: Text(inspection.priority.displayName,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: priorityColor(inspection.priority))),
                ),
              ]),
              const SizedBox(height: 6),
              Text(inspection.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              if (inspection.notes != null &&
                  inspection.notes!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(inspection.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary)),
              ],
              const Divider(height: 16),
              Row(children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                    inspection.stationName ??
                        inspection.depotName ??
                        'Location N/A',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                if (inspection.assetName != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.build_outlined,
                      size: 14, color: AppTheme.railwayBlue),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(inspection.assetName!,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.railwayBlue),
                          overflow: TextOverflow.ellipsis)),
                ],
              ]),
              if (inspection.createdAt != null) ...[
                const SizedBox(height: 4),
                Text('Reported: ${dateFormat.format(inspection.createdAt!)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              ],
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4)),
                child: Text(inspection.status.displayName,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
