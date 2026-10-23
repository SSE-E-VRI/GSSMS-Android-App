import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
import 'package:gssms_mobile/features/dashboard/presentation/widgets/dashboard_skeleton.dart';
import 'package:gssms_mobile/features/dashboard/presentation/widgets/status_donut_chart.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_list_screen.dart';
import 'package:gssms_mobile/features/pending_actions/presentation/screens/pending_actions_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_list_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_navigation.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static const _attentionPreview = 5;
  bool _showAllOverdue = false;
  bool _showAllDueSoon = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = sessionFromAuth(ref.read(authControllerProvider));
      if (!sessionAllows(session, 'dashboard.view')) return;
      ref.read(dashboardControllerProvider.notifier).loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final session = sessionFromAuth(authState);

    if (!sessionAllows(session, 'dashboard.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: const PermissionDeniedView(),
      );
    }

    final loaded = state is DashboardLoaded
        ? state
        : (state is DashboardError ? state.previousLoaded : null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          if (session != null)
            OrgScopeAppBarFilter(
              scope: session.scope,
              selection: loaded?.orgScope ?? OrgScopeSelection.empty,
              // `dashboard/summary/` now accepts zone_id/division_id too
              // (most-specific-wins, same as `attention`) — Zone/Division
              // dropdowns show here for GLOBAL/ZONE-scoped users
              // (Super Admin/Zonal Admin) same as Work Orders/Assets.
              // Station stays disabled: neither endpoint has a station param.
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
      return const DashboardSkeleton();
    }

    if (state is DashboardError && state.previousLoaded is DashboardLoaded) {
      return _buildLoaded(state.previousLoaded!, session,
          staleMessage: state.message);
    }

    if (state is DashboardError) {
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
      return _buildLoaded(state, session);
    }

    return const DashboardSkeleton();
  }

  /// Glance-first order: headline numbers, then what is late, then what to
  /// do next, then the breakdown charts. When a refresh fails but an earlier
  /// load exists, that data stays on screen under a "could not refresh" note
  /// instead of being replaced by a full-page error.
  Widget _buildLoaded(DashboardLoaded state, UserSession? session,
      {String? staleMessage}) {
    final attention = state.attention;
    final stats = state.summary.stats;
    return RefreshIndicator(
      onRefresh: () => ref.read(dashboardControllerProvider.notifier).loadDashboard(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (staleMessage != null) ...[
            _buildStaleBanner(staleMessage),
            const SizedBox(height: 12),
          ],
          _buildKpiGrid(stats, session),
          const SizedBox(height: 16),
          _buildAttentionSection(attention, session),
          const SizedBox(height: 16),
          _buildPendingActions(
            stats,
            state.summary.pendingTasks.where((t) => !t.isBreakdown).toList(),
            session,
          ),
          const SizedBox(height: 16),
          StatusDonutChart(
            segments: stats.statusSegments,
            total: stats.totalWorkOrders,
          ),
          if (stats.typeStats.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildTypeStatsRow(stats),
          ],
        ],
      ),
    );
  }

  Widget _buildStaleBanner(String message) {
    final palette = context.gssms.warning;
    return Container(
      key: const Key('dashboard_stale_banner'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(GssmsRadius.r8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 20, color: palette.foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Could not refresh. Showing the last loaded figures.',
              style: TextStyle(fontSize: 13, color: palette.foreground),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(dashboardControllerProvider.notifier).loadDashboard(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Widget _buildAttentionSection(AttentionSummary attention, UserSession? session) {
    final canOpen = sessionAllows(session, 'maintenance.view');
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
            // Wrap (not Row): title + two badges overflow a phone-width card,
            // so the badges drop to the next line instead of clipping.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: context.gssms.danger.foreground),
                    const SizedBox(width: 8),
                    Text(
                      'Attention Required',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.gssms.link),
                    ),
                  ],
                ),
                if (hasOverdue)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.gssms.danger.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${attention.overdue.length} Overdue',
                    style: TextStyle(color: context.gssms.danger.foreground, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                if (attention.dueSoon.isNotEmpty) ...[
                  Container(
                    key: const Key('attention_due_soon_badge'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.gssms.warning.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${attention.dueSoon.length} Due soon',
                      style: TextStyle(color: context.gssms.warning.foreground, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (!hasOverdue && !hasDueSoon)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 20, color: context.gssms.success.foreground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Nothing overdue or due this week.',
                          style: TextStyle(color: context.gssms.textSecondary, fontSize: 13)),
                    ),
                  ],
                ),
              )
            else ...[
              if (hasOverdue) ...[
                Text('Overdue Schedules', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: context.gssms.danger.foreground)),
                const SizedBox(height: 6),
                ..._attentionTiles(attention.overdue, isOverdue: true, canOpen: canOpen,
                    expanded: _showAllOverdue,
                    onToggle: () => setState(() => _showAllOverdue = !_showAllOverdue)),
                const SizedBox(height: 10),
              ],
              if (hasDueSoon) ...[
                Text('Due in 7 Days', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: context.gssms.warning.foreground)),
                const SizedBox(height: 6),
                ..._attentionTiles(attention.dueSoon, isOverdue: false, canOpen: canOpen,
                    expanded: _showAllDueSoon,
                    onToggle: () => setState(() => _showAllDueSoon = !_showAllDueSoon)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Shows the first few rows and a toggle for the rest, so a long backlog
  /// does not push every other dashboard card off-screen.
  List<Widget> _attentionTiles(
    List<AttentionItem> items, {
    required bool isOverdue,
    required bool canOpen,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    final shown = expanded ? items : items.take(_attentionPreview).toList();
    return [
      ...shown.map((item) => _buildAttentionTile(item, isOverdue: isOverdue, canOpen: canOpen)),
      if (items.length > _attentionPreview)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onToggle,
            child: Text(expanded
                ? 'Show fewer'
                : 'Show all ${items.length}'),
          ),
        ),
    ];
  }

  Widget _buildAttentionTile(AttentionItem item,
      {required bool isOverdue, required bool canOpen}) {
    final days = item.daysOverdue ??
        (item.dueDate != null
            ? DateTime.now().difference(item.dueDate!).inDays
            : null);
    final overdueLabel = (days != null && days > 0) ? '${days}d Overdue' : 'Overdue';
    final where = [
      if ((item.assetName ?? '').isNotEmpty) item.assetName!,
      if ((item.stationName ?? '').isNotEmpty)
        item.stationName!
      else if ((item.depotName ?? '').isNotEmpty)
        item.depotName!,
    ].join(' • ');
    final palette = isOverdue ? context.gssms.danger : context.gssms.warning;
    final dateStr = item.dueDate != null ? DateFormat('dd/MM/yyyy').format(item.dueDate!) : 'Pending';

    final tile = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(GssmsRadius.r8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Most rows share a schedule name ("Station Monthly
                // Maintenance"), so the place is what tells them apart.
                Text(
                  where.isNotEmpty ? where : item.masterName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (where.isNotEmpty)
                  Text(
                    item.masterName,
                    style: TextStyle(fontSize: 11, color: context.gssms.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: palette.solid,
              borderRadius: BorderRadius.circular(GssmsRadius.r4),
            ),
            child: Text(
              isOverdue ? overdueLabel : 'Due: $dateStr',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.onSolid,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ],
      ),
    );
    if (!canOpen) return tile;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(GssmsRadius.r8),
        onTap: () => _push(const PendingActionsScreen()),
        child: tile,
      ),
    );
  }

  /// Preventive vs Corrective split the summary already ships (`type_stats`)
  /// but no widget ever read — a compact companion to the donut.
  Widget _buildTypeStatsRow(DashboardStats stats) {
    return Card(
      key: const Key('dashboard_type_stats'),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Work by Type',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: context.gssms.link),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: stats.typeStats.map((t) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.gssms.info.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.gssms.info.border),
                  ),
                  child: Text(
                    t.percentage > 0
                        ? '${t.label}: ${t.count} (${t.percentage.toStringAsFixed(0)}%)'
                        : '${t.label}: ${t.count}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.gssms.link),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  /// Actionable rows from `summary.pending_tasks`, falling back to the stat
  /// counts when the server sends no itemised list. Tapping a row with a
  /// work-order id opens that Job Work; kind-only rows open the matching
  /// list (permission-gated for the synthesised fallbacks).
  Widget _buildPendingActions(
      DashboardStats stats, List<PendingAction> tasks, UserSession? session) {
    final canComplaints = sessionAllows(session, 'complaints.view');
    final canInspections = sessionAllows(session, 'inspections.view');
    final canWorkOrders = sessionAllows(session, 'maintenance.view');

    void openWorkOrder(int id) {
      unawaited(openWorkOrderGuarded(
        context: context,
        session: session,
        workOrderId: id,
      ));
    }

    void openList(Widget screen) {
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
    }

    final rows = <Widget>[];
    if (tasks.isNotEmpty) {
      for (final t in tasks.take(8)) {
        rows.add(_pendingRow(
          icon: _pendingIcon(t.kind),
          color: _pendingColor(t.kind),
          // Lead with the place (as the Attention rows do): most tasks share
          // a schedule name, so the station/asset is what tells them apart.
          title: (t.subtitle ?? '').isNotEmpty ? t.subtitle! : t.title,
          subtitle: [
            if ((t.subtitle ?? '').isNotEmpty) t.title,
            if (t.kind != PendingActionKind.unknown &&
                t.kind != PendingActionKind.task)
              t.kind.displayName,
            if (_dueLabel(t.dueDate) != null) _dueLabel(t.dueDate)!,
          ].join(' • '),
          onTap: () {
            if (t.workOrderId != null && t.workOrderId! > 0) {
              if (!canWorkOrders) return;
              openWorkOrder(t.workOrderId!);
            } else if (t.complaintId != null && canComplaints) {
              openList(const ComplaintListScreen());
            } else if (t.inspectionId != null && canInspections) {
              openList(const InspectionListScreen());
            } else if (canWorkOrders) {
              openList(const WorkOrderListScreen());
            }
          },
        ));
      }
      if (tasks.length > 8) {
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('dashboard_pending_actions_more_button'),
              onPressed: canWorkOrders
                  ? () => openList(const WorkOrderListScreen())
                  : null,
              icon: const Icon(Icons.arrow_forward, size: 14),
              label: Text(
                '+${tasks.length - 8} more in the work queues',
                style: TextStyle(
                  fontSize: 12,
                  color: canWorkOrders ? context.gssms.link : context.gssms.textSecondary,
                ),
              ),
            ),
          ),
        ));
      }
    } else {
      // No itemised list — synthesise from the counts so the section still
      // answers "what do I do next".
      if (stats.pendingVerificationCount > 0 && canWorkOrders) {
        rows.add(_pendingRow(
          icon: Icons.verified_outlined,
          color: context.gssms.success.foreground,
          title: '${stats.pendingVerificationCount} awaiting verification',
          subtitle: 'Review and verify completed Job Works',
          onTap: () => openList(const WorkOrderListScreen()),
        ));
      }
      if (stats.scheduledTasksDisplay > 0 && canWorkOrders) {
        rows.add(_pendingRow(
          icon: Icons.hourglass_empty_outlined,
          color: context.gssms.warning.foreground,
          title: '${stats.scheduledTasksDisplay} pending job works',
          subtitle: 'Open assignments needing execution',
          onTap: () => openList(const WorkOrderListScreen()),
        ));
      }
      if (stats.openComplaintCount > 0 && canComplaints) {
        rows.add(_pendingRow(
          icon: Icons.report_problem_outlined,
          color: context.gssms.danger.foreground,
          title: '${stats.openComplaintCount} open breakdowns',
          subtitle: 'Triage the breakdown queue',
          onTap: () => openList(const ComplaintListScreen()),
        ));
      }
      if (stats.inspectionCount > 0 && canInspections) {
        rows.add(_pendingRow(
          icon: Icons.fact_check_outlined,
          color: context.gssms.link,
          title: '${stats.inspectionCount} recorded notes',
          subtitle: 'Review inspections, convert where needed',
          onTap: () => openList(const InspectionListScreen()),
        ));
      }
    }

    return Card(
      key: const Key('dashboard_pending_actions'),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.playlist_add_check_outlined, color: context.gssms.link),
                      const SizedBox(width: 8),
                      Text('Pending Actions',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.gssms.link)),
                    ],
                  ),
                ),
                // Web-parity entry point: the full 4-tab breakdown (Scheduled
                // Tasks/Complaints/Inspection Notes/Deficiencies) — this
                // card only ever shows a flat glance-summary, same reasoning
                // as web keeping its own tabbed section below the KPI cards
                // rather than cramming all four lists in here at once.
                if (sessionAllows(session, 'maintenance.view'))
                  TextButton(
                    key: const Key('open_pending_actions_button'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const PendingActionsScreen())),
                    child: const Text('View All'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Text('All clear — nothing needs your action.',
                  style: TextStyle(fontSize: 13, color: context.gssms.textSecondary))
            else
              ...rows,
          ],
        ),
      ),
    );
  }

  String? _dueLabel(DateTime? due) {
    if (due == null) return null;
    final today = DateUtils.dateOnly(DateTime.now());
    final days = DateUtils.dateOnly(due.toLocal()).difference(today).inDays;
    if (days < 0) return '${-days}d overdue';
    if (days == 0) return 'Due today';
    return 'Due ${DateFormat('d MMM').format(due.toLocal())}';
  }

  IconData _pendingIcon(PendingActionKind kind) {
    switch (kind) {
      case PendingActionKind.verification:
        return Icons.verified_outlined;
      case PendingActionKind.assignment:
        return Icons.assignment_ind_outlined;
      case PendingActionKind.complaint:
        return Icons.report_problem_outlined;
      case PendingActionKind.inspection:
        return Icons.fact_check_outlined;
      case PendingActionKind.task:
      case PendingActionKind.unknown:
        return Icons.hourglass_empty_outlined;
    }
  }

  Color _pendingColor(PendingActionKind kind) {
    switch (kind) {
      case PendingActionKind.verification:
        return context.gssms.success.foreground;
      case PendingActionKind.assignment:
        return context.gssms.link;
      case PendingActionKind.complaint:
        return context.gssms.danger.foreground;
      case PendingActionKind.inspection:
        return Colors.teal;
      case PendingActionKind.task:
      case PendingActionKind.unknown:
        return context.gssms.warning.foreground;
    }
  }

  Widget _pendingRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: context.gssms.surfaceInset,
        leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 20)),
        title: Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: context.gssms.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      ),
    );
  }

  Color _complianceColor(double rate) {
    if (rate >= 90) return context.gssms.success.foreground;
    if (rate >= 70) return context.gssms.warning.foreground;
    return context.gssms.danger.foreground;
  }

  Widget _buildKpiGrid(DashboardStats stats, UserSession? session) {
    final canWork = sessionAllows(session, 'maintenance.view');
    final canComplaints = sessionAllows(session, 'complaints.view');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.gssms.link),
        ),
        const SizedBox(height: 10),
        // Two rows of two `Expanded` cards, not `GridView.count` with a
        // fixed `childAspectRatio` — a locked aspect ratio gives every tile
        // a fixed *height* regardless of how much room its content actually
        // needs, so anything that pushed the content taller than that
        // (a larger system text-scale setting, a longer value like "100.0%"
        // wrapping, a longer localized label) overflowed the tile with the
        // classic yellow/black "BOTTOM OVERFLOWED BY n PIXELS" banner —
        // exactly what was happening here. `IntrinsicHeight` still keeps
        // the two cards in a row matched to each other's height, but that
        // height is now whatever the taller card's content actually needs,
        // never a number picked in advance that content can outgrow.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildKpiCard('Total Job Works', '${stats.totalWorkOrders}',
                    Icons.assignment_outlined, context.gssms.link,
                    onTap: canWork ? () => _push(const WorkOrderListScreen()) : null),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard('Compliance Rate',
                    '${stats.complianceRate.toStringAsFixed(1)}%',
                    Icons.check_circle_outline, _complianceColor(stats.complianceRate)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildKpiCard('Pending Tasks', '${stats.scheduledTasksDisplay}',
                    Icons.hourglass_empty_outlined, context.gssms.warning.foreground,
                    onTap: canWork ? () => _push(const PendingActionsScreen()) : null),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKpiCard('Open Breakdowns', '${stats.openComplaintCount}',
                    Icons.report_problem_outlined, context.gssms.danger.foreground,
                    onTap: canComplaints ? () => _push(const ComplaintListScreen()) : null),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color,
      {VoidCallback? onTap}) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const Spacer(),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      value,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(fontSize: 13, color: context.gssms.textSecondary, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      ),
    );
  }
}
