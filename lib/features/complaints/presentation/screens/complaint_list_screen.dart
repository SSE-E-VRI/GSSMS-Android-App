import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/date_range_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_create_screen.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_detail_screen.dart';
import 'package:intl/intl.dart';

class ComplaintListScreen extends ConsumerStatefulWidget {
  const ComplaintListScreen({super.key});

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complaints & Issues'),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SyncStatusBadge(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(complaintListControllerProvider.notifier)
                .fetchComplaints(forceRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (session != null) _buildOrgScope(listState, session),
          _buildDateRange(listState),
          _buildFilterChips(listState),
          Expanded(child: _buildListBody(listState)),
        ],
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

  Widget _buildOrgScope(ComplaintListState state, UserSession session) {
    final loaded = state is ComplaintListLoaded ? state : null;
    return OrgScopeFilterBar(
      scope: session.scope,
      selection: loaded?.orgScope ?? OrgScopeSelection.empty,
      // ComplaintViewSet.get_queryset has no station-level filter.
      enableStation: false,
      onChanged: (selection) {
        ref
            .read(complaintListControllerProvider.notifier)
            .setOrgScope(selection);
      },
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

  Widget _buildFilterChips(ComplaintListState state) {
    final selected = state is ComplaintListLoaded ? state.selectedStatus : null;

    final filterOptions = [
      (label: 'All', status: null),
      (label: 'Open', status: ComplaintStatus.open),
      (label: 'In Progress', status: ComplaintStatus.inProgress),
      (label: 'Resolved', status: ComplaintStatus.resolved),
      (label: 'Closed', status: ComplaintStatus.closed),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filterOptions.map((opt) {
            final isSelected = selected == opt.status;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(
                  opt.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : AppTheme.railwayBlue,
                  ),
                ),
                selected: isSelected,
                selectedColor: AppTheme.railwayBlue,
                checkmarkColor: Colors.white,
                onSelected: (_) {
                  ref
                      .read(complaintListControllerProvider.notifier)
                      .setStatusFilter(opt.status);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildListBody(ComplaintListState state) {
    if (state is ComplaintListLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is ComplaintListError) {
      final previous = state.previousLoaded;
      if (previous != null) {
        return Column(
          children: [
            Material(
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
            Expanded(child: _buildLoadedList(previous)),
          ],
        );
      }
      return Center(
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
      );
    }

    if (state is ComplaintListLoaded) {
      return _buildLoadedList(state);
    }

    return const SizedBox.shrink();
  }

  Widget _buildLoadedList(ComplaintListLoaded state) {
    final complaints = state.filteredComplaints;

    if (complaints.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref
            .read(complaintListControllerProvider.notifier)
            .fetchComplaints(forceRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 100),
            Center(child: Text('No complaints found matching criteria.')),
          ],
        ),
      );
    }

      return RefreshIndicator(
        onRefresh: () => ref
            .read(complaintListControllerProvider.notifier)
            .fetchComplaints(forceRefresh: true),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          itemCount: complaints.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return _ComplaintCard(complaint: complaints[index]);
          },
        ),
      );
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
