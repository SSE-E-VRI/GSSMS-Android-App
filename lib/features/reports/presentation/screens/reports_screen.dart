import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/date_range_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/domain/models/maintenance_register_entry.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_state.dart';
import 'package:gssms_mobile/features/reports/presentation/screens/register_entry_detail_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)), 'reports.view')) {
        return;
      }
      ref.read(reportsControllerProvider.notifier).loadRegister();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportsControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final session = sessionFromAuth(authState);

    if (!sessionAllows(session, 'reports.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports & Audit')),
        body: const PermissionDeniedView(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Audit'),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SyncStatusBadge(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(reportsControllerProvider.notifier).loadRegister(),
          ),
        ],
      ),
      body: _buildBody(state, session),
    );
  }

  Widget _buildBody(ReportsState state, UserSession? session) {
    if (state is ReportsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is ReportsError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.errorRed),
              const SizedBox(height: 12),
              Text(
                state.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(reportsControllerProvider.notifier).loadRegister(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is ReportsLoaded) {
      final entries = state.entries;

      return Column(
        children: [
          if (session != null) _buildOrgScope(state, session),
          _buildFilters(state),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No maintenance register entries found for selected date range.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _buildRegisterCard(entry, index + 1);
                    },
                  ),
          ),
        ],
      );
    }

    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildOrgScope(ReportsLoaded state, UserSession session) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: OrgScopeFilterBar(
        scope: session.scope,
        selection: state.orgScope,
        padding: EdgeInsets.zero,
        // register_report has no zone/division param, and station-level
        // narrowing is already covered by the Infrastructure Type/Item
        // filter below (Type=Station + item) — so only Depot is offered here.
        enableZoneDivision: false,
        enableStation: false,
        onChanged: (selection) {
          ref.read(reportsControllerProvider.notifier).setOrgScope(selection);
        },
      ),
    );
  }

  Widget _buildFilters(ReportsLoaded state) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<InfraFilterType>(
                  key: const Key('reports_infra_type'),
                  isExpanded: true,
                  isDense: true,
                  value: state.infraType,
                  decoration: const InputDecoration(
                    labelText: 'Infrastructure Type',
                    isDense: true,
                  ),
                  items: InfraFilterType.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.label, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (type) {
                    if (type == null) return;
                    ref.read(reportsControllerProvider.notifier).setInfraType(type);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const Key('reports_infra_item'),
                  isExpanded: true,
                  isDense: true,
                  value: state.infraId,
                  decoration: const InputDecoration(
                    labelText: 'Infrastructure Item',
                    isDense: true,
                  ),
                  hint: const Text('All'),
                  items: state.infraOptions
                      .map(
                        (o) => DropdownMenuItem(
                          value: o.id,
                          child: Text(o.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: state.infraType == InfraFilterType.all
                      ? null
                      : (id) => ref
                          .read(reportsControllerProvider.notifier)
                          .setInfraId(id),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DateRangeFilterBar(
            from: state.startDate,
            to: state.endDate,
            padding: EdgeInsets.zero,
            onChanged: (from, to) {
              final now = DateTime.now();
              ref.read(reportsControllerProvider.notifier).loadRegister(
                    startDate: from ?? now.subtract(const Duration(days: 30)),
                    endDate: to ?? now,
                  );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterCard(MaintenanceRegisterEntry entry, int slNo) {
    final dateStr = entry.date != null ? DateFormat('dd/MM/yyyy').format(entry.date!) : 'N/A';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppTheme.railwayBlue.withOpacity(0.12),
          child: Text('#$slNo', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.railwayBlue, fontSize: 12)),
        ),
        title: Text(
          entry.masterName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Completed: $dateStr · ${entry.stationName ?? "Not specified"}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            if (entry.technician != null)
              Text('Technician: ${entry.technician}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textSecondary),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RegisterEntryDetailScreen(entry: entry),
            ),
          );
        },
      ),
    );
  }
}
