import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/date_range_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_create_screen.dart';
import 'package:intl/intl.dart';

class InspectionListScreen extends ConsumerStatefulWidget {
  const InspectionListScreen({super.key});

  @override
  ConsumerState<InspectionListScreen> createState() => _InspectionListScreenState();
}

class _InspectionListScreenState extends ConsumerState<InspectionListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(inspectionListControllerProvider.notifier).fetchInspections();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(inspectionListControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final session = authState is Authenticated ? authState.session : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Inspections'),
        actions: [
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: SyncStatusBadge()),
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.read(inspectionListControllerProvider.notifier).fetchInspections(forceRefresh: true)),
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
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab_create_inspection'),
        icon: const Icon(Icons.add_task_outlined),
        label: const Text('Log Inspection'),
        backgroundColor: AppTheme.railwayBlue,
        foregroundColor: Colors.white,
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const InspectionCreateScreen()));
          if (created == true && mounted) {
            unawaited(ref.read(inspectionListControllerProvider.notifier).fetchInspections(forceRefresh: true));
          }
        },
      ),
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
              ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); ref.read(inspectionListControllerProvider.notifier).setSearchQuery(''); })
              : null,
          filled: true,
          fillColor: AppTheme.backgroundLight,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        ),
        onChanged: (val) => ref.read(inspectionListControllerProvider.notifier).setSearchQuery(val),
      ),
    );
  }

  Widget _buildOrgScope(InspectionListState state, UserSession session) {
    final loaded = state is InspectionListLoaded ? state : null;
    return OrgScopeFilterBar(
      scope: session.scope,
      selection: loaded?.orgScope ?? OrgScopeSelection.empty,
      // InspectionViewSet.get_queryset has no station-level filter.
      enableStation: false,
      onChanged: (selection) {
        ref.read(inspectionListControllerProvider.notifier).setOrgScope(selection);
      },
    );
  }

  Widget _buildDateRange(InspectionListState state) {
    final loaded = state is InspectionListLoaded ? state : null;
    return DateRangeFilterBar(
      from: loaded?.dateFrom,
      to: loaded?.dateTo,
      onChanged: (from, to) {
        ref.read(inspectionListControllerProvider.notifier).setDateRange(from, to);
      },
    );
  }

  Widget _buildFilterChips(InspectionListState state) {
    final selected = state is InspectionListLoaded ? state.selectedStatus : null;
    final options = [
      (label: 'All', status: null),
      (label: 'Pending', status: InspectionStatus.pending),
      (label: 'In Progress', status: InspectionStatus.inProgress),
      (label: 'Completed', status: InspectionStatus.completed),
      (label: 'Converted', status: InspectionStatus.converted),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: options.map((opt) {
            final isSelected = selected == opt.status;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(opt.label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : AppTheme.railwayBlue)),
                selected: isSelected,
                selectedColor: AppTheme.railwayBlue,
                checkmarkColor: Colors.white,
                onSelected: (_) => ref.read(inspectionListControllerProvider.notifier).setStatusFilter(opt.status),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildListBody(InspectionListState state) {
    if (state is InspectionListLoading) return const Center(child: CircularProgressIndicator());
    if (state is InspectionListError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.errorRed),
            const SizedBox(height: 12),
            Text(state.message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => ref.read(inspectionListControllerProvider.notifier).fetchInspections(forceRefresh: true), child: const Text('Retry')),
          ]),
        ),
      );
    }
    if (state is InspectionListLoaded) {
      final inspections = state.filteredInspections;
      if (inspections.isEmpty) return const Center(child: Text('No inspections found matching criteria.'));
      return RefreshIndicator(
        onRefresh: () => ref.read(inspectionListControllerProvider.notifier).fetchInspections(forceRefresh: true),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          itemCount: inspections.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _InspectionCard(inspection: inspections[index]),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _InspectionCard extends StatelessWidget {
  const _InspectionCard({required this.inspection});
  final Inspection inspection;

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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(inspection.inspectionNumber, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: priorityColor(inspection.priority).withOpacity(0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: priorityColor(inspection.priority))),
                child: Text(inspection.priority.displayName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: priorityColor(inspection.priority))),
              ),
            ]),
            const SizedBox(height: 6),
            Text(inspection.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (inspection.description != null && inspection.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(inspection.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ],
            const Divider(height: 16),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text(inspection.stationName ?? inspection.depotName ?? 'Location N/A', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              if (inspection.assetName != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.build_outlined, size: 14, color: AppTheme.railwayBlue),
                const SizedBox(width: 4),
                Expanded(child: Text(inspection.assetName!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.railwayBlue), overflow: TextOverflow.ellipsis)),
              ],
            ]),
            if (inspection.createdAt != null) ...[
              const SizedBox(height: 4),
              Text('Reported: ${dateFormat.format(inspection.createdAt!)}', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
              child: Text(inspection.status.displayName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
            ),
          ],
        ),
      ),
    );
  }
}
