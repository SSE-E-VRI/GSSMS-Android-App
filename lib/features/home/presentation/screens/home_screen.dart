import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/sync/widgets/sync_status_badge.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../assets/presentation/asset_scan_flow.dart';
import '../../../assets/presentation/screens/asset_list_screen.dart';
import '../../../auth/domain/models/auth_role.dart';
import '../../../auth/domain/models/user_session.dart';
import '../../../auth/domain/rbac.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/auth_state.dart';
import '../../../auth/presentation/screens/user_profile_screen.dart';
import '../../../auth/presentation/widgets/sign_out_confirmation.dart';
import '../../../complaints/presentation/screens/complaint_list_screen.dart';
import '../../../dashboard/presentation/controllers/dashboard_controller.dart';
import '../../../dashboard/presentation/controllers/dashboard_state.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../energy/presentation/screens/energy_placeholder_screen.dart';
import '../../../inspections/presentation/screens/inspection_list_screen.dart';
import '../../../maintenance/presentation/screens/maintenance_screen.dart';
import '../../../more/presentation/screens/more_screen.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../reports/presentation/screens/reports_screen.dart';
import '../../../work/presentation/screens/work_screen.dart';
import '../../../work_orders/domain/models/work_order.dart';
import '../../../work_orders/presentation/controllers/work_order_controllers.dart';
import '../../../work_orders/presentation/controllers/work_order_state.dart';
import '../../../work_orders/presentation/screens/work_order_detail_screen.dart';
import '../../../work_orders/presentation/screens/work_order_list_screen.dart';

class _NavDestinationItem {
  const _NavDestinationItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final Key key;
  final String label;
  final Widget icon;
  final Widget selectedIcon;
  final Widget screen;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    this.session,
    this.autoLoadData = false,
  });

  final UserSession? session;
  final bool autoLoadData;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.autoLoadData) return;
      final session = sessionFromAuth(ref.read(authControllerProvider)) ?? widget.session;
      if (sessionAllows(session, 'maintenance.view')) {
        ref.read(workOrderListControllerProvider.notifier).fetchWorkOrders();
        ref.read(dashboardControllerProvider.notifier).loadDashboard();
      }
    });
  }

  static bool _showEnergyPlaceholder(UserSession session) {
    if (session.primaryRole == AuthRole.ebBillClerk) return true;
    if (session.roles.contains(AuthRole.ebBillClerk)) return true;
    if (session.permissions.contains('*')) return false;
    return session.permissions.any((p) => p.startsWith('energy.'));
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  List<_NavDestinationItem> _buildDestinations(UserSession session) {
    final list = <_NavDestinationItem>[
      _NavDestinationItem(
        key: const Key('nav_home'),
        label: 'Home',
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        screen: _buildHomeTab(context, session),
      ),
    ];

    final hasWork = sessionAllows(session, 'maintenance.view') ||
        sessionAllows(session, 'complaints.view') ||
        sessionAllows(session, 'inspections.view');

    if (hasWork) {
      list.add(
        _NavDestinationItem(
          key: const Key('nav_work'),
          label: 'Work',
          icon: const Icon(Icons.assignment_outlined),
          selectedIcon: const Icon(Icons.assignment),
          screen: WorkScreen(session: session),
        ),
      );
    }

    if (sessionAllows(session, 'assets.view')) {
      list.add(
        const _NavDestinationItem(
          key: Key('nav_assets'),
          label: 'Assets',
          icon: Icon(Icons.qr_code_scanner_outlined),
          selectedIcon: Icon(Icons.qr_code_scanner),
          screen: AssetListScreen(),
        ),
      );
    }

    list.add(
      _NavDestinationItem(
        key: const Key('nav_more'),
        label: 'More',
        icon: const Icon(Icons.more_horiz_outlined),
        selectedIcon: const Icon(Icons.more_horiz),
        screen: MoreScreen(session: session),
      ),
    );

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final currentSession =
        authState is Authenticated ? authState.session : widget.session;

    if (currentSession == null) {
      return const Scaffold(
        body: SizedBox.shrink(),
      );
    }

    final destinations = _buildDestinations(currentSession);
    final activeIndex =
        _currentIndex < destinations.length ? _currentIndex : 0;

    return Scaffold(
      body: IndexedStack(
        index: activeIndex,
        children: destinations.map((d) => d.screen).toList(),
      ),
      bottomNavigationBar: destinations.length > 1
          ? NavigationBar(
              key: const Key('app_navigation_bar'),
              selectedIndex: activeIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              destinations: destinations
                  .map(
                    (d) => NavigationDestination(
                      key: d.key,
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: d.label,
                    ),
                  )
                  .toList(),
            )
          : null,
    );
  }

  Widget _buildHomeTab(BuildContext context, UserSession currentSession) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: GssmsSpacing.s16,
        title: const Text('GSSMS Operations'),
        actions: [
          _buildHeaderProfile(context, currentSession),
          if (currentSession.hasPermission('maintenance.view'))
            IconButton(
              key: const Key('home_notifications_button'),
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
              onPressed: () => _open(const NotificationsScreen()),
            ),
          IconButton(
            key: const Key('home_logout_button'),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () => confirmAndSignOut(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          const SyncStatusBadge(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (currentSession.hasPermission('maintenance.view')) {
                  await Future.wait([
                    ref
                        .read(workOrderListControllerProvider.notifier)
                        .fetchWorkOrders(forceRefresh: true),
                    ref.read(dashboardControllerProvider.notifier).loadDashboard(),
                  ]);
                }
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(GssmsSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. My Work (the technician's assigned / in-progress job)
                    _buildMyWorkSection(context, currentSession),
                    // 2. Attention Required
                    _buildAttentionSection(context, currentSession),
                    // 3. Quick Actions
                    _buildQuickActionsSection(context, currentSession),
                    const SizedBox(height: GssmsSpacing.s24),
                    // 4. Operational Modules (long-tail grid)
                    const _HomeSectionLabel('OPERATIONAL MODULES'),
                    const SizedBox(height: GssmsSpacing.s8),
                    _buildModulesGrid(context, currentSession),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyWorkSection(BuildContext context, UserSession session) {
    // "My Work" surfaces the record assigned to *this person as executor* --
    // a technician concept. Every other role (Depot Incharge and above) works
    // through the Maintenance/Work Orders module instead, so showing this
    // banner there would point at a job that isn't theirs to execute.
    if (!session.roles.contains(AuthRole.maintenanceStaff)) {
      return const SizedBox.shrink();
    }

    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final listState = ref.watch(workOrderListControllerProvider);

    WorkOrder? inProgress;
    WorkOrder? assigned;

    if (listState is WorkOrderListLoaded) {
      for (final wo in listState.workOrders) {
        if (wo.status == WorkOrderStatus.inProgress && inProgress == null) {
          inProgress = wo;
        } else if (wo.status == WorkOrderStatus.assigned && assigned == null) {
          assigned = wo;
        }
      }
    }

    final activeWo = inProgress ?? assigned;
    final isContinue = inProgress != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: GssmsSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _HomeSectionLabel('MY WORK')),
              if (activeWo != null)
                StatusChip(
                  label: isContinue ? 'In Progress' : 'Assigned to You',
                  tone: isContinue ? GssmsTone.accent : GssmsTone.info,
                  icon: isContinue
                      ? Icons.construction_outlined
                      : Icons.assignment_ind_outlined,
                ),
            ],
          ),
          const SizedBox(height: GssmsSpacing.s8),
          if (activeWo != null)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(GssmsSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(GssmsSpacing.s8),
                          decoration: BoxDecoration(
                            color: tokens.info.background,
                            borderRadius: BorderRadius.circular(GssmsRadius.r8),
                          ),
                          child: Icon(
                            Icons.engineering_outlined,
                            color: tokens.info.foreground,
                            size: GssmsSize.iconLg,
                          ),
                        ),
                        const SizedBox(width: GssmsSpacing.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activeWo.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium,
                              ),
                              const SizedBox(height: GssmsSpacing.s2),
                              Text(
                                '${activeWo.displayReference} • '
                                '${activeWo.stationName ?? activeWo.depotName ?? 'Location not set'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: GssmsSpacing.s16),
                    SizedBox(
                      width: double.infinity,
                      height: GssmsSize.primaryAction,
                      child: FilledButton.icon(
                        key: Key(isContinue
                            ? 'home_continue_work_button'
                            : 'home_start_work_button'),
                        style: isContinue
                            ? FilledButton.styleFrom(
                                backgroundColor: tokens.accent.solid,
                                foregroundColor: tokens.accent.onSolid,
                              )
                            : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(isContinue ? 'Continue work' : 'Open to start'),
                        onPressed: () =>
                            _open(WorkOrderDetailScreen(workOrderId: activeWo.id)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _InfoPanel(
              icon: Icons.task_alt_rounded,
              tone: GssmsTone.success,
              message:
                  'No active job works in progress. Ready for new field assignments.',
              action: TextButton(
                onPressed: () => _open(const WorkOrderListScreen()),
                child: const Text('View All'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttentionSection(BuildContext context, UserSession session) {
    final dashboardState = ref.watch(dashboardControllerProvider);

    int totalAttention = 0;
    if (dashboardState is DashboardLoaded) {
      final overdue = dashboardState.attention.overdue.length;
      final dueSoon = dashboardState.attention.dueSoon.length;
      totalAttention = overdue + dueSoon;
    }
    final needsAttention = totalAttention > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: GssmsSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HomeSectionLabel('ATTENTION REQUIRED'),
          const SizedBox(height: GssmsSpacing.s8),
          _InfoPanel(
            icon: needsAttention
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline,
            tone: needsAttention ? GssmsTone.warning : GssmsTone.success,
            tinted: needsAttention,
            emphasize: needsAttention,
            message: needsAttention
                ? '$totalAttention action${totalAttention > 1 ? 's' : ''} need attention'
                : 'All scheduled maintenance and items are up to date.',
            action: needsAttention && sessionAllows(session, 'dashboard.view')
                ? TextButton(
                    onPressed: () => _open(const DashboardScreen()),
                    child: const Text('Review'),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection(BuildContext context, UserSession session) {
    final canScan = sessionAllows(session, 'assets.view');
    final canWork = sessionAllows(session, 'maintenance.view');
    if (!canScan && !canWork) return const SizedBox.shrink();

    final iconColor = context.gssms.link;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HomeSectionLabel('QUICK ACTIONS'),
        const SizedBox(height: GssmsSpacing.s8),
        Wrap(
          spacing: GssmsSpacing.s8,
          runSpacing: GssmsSpacing.s8,
          children: [
            // Scan resolves the code to one asset and opens it (it used to
            // discard the scan result). Asset lookup needs assets.view.
            if (canScan)
              ActionChip(
                key: const Key('quick_action_scan_asset'),
                avatar: Icon(Icons.qr_code_scanner, size: 18, color: iconColor),
                label: const Text('Scan Asset'),
                onPressed: () => scanAndOpenAsset(context, ref),
              ),
            // "Log Complaint"/"Inspection" quick actions were removed from
            // here — creating a complaint or inspection now lives only in
            // its own module (the FAB on ComplaintListScreen/
            // InspectionListScreen), not duplicated as a Home shortcut too.
            if (canWork)
              ActionChip(
                key: const Key('quick_action_work_orders'),
                avatar: Icon(Icons.assignment_outlined, size: 18, color: iconColor),
                label: const Text('Job Works'),
                onPressed: () => _open(const WorkOrderListScreen()),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderProfile(BuildContext context, UserSession currentSession) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('home_profile_button'),
        onTap: () => _open(const UserProfileScreen()),
        borderRadius: BorderRadius.circular(GssmsRadius.r8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GssmsSpacing.s8,
            vertical: GssmsSpacing.s4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatar(
                key: const Key('home_profile_avatar'),
                userId: currentSession.userId,
                photoUrl: currentSession.profilePicture,
                displayName: currentSession.displayName,
                radius: 16,
                backgroundColor: Colors.white.withOpacity(0.18),
                foregroundColor: Colors.white,
              ),
              const SizedBox(width: GssmsSpacing.s8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentSession.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),
                    Text(
                      currentSession.primaryRole.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.white.withOpacity(0.8),
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModulesGrid(BuildContext context, UserSession session) {
    final modules = <Widget>[];

    void add({
      required Key key,
      required String title,
      required String subtitle,
      required IconData icon,
      required Color color,
      required Widget screen,
    }) {
      modules.add(_ModuleCard(
        key: key,
        title: title,
        subtitle: subtitle,
        icon: icon,
        color: color,
        onTap: () => _open(screen),
      ));
    }

    if (sessionAllows(session, 'dashboard.view')) {
      add(
        key: const Key('module_dashboard'),
        title: 'Dashboard',
        subtitle: 'Org-wide status & attention overview',
        icon: Icons.dashboard_outlined,
        color: AppTheme.moduleDashboard,
        screen: const DashboardScreen(),
      );
    }

    if (sessionAllows(session, 'maintenance.view')) {
      add(
        key: const Key('module_maintenance'),
        title: 'Maintenance',
        subtitle: 'Compliance & job work management',
        icon: Icons.build_circle_outlined,
        color: AppTheme.moduleMaintenance,
        screen: const MaintenanceScreen(),
      );
    }

    if (sessionAllows(session, 'complaints.view')) {
      add(
        key: const Key('module_complaints'),
        title: 'Complaints',
        subtitle: 'Log and track field complaints',
        icon: Icons.report_problem_outlined,
        color: AppTheme.moduleComplaints,
        screen: const ComplaintListScreen(),
      );
    }

    if (sessionAllows(session, 'inspections.view')) {
      add(
        key: const Key('module_inspections'),
        title: 'Inspections',
        subtitle: 'Field inspections & requests',
        icon: Icons.fact_check_outlined,
        color: AppTheme.moduleInspections,
        screen: const InspectionListScreen(),
      );
    }

    if (sessionAllows(session, 'assets.view')) {
      add(
        key: const Key('module_assets'),
        title: 'Assets',
        subtitle: 'Search equipment & scan barcodes',
        icon: Icons.qr_code_scanner_outlined,
        color: AppTheme.moduleAssets,
        screen: const AssetListScreen(),
      );
    }

    if (sessionAllows(session, 'reports.view')) {
      add(
        key: const Key('module_reports'),
        title: 'Reports & Audit',
        subtitle: 'Maintenance register & audit trail',
        icon: Icons.description_outlined,
        color: AppTheme.moduleReports,
        screen: const ReportsScreen(),
      );
    }

    if (_showEnergyPlaceholder(session)) {
      add(
        key: const Key('module_energy'),
        title: 'Energy & Solar',
        subtitle: 'Meter photos & bills — coming soon',
        icon: Icons.solar_power_outlined,
        color: AppTheme.moduleEnergy,
        screen: const EnergyPlaceholderScreen(),
      );
    }

    if (modules.isEmpty) {
      return const _InfoPanel(
        icon: Icons.lock_outline,
        tone: GssmsTone.neutral,
        message: 'No operational modules enabled by server permissions.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
        // Grow the tile with the user's font size instead of clipping it.
        final scale =
            MediaQuery.textScalerOf(context).scale(14) / 14;
        return GridView(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: GssmsSpacing.s12,
            crossAxisSpacing: GssmsSpacing.s12,
            mainAxisExtent: 128 * scale.clamp(1.0, 1.6),
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: modules,
        );
      },
    );
  }
}

class _HomeSectionLabel extends StatelessWidget {
  const _HomeSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.gssms.textSecondary,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

/// Single-row status panel: tone icon + message + optional trailing action.
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.tone,
    required this.message,
    this.action,
    this.tinted = false,
    this.emphasize = false,
  });

  final IconData icon;
  final GssmsTone tone;
  final String message;
  final Widget? action;
  final bool tinted;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final palette = tokens.tone(tone);
    final cardColor = Theme.of(context).cardTheme.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        GssmsSpacing.s16,
        GssmsSpacing.s12,
        GssmsSpacing.s8,
        GssmsSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: tinted ? palette.background : cardColor,
        borderRadius: BorderRadius.circular(GssmsRadius.r12),
        border: Border.all(color: tinted ? palette.border : tokens.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.foreground, size: GssmsSize.iconLg),
          const SizedBox(width: GssmsSpacing.s12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: emphasize ? FontWeight.w600 : FontWeight.normal,
                    color: emphasize ? palette.foreground : tokens.textSecondary,
                  ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final accent = context.moduleColor(color);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(GssmsSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(GssmsSpacing.s8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(GssmsRadius.r8),
                ),
                child: Icon(icon, color: accent, size: GssmsSize.iconLg),
              ),
              const Spacer(),
              Text(
                title,
                style: textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: GssmsSpacing.s2),
              Text(
                subtitle,
                style: textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                ),
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
