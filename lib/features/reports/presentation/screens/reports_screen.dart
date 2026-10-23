import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/date_range_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/org_scope_app_bar_filter.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_state.dart';
import 'package:gssms_mobile/features/reports/presentation/screens/register_job_work_detail_screen.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

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
        appBar: AppBar(title: const Text('Reports')),
        body: const PermissionDeniedView(),
      );
    }

    final loaded = state is ReportsLoaded ? state : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          if (session != null)
            OrgScopeAppBarFilter(
              scope: session.scope,
              selection: loaded?.orgScope ?? OrgScopeSelection.empty,
              // The work-order list accepts zone/division/depot (narrowest
              // wins server-side). Station stays disabled: it's already
              // covered by the Infrastructure Type/Item filter (Type=Station
              // + item) elsewhere on this screen.
              enableStation: false,
              onChanged: (selection) {
                ref
                    .read(reportsControllerProvider.notifier)
                    .setOrgScope(selection);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          const SyncStatusBadge(),
          Expanded(child: _buildBody(state, session)),
        ],
      ),
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
              Icon(Icons.error_outline, size: 48, color: context.gssms.danger.foreground),
              const SizedBox(height: 12),
              Text(
                state.message,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.gssms.textSecondary),
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
          _buildFilters(state),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No completed Job Works found for the selected date range.', textAlign: TextAlign.center, style: TextStyle(color: context.gssms.textSecondary)),
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


  Widget _buildFilters(ReportsLoaded state) {
    return Container(
      width: double.infinity,
      color: context.gssms.surfaceRaised,
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
                  initialValue: state.infraType,
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
                  initialValue: state.infraId,
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

  Widget _buildRegisterCard(WorkOrder order, int slNo) {
    final dateStr = order.reportCompletedAt != null
        ? DateFormat('dd/MM/yyyy').format(order.reportCompletedAt!.toLocal())
        : 'N/A';
    final location = [
      order.stationName,
      order.assetName,
    ].where((v) => v != null && v.trim().isNotEmpty).join(' · ');

    return Card(
      key: Key('register_card_${order.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: context.gssms.info.background,
          child: Text('#$slNo', style: TextStyle(fontWeight: FontWeight.bold, color: context.gssms.link, fontSize: 12)),
        ),
        title: Text(
          order.title?.trim().isNotEmpty == true
              ? order.title!
              : order.displayReference,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
                '${order.displayReference} · ${order.scheduleCategory} · Completed: $dateStr',
                style: TextStyle(fontSize: 12, color: context.gssms.textSecondary)),
            Text(
                location.isNotEmpty
                    ? location
                    : (order.depotName ?? 'Location not set'),
                style: TextStyle(fontSize: 11, color: context.gssms.textSecondary)),
            if (order.assignedToName != null)
              Text('Technician: ${order.assignedToName}', style: TextStyle(fontSize: 11, color: context.gssms.textSecondary)),
          ],
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: context.gssms.textSecondary),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RegisterJobWorkDetailScreen(workOrder: order),
            ),
          );
        },
      ),
    );
  }
}
