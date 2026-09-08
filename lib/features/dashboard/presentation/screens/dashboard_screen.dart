import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_state.dart';
import 'package:gssms_mobile/features/dashboard/presentation/widgets/status_donut_chart.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dashboardControllerProvider.notifier).loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final session = authState is Authenticated ? authState.session : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SyncStatusBadge(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(dashboardControllerProvider.notifier).loadDashboard(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (session != null) _buildOrgScope(state, session),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  /// Depot-only by design: `summary` accepts nothing broader (see
  /// DashboardApiService.getSummary), and offering Zone/Division here would
  /// narrow the attention card while leaving the KPI donut beside it
  /// unfiltered. Station is not a level either endpoint supports.
  Widget _buildOrgScope(DashboardState state, UserSession session) {
    final loaded = state is DashboardLoaded
        ? state
        : (state is DashboardError ? state.previousLoaded : null);
    // The bar collapses to nothing for a depot-scoped viewer, so its own
    // padding is used rather than an outer wrapper that would leave a gap.
    return OrgScopeFilterBar(
      scope: session.scope,
      selection: loaded?.orgScope ?? OrgScopeSelection.empty,
      enableZoneDivision: false,
      enableStation: false,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      onChanged: (selection) {
        ref.read(dashboardControllerProvider.notifier).setOrgScope(selection);
      },
    );
  }

  Widget _buildBody(DashboardState state) {
    if (state is DashboardLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is DashboardError) {
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
                onPressed: () => ref.read(dashboardControllerProvider.notifier).loadDashboard(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is DashboardLoaded) {
      final attention = state.attention;
      final stats = state.summary.stats;

      return RefreshIndicator(
        onRefresh: () => ref.read(dashboardControllerProvider.notifier).loadDashboard(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildAttentionSection(attention),
            const SizedBox(height: 16),
            StatusDonutChart(
              segments: stats.statusSegments,
              total: stats.totalWorkOrders,
            ),
            const SizedBox(height: 16),
            _buildKpiGrid(stats),
          ],
        ),
      );
    }

    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildAttentionSection(AttentionSummary attention) {
    final hasOverdue = attention.overdue.isNotEmpty;
    final hasDueSoon = attention.dueSoon.isNotEmpty;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppTheme.errorRed),
                const SizedBox(width: 8),
                const Text(
                  'Attention Required',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.railwayBlue),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.errorRed.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${attention.overdue.length} Overdue',
                    style: const TextStyle(color: AppTheme.errorRed, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasOverdue && !hasDueSoon)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No urgent items requiring attention.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              )
            else ...[
              if (hasOverdue) ...[
                const Text('Overdue Schedules', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.errorRed)),
                const SizedBox(height: 6),
                ...attention.overdue.map((item) => _buildAttentionTile(item, isOverdue: true)),
                const SizedBox(height: 10),
              ],
              if (hasDueSoon) ...[
                const Text('Due in 7 Days', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.warningAmber)),
                const SizedBox(height: 6),
                ...attention.dueSoon.map((item) => _buildAttentionTile(item, isOverdue: false)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAttentionTile(AttentionItem item, {required bool isOverdue}) {
    final color = isOverdue ? AppTheme.errorRed : AppTheme.warningAmber;
    final dateStr = item.dueDate != null ? DateFormat('dd/MM/yyyy').format(item.dueDate!) : 'Pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.masterName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                if (item.stationName != null && item.stationName!.isNotEmpty)
                  Text(
                    item.stationName!,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isOverdue
                  ? '${item.daysOverdue ?? 1}d Overdue'
                  : 'Due: $dateStr',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(DashboardStats stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Operational Metrics',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.railwayBlue),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: [
            _buildKpiCard('Total Job Works', '${stats.totalWorkOrders}', Icons.assignment_outlined, AppTheme.railwayBlue),
            _buildKpiCard('Compliance Rate', '${stats.complianceRate.toStringAsFixed(1)}%', Icons.check_circle_outline, AppTheme.railwayGreen),
            _buildKpiCard('Pending Tasks', '${stats.pendingTaskCount}', Icons.hourglass_empty_outlined, AppTheme.warningAmber),
            _buildKpiCard('Open Complaints', '${stats.openComplaintCount}', Icons.report_problem_outlined, AppTheme.errorRed),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
