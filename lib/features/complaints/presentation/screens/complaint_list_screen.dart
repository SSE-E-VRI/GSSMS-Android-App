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
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)),
          'complaints.view')) {
        return;
      }
      ref.read(complaintListControllerProvider.notifier).fetchComplaints();
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
    final listState = ref.watch(complaintListControllerProvider);
    final session = sessionFromAuth(ref.watch(authControllerProvider));

    if (!sessionAllows(session, 'complaints.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Complaints & Issues')),
        body: const PermissionDeniedView(),
      );
    }

    final loaded = listState is ComplaintListLoaded ? listState : null;

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
              onChanged: (selection) {
                ref
                    .read(complaintListControllerProvider.notifier)
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
            .read(complaintListControllerProvider.notifier)
            .fetchComplaints(forceRefresh: true),
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
      // there is no "add" action, so `complaints.add` never appears in a real
      // JWT's permissions claim and this FAB was unconditionally hidden.
      floatingActionButton: sessionAllows(session, 'complaints.create')
              ? FloatingActionButton.extended(
                  key: const Key('fab_create_complaint'),
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('Log Complaint'),
                  backgroundColor: AppTheme.accentOrange,
                  foregroundColor: Colors.white,
                  onPressed: () async {
                    final created = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const ComplaintCreateScreen(),
                      ),
                    );
                    if (created == true && mounted) {
                      unawaited(ref
                          .read(complaintListControllerProvider.notifier)
                          .fetchComplaints(forceRefresh: true));
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
          hintText: 'Search by complaint #, asset, title...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    ref
                        .read(complaintListControllerProvider.notifier)
                        .setSearchQuery('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppTheme.backgroundLight,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (val) {
          ref
              .read(complaintListControllerProvider.notifier)
              .setSearchQuery(val);
        },
      ),
    );
  }


  Widget _buildDateRange(ComplaintListState state) {
    final loaded = state is ComplaintListLoaded ? state : null;
    return DateRangeFilterBar(
      from: loaded?.dateFrom,
      to: loaded?.dateTo,
      onChanged: (from, to) {
        ref
            .read(complaintListControllerProvider.notifier)
            .setDateRange(from, to);
      },
    );
  }

  /// Status filter as a dropdown rather than a row of FilterChips — same
  /// reasoning as WorkOrderListScreen's status/type dropdown pair: a chip
  /// row costs a dedicated horizontally-wrapping band of screen space for
  /// what's fundamentally a single-choice selection.
  Widget _buildFilterChips(ComplaintListState state) {
    final selected = state is ComplaintListLoaded ? state.selectedStatus : null;

    int countFor(ComplaintStatus? status) {
      if (state is! ComplaintListLoaded) return 0;
      if (status == null) return state.complaints.length;
      return state.complaints.where((c) => c.status == status).length;
    }

    final filterOptions = [
      (label: 'All (${countFor(null)})', status: null),
      (label: 'Open (${countFor(ComplaintStatus.open)})', status: ComplaintStatus.open),
      (label: 'Converted (${countFor(ComplaintStatus.converted)})', status: ComplaintStatus.converted),
      (label: 'Closed (${countFor(ComplaintStatus.closed)})', status: ComplaintStatus.closed),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: DropdownButtonFormField<ComplaintStatus?>(
        key: const Key('complaint_status_filter_dropdown'),
        isExpanded: true,
        value: selected,
        decoration: const InputDecoration(
          labelText: 'Status',
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(),
        ),
        items: filterOptions
            .map((opt) => DropdownMenuItem(
                value: opt.status,
                child: Text(opt.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13))))
            .toList(),
        onChanged: (status) {
          ref
              .read(complaintListControllerProvider.notifier)
              .setStatusFilter(status);
        },
      ),
    );
  }

  /// Slivers for the scrollable body below the filter block (see build()).
  /// One `RefreshIndicator` wraps the whole `CustomScrollView` — filters
  /// included — so none of these branches carry their own.
  List<Widget> _buildListSlivers(ComplaintListState state) {
    if (state is ComplaintListLoading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (state is ComplaintListError) {
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
                          .read(complaintListControllerProvider.notifier)
                          .fetchComplaints(forceRefresh: true),
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
                  const Icon(Icons.error_outline,
                      size: 48, color: AppTheme.errorRed),
                  const SizedBox(height: 12),
                  Text(state.message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref
                        .read(complaintListControllerProvider.notifier)
                        .fetchComplaints(forceRefresh: true),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
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
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('No complaints found matching criteria.')),
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
              return _ComplaintCard(complaint: complaints[i ~/ 2]);
            },
            childCount: complaints.length * 2 - 1,
          ),
        ),
      ),
    ];
  }
}

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({required this.complaint});

  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Card(
      key: Key('complaint_card_${complaint.id}'),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ComplaintDetailScreen(complaint: complaint),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    complaint.complaintNumber,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _getSeverityColor(complaint.severity)
                          .withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: _getSeverityColor(complaint.severity)),
                    ),
                    child: Text(
                      complaint.severity.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getSeverityColor(complaint.severity),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                complaint.title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (complaint.description != null &&
                  complaint.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  complaint.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
              const Divider(height: 16),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    complaint.stationName ??
                        complaint.depotName ??
                        'Location N/A',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  if (complaint.assetName != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.build_outlined,
                        size: 14, color: AppTheme.railwayBlue),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        complaint.assetName!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.railwayBlue,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              if (complaint.createdAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Reported: ${dateFormat.format(complaint.createdAt!)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getSeverityColor(ComplaintSeverity severity) {
    switch (severity) {
      case ComplaintSeverity.critical:
        return Colors.red.shade900;
      case ComplaintSeverity.high:
        return AppTheme.errorRed;
      case ComplaintSeverity.medium:
        return Colors.orange.shade700;
      case ComplaintSeverity.low:
        return Colors.green;
    }
  }
}
