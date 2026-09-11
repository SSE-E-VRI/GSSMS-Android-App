import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/org_scope_app_bar_filter.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_list_screen.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_state.dart';
import 'package:gssms_mobile/features/dashboard/presentation/widgets/status_donut_chart.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_list_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_list_screen.dart';

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)), 'maintenance.view')) {
        return;
      }
      ref.read(dashboardControllerProvider.notifier).loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final session = sessionFromAuth(authState);

    if (!sessionAllows(session, 'maintenance.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Maintenance Management')),
        body: const PermissionDeniedView(),
      );
    }

    final loaded = state is DashboardLoaded
        ? state
        : (state is DashboardError ? state.previousLoaded : null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance Management'),
        actions: [
          if (session != null)
            OrgScopeAppBarFilter(
              scope: session.scope,
              selection: loaded?.orgScope ?? OrgScopeSelection.empty,
              // Same as DashboardScreen (this screen reuses
              // dashboardControllerProvider): `dashboard/summary/` now
              // accepts zone_id/division_id. Station stays disabled: the
              // endpoint has no station param.
              enableStation: false,
              onChanged: (selection) {
                ref
                    .read(dashboardControllerProvider.notifier)
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


  Widget _buildBody(DashboardState state, UserSession? session) {
    if (state is DashboardLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is DashboardError) {
      // Keep showing the last good summary with an inline error instead of
      // wiping the screen on a failed refresh (e.g. offline reopen).
      final fallback = state.previousLoaded;
      if (fallback != null) {
        return RefreshIndicator(
          onRefresh: () =>
              ref.read(dashboardControllerProvider.notifier).loadDashboard(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Material(
                color: context.gssms.danger.background,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off, size: 18, color: context.gssms.danger.foreground),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.message,
                          style: TextStyle(fontSize: 12, color: context.gssms.danger.foreground),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildComplianceCard(fallback.summary.stats.complianceRate),
              const SizedBox(height: 16),
              StatusDonutChart(
                title: 'Job Work Distribution',
                segments: fallback.summary.stats.statusSegments,
                total: fallback.summary.stats.totalWorkOrders,
              ),
              const SizedBox(height: 16),
              _buildQuickActions(
                  context, fallback.summary.stats, session),
            ],
          ),
        );
      }
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
                onPressed: () => ref.read(dashboardControllerProvider.notifier).loadDashboard(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is DashboardLoaded) {
      final stats = state.summary.stats;

      return RefreshIndicator(
        onRefresh: () => ref.read(dashboardControllerProvider.notifier).loadDashboard(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildComplianceCard(stats.complianceRate),
            const SizedBox(height: 16),
            StatusDonutChart(
              title: 'Job Work Distribution',
              segments: stats.statusSegments,
              total: stats.totalWorkOrders,
            ),
            const SizedBox(height: 16),
            _buildQuickActions(context, stats, session),
          ],
        ),
      );
    }

    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildComplianceCard(double rate) {
    final palette = rate >= 80 ? context.gssms.success : context.gssms.warning;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: 'Maintenance compliance rate ${rate.toStringAsFixed(1)} percent',
      child: Container(
        padding: const EdgeInsets.all(GssmsSpacing.s16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(GssmsRadius.r12),
          border: Border.all(color: context.gssms.border),
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Maintenance Compliance Rate',
                style: textTheme.labelMedium?.copyWith(color: context.gssms.textSecondary),
              ),
              const SizedBox(height: GssmsSpacing.s8),
              Row(
                children: [
                  Text(
                    '${rate.toStringAsFixed(1)}%',
                    style: textTheme.headlineSmall?.copyWith(fontSize: 32),
                  ),
                  const Spacer(),
                  Icon(
                    rate >= 80 ? Icons.check_circle : Icons.warning_amber_rounded,
                    color: palette.foreground,
                    size: 36,
                  ),
                ],
              ),
              const SizedBox(height: GssmsSpacing.s8),
              ClipRRect(
                borderRadius: BorderRadius.circular(GssmsRadius.r4),
                child: LinearProgressIndicator(
                  value: (rate / 100).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: context.gssms.border,
                  color: palette.solid,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Reaching this screen already required `maintenance.view` (the Home tile
  /// gate), which covers the Work Orders shortcut. Complaints and Inspections
  /// are independently-permissioned resources on the server
  /// (ComplaintViewSet/InspectionViewSet each gate reads on their own
  /// `complaints.view`/`inspections.view` code, not `maintenance.view`) — a
  /// role that holds only `maintenance.view` would 403 on those lists, so
  /// each shortcut here is gated on the permission its destination actually
  /// requires rather than assumed from this screen's own entry gate.
  Widget _buildQuickActions(
    BuildContext context,
    DashboardStats stats,
    UserSession? session,
  ) {
    final tiles = <Widget>[];
    if (sessionAllows(session, 'maintenance.view')) {
      tiles.add(ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: Theme.of(context).cardTheme.color,
        leading: CircleAvatar(backgroundColor: context.gssms.info.background, child: Icon(Icons.assignment, color: context.gssms.link)),
        title: const Text('Job Works', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${stats.pendingTaskCount} pending tasks'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WorkOrderListScreen())),
      ));
    }

    if (sessionAllows(session, 'complaints.view')) {
      tiles.add(ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: Theme.of(context).cardTheme.color,
        leading: CircleAvatar(backgroundColor: context.gssms.danger.background, child: Icon(Icons.report_problem, color: context.gssms.danger.foreground)),
        title: const Text('Complaints & Failures', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${stats.openComplaintCount} open complaints'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ComplaintListScreen())),
      ));
    }

    if (sessionAllows(session, 'inspections.view')) {
      tiles.add(ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: Theme.of(context).cardTheme.color,
        leading: CircleAvatar(backgroundColor: context.gssms.success.background, child: Icon(Icons.fact_check, color: context.gssms.success.foreground)),
        title: const Text('Inspections & Notes', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${stats.inspectionCount} recorded notes'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InspectionListScreen())),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Navigation',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.gssms.link),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          tiles[i],
        ],
      ],
    );
  }
}
