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

  Future<void> _clearFilters() async {
    _searchController.clear();
    await _controller.clearFilters();
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(complaintListControllerProvider);
    final session = sessionFromAuth(ref.watch(authControllerProvider));

    if (!sessionAllows(session, 'complaints.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Complaints & Issues')),
        body: const PermissionDeniedView(),
      );
    }

    final loaded = listState is ComplaintListLoaded
        ? listState
        : (listState is ComplaintListError ? listState.previousLoaded : null);

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('Complaints & Issues'),
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
                  children: [
                    GssmsSearchField(
                      controller: _searchController,
                      hintText: 'Search by #, title, location, asset…',
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
                    _StatusFilter(state: loaded, onChanged: _controller.setStatusFilter),
                  ],
                ),
              ),
            ),
            if (loaded != null)
              SliverToBoxAdapter(
                child: ListResultHeader(
                  shown: loaded.filteredComplaints.length,
                  total: loaded.complaints.length,
                  noun: 'complaints',
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
              label: const Text('Log Complaint'),
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
            title: 'Could not load complaints',
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
                ? 'No complaints match these filters'
                : 'No complaints logged yet',
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
            (context, i) => _ComplaintCard(complaint: complaints[i]),
            childCount: complaints.length,
          ),
        ),
      ),
    ];
  }
}

/// Single-choice status filter as a dropdown (one row instead of a chip band).
class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.state, required this.onChanged});

  final ComplaintListLoaded? state;
  final ValueChanged<ComplaintStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = state;
    int countFor(ComplaintStatus? status) {
      if (s == null) return 0;
      if (status == null) return s.complaints.length;
      return s.complaints.where((c) => c.status == status).length;
    }

    final options = <(String, ComplaintStatus?)>[
      ('All (${countFor(null)})', null),
      for (final status in const [
        ComplaintStatus.open,
        ComplaintStatus.converted,
        ComplaintStatus.closed,
      ])
        ('${status.displayName} (${countFor(status)})', status),
    ];

    return DropdownButtonFormField<ComplaintStatus?>(
      key: const Key('complaint_status_filter_dropdown'),
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
        for (final (label, status) in options)
          DropdownMenuItem(
            value: status,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({required this.complaint});

  final Complaint complaint;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final metaStyle = textTheme.bodySmall?.copyWith(color: tokens.textSecondary);
    final location = complaint.locationLabel ?? complaint.depotName;

    return Card(
      key: Key('complaint_card_${complaint.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ComplaintDetailScreen(complaint: complaint),
            ),
          );
        },
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
                  if (complaint.createdAt != null)
                    _Meta(
                      icon: Icons.schedule,
                      text: _dateFormat.format(complaint.createdAt!.toLocal()),
                      style: metaStyle,
                    ),
                ],
              ),
              if (complaint.isConverted) ...[
                const SizedBox(height: GssmsSpacing.s8),
                ComplaintJobWorkChip(complaint: complaint),
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
