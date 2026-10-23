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
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/complaint_status_style.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_create_screen.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_detail_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/linked_job_work_line.dart';
import 'package:intl/intl.dart';

class ComplaintListScreen extends ConsumerStatefulWidget {
  const ComplaintListScreen({
    super.key,
    this.isEmbedded = false,
  });

  final bool isEmbedded;

  @override
  ConsumerState<ComplaintListScreen> createState() =>
      _ComplaintListScreenState();
}

class _ComplaintListScreenState extends ConsumerState<ComplaintListScreen> {
  final TextEditingController _searchController = TextEditingController();

  ComplaintListController get _controller =>
      ref.read(complaintListControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)),
          'complaints.view')) {
        return;
      }
      final current = ref.read(complaintListControllerProvider);
      if (current is ComplaintListLoaded) {
        _searchController.text = current.searchQuery;
      }
      _controller.fetchComplaints();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _hasActiveFilters(ComplaintListLoaded? s) =>
      s != null &&
      (s.selectedStatus != null ||
          s.searchQuery.isNotEmpty ||
          s.dateFrom != null ||
          s.dateTo != null);

  static int _activeFilterCount(ComplaintListLoaded? s) {
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

  void _openFilterSheet(BuildContext context, ComplaintListLoaded? loaded) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ComplaintFilterSheet(
        state: loaded,
        controller: _controller,
        onClearAll: _clearFilters,
      ),
    );
  }

  Future<void> _open(Complaint complaint) async {
    // The detail screen stays open after a successful convert (so its "View
    // Linked Job Work" link is reachable), so refresh whenever the user comes
    // back rather than plumbing a result through the back button.
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ComplaintDetailScreen(complaint: complaint),
      ),
    );
    if (mounted) unawaited(_controller.fetchComplaints(forceRefresh: true));
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(complaintListControllerProvider);
    final session = sessionFromAuth(ref.watch(authControllerProvider));

    if (!sessionAllows(session, 'complaints.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Breakdowns')),
        body: const PermissionDeniedView(),
      );
    }

    final loaded = listState is ComplaintListLoaded
        ? listState
        : (listState is ComplaintListError ? listState.previousLoaded : null);
    final filterCount = _activeFilterCount(loaded);

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('Breakdowns'),
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
      // Filters are leading slivers so the whole filter block scrolls away
      // with the list instead of permanently eating screen space.
      body: RefreshIndicator(
        onRefresh: () => _controller.fetchComplaints(forceRefresh: true),
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
                        _ComplaintFiltersButton(
                          activeCount: filterCount,
                          onPressed: () => _openFilterSheet(context, loaded),
                        ),
                      ],
                    ),
                    if (loaded != null && filterCount > 0) ...[
                      const SizedBox(height: GssmsSpacing.s8),
                      _ComplaintActiveFilterChips(
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
                  shown: loaded.filteredComplaints.length,
                  total: loaded.complaints.length,
                  noun: 'Breakdowns',
                  nounSingular: 'Breakdown',
                  onClearFilters: _hasActiveFilters(loaded) ? _clearFilters : null,
                ),
              ),
            ..._buildListSlivers(listState),
          ],
        ),
      ),
      // rbac/registry.py MODULES builds every permission code as
      // `{module}.{action}` from CRUD = ["view", "create", "edit", "delete"].
      floatingActionButton: sessionAllows(session, 'complaints.create')
          ? FloatingActionButton.extended(
              key: const Key('fab_create_complaint'),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Report Breakdown'),
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const ComplaintCreateScreen(),
                  ),
                );
                if (created == true && mounted) {
                  unawaited(_controller.fetchComplaints(forceRefresh: true));
                }
              },
            )
          : null,
    );
  }

  List<Widget> _buildListSlivers(ComplaintListState state) {
    if (state is ComplaintListInitial || state is ComplaintListLoading) {
      return const [SliverSkeletonList()];
    }

    if (state is ComplaintListError) {
      final previous = state.previousLoaded;
      if (previous != null) {
        return [
          SliverToBoxAdapter(
            child: ErrorBanner(
              message: state.message,
              onRetry: () => _controller.fetchComplaints(forceRefresh: true),
            ),
          ),
          ..._buildLoadedSlivers(previous),
        ];
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateView.error(
            title: 'Could not load breakdowns',
            message: state.message,
            onRetry: () => _controller.fetchComplaints(forceRefresh: true),
          ),
        ),
      ];
    }

    if (state is ComplaintListLoaded) {
      return _buildLoadedSlivers(state);
    }

    return const [SliverToBoxAdapter(child: SizedBox.shrink())];
  }

  List<Widget> _buildLoadedSlivers(ComplaintListLoaded state) {
    final complaints = state.filteredComplaints;

    if (complaints.isEmpty) {
      final filtered = _hasActiveFilters(state);
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateView.noResults(
            title: filtered
                ? 'No breakdowns match these filters'
                : 'No breakdowns reported yet',
            icon: Icons.report_problem_outlined,
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
            (context, i) => _ComplaintCard(
              complaint: complaints[i],
              onTap: () => _open(complaints[i]),
            ),
            childCount: complaints.length,
          ),
        ),
      ),
    ];
  }
}

class _ComplaintFiltersButton extends StatelessWidget {
  const _ComplaintFiltersButton({
    required this.activeCount,
    required this.onPressed,
  });

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final button = OutlinedButton.icon(
      key: const Key('complaint_filters_button'),
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
      key: const Key('complaint_filters_badge'),
      label: Text('$activeCount'),
      backgroundColor: tokens.link,
      child: button,
    );
  }
}

class _ComplaintActiveFilterChips extends StatelessWidget {
  const _ComplaintActiveFilterChips({
    required this.state,
    required this.controller,
    required this.onClearAll,
  });

  final ComplaintListLoaded state;
  final ComplaintListController controller;
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
          key: const Key('chip_complaint_date_range'),
          label: Text(dateLabel),
          onDeleted: () => controller.setDateRange(null, null),
        ),
      );
    }

    if (state.selectedStatus != null) {
      chips.add(
        InputChip(
          key: const Key('chip_complaint_status'),
          label: Text('Status: ${state.selectedStatus!.displayName}'),
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
          key: const Key('clear_all_complaint_filters_button'),
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

class _ComplaintFilterSheet extends StatelessWidget {
  const _ComplaintFilterSheet({
    required this.state,
    required this.controller,
    required this.onClearAll,
  });

  final ComplaintListLoaded? state;
  final ComplaintListController controller;
  final VoidCallback onClearAll;

  static const _statuses = [
    ComplaintStatus.open,
    ComplaintStatus.converted,
    ComplaintStatus.closed,
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
              DropdownButtonFormField<ComplaintStatus?>(
                key: const Key('complaint_status_filter_dropdown'),
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
                        status.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: controller.setStatusFilter,
              ),
              const SizedBox(height: GssmsSpacing.s16),
              FilledButton(
                key: const Key('apply_complaint_filters_button'),
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

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({required this.complaint, required this.onTap});

  final Complaint complaint;
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
    final location = complaint.locationLabel ?? complaint.depotName;

    final semanticsLabel = [
      'Breakdown ${complaint.reference}',
      'status: ${complaint.status.displayName}',
      if (location != null && location.isNotEmpty) location,
      complaint.title,
      if (complaint.complainantName != null &&
          complaint.complainantName!.trim().isNotEmpty)
        'reported by ${complaint.complainantName!.trim()}',
      if (complaint.createdAt != null) _formatWhen(complaint.createdAt!),
    ].join(', ');

    return Semantics(
      container: true,
      button: true,
      onTap: onTap,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Card(
      key: Key('complaint_card_${complaint.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(GssmsSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // spaceBetween keeps the status chip right-aligned; it wraps
              // under the reference instead of truncating at large text sizes.
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: GssmsSpacing.s8,
                  runSpacing: GssmsSpacing.s4,
                  children: [
                    Text(
                      complaint.reference,
                      style: textTheme.labelMedium?.copyWith(color: tokens.link),
                    ),
                    ComplaintStatusChip(complaint: complaint),
                  ],
                ),
              ),
              const SizedBox(height: GssmsSpacing.s8),
              Text(
                complaint.title,
                style: textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (complaint.description != null &&
                  complaint.description!.isNotEmpty) ...[
                const SizedBox(height: GssmsSpacing.s4),
                Text(
                  complaint.description!,
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
                    text: location ?? 'Location not set',
                    style: metaStyle,
                  ),
                  if (complaint.assetUniqueId != null)
                    _Meta(
                      icon: Icons.precision_manufacturing_outlined,
                      text: complaint.assetUniqueId!,
                      style: metaStyle?.copyWith(
                        color: tokens.link,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (complaint.complainantName != null &&
                      complaint.complainantName!.trim().isNotEmpty)
                    _Meta(
                      icon: Icons.person_outline,
                      text: complaint.complainantName!.trim(),
                      style: metaStyle,
                    ),
                  if (complaint.createdAt != null)
                    _Meta(
                      icon: Icons.schedule,
                      text: _formatWhen(complaint.createdAt!),
                      style: metaStyle,
                    ),
                ],
              ),
              if (complaint.isConverted && complaint.workOrderId != null) ...[
                const SizedBox(height: GssmsSpacing.s8),
                LinkedJobWorkLine(
                  workOrderId: complaint.workOrderId!,
                  ticketNumber: complaint.workOrderTicketNumber,
                  workOrderStatus: complaint.workOrderStatus,
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
