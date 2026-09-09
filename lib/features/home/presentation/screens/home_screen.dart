import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../../assets/presentation/screens/asset_list_screen.dart';
import '../../../assets/presentation/widgets/qr_scanner_dialog.dart';
import '../../../auth/domain/models/auth_role.dart';
import '../../../auth/domain/models/user_session.dart';
import '../../../auth/domain/rbac.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/auth_state.dart';
import '../../../auth/presentation/screens/user_profile_screen.dart';
import '../../../complaints/presentation/screens/complaint_create_screen.dart';
import '../../../complaints/presentation/screens/complaint_list_screen.dart';
import '../../../dashboard/presentation/controllers/dashboard_controller.dart';
import '../../../dashboard/presentation/controllers/dashboard_state.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../energy/presentation/screens/energy_placeholder_screen.dart';
import '../../../inspections/presentation/screens/inspection_create_screen.dart';
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
        titleSpacing: 16,
        title: const Text('GSSMS Operations'),
        actions: [
          _buildHeaderProfile(context, currentSession),
          if (currentSession.hasPermission('maintenance.view'))
            IconButton(
              key: const Key('home_notifications_button'),
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                );
              },
            ),
          IconButton(
            key: const Key('home_logout_button'),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () {
              ref.read(authControllerProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (currentSession.hasPermission('maintenance.view')) {
            await ref
                .read(workOrderListControllerProvider.notifier)
                .fetchWorkOrders(forceRefresh: true);
            await ref.read(dashboardControllerProvider.notifier).loadDashboard();
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. My Work Section (Assigned / In-progress work with CONTINUE)
              _buildMyWorkSection(context, currentSession),
              const SizedBox(height: 20),

              // 2. Attention Required
              _buildAttentionSection(context, currentSession),
              const SizedBox(height: 20),

              // 3. Quick Actions
              _buildQuickActionsSection(context, currentSession),
              const SizedBox(height: 24),

              // 4. Operational Modules (long tail grid)
              const Text(
                'Operational Modules',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 12),
              _buildModulesGrid(context, currentSession),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyWorkSection(BuildContext context, UserSession session) {
    if (!sessionAllows(session, 'maintenance.view')) {
      return const SizedBox.shrink();
    }

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'MY WORK',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            if (activeWo != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isContinue
                      ? AppTheme.accentOrange.withOpacity(0.12)
                      : AppTheme.railwayBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isContinue ? 'In Progress' : 'Assigned to You',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isContinue
                            ? AppTheme.accentOrange
                            : AppTheme.railwayBlue,
                      ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (activeWo != null)
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.borderGrey),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.engineering_outlined,
                          color: AppTheme.primaryBlue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activeWo.title ??
                                  activeWo.maintenanceMasterName ??
                                  'Maintenance Work Order',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'WO #${activeWo.ticketNumber ?? activeWo.id} • ${activeWo.stationName ?? activeWo.depotName ?? 'Location'}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: Key(isContinue
                          ? 'home_continue_work_button'
                          : 'home_start_work_button'),
                      style: FilledButton.styleFrom(
                        backgroundColor: isContinue
                            ? AppTheme.accentOrange
                            : AppTheme.railwayBlue,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        isContinue ? 'CONTINUE' : 'START',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                WorkOrderDetailScreen(workOrderId: activeWo.id),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderGrey),
            ),
            child: Row(
              children: [
                const Icon(Icons.task_alt_rounded,
                    color: AppTheme.successGreen, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'No active job works in progress. Ready for new field assignments.',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WorkOrderListScreen(),
                      ),
                    );
                  },
                  child: const Text('View All'),
                ),
              ],
            ),
          ),
      ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ATTENTION REQUIRED',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: totalAttention > 0
                ? AppTheme.warningAmber.withOpacity(0.08)
                : AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: totalAttention > 0
                  ? AppTheme.warningAmber.withOpacity(0.3)
                  : AppTheme.borderGrey,
            ),
          ),
          child: Row(
            children: [
              Icon(
                totalAttention > 0
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                color: totalAttention > 0
                    ? AppTheme.warningAmber
                    : AppTheme.successGreen,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  totalAttention > 0
                      ? '$totalAttention action${totalAttention > 1 ? 's' : ''} need attention'
                      : 'All scheduled maintenance and items are up to date.',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: totalAttention > 0
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: totalAttention > 0
                        ? AppTheme.warningAmberDark
                        : AppTheme.textMuted,
                  ),
                ),
              ),
              if (totalAttention > 0 && sessionAllows(session, 'dashboard.view'))
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const DashboardScreen()),
                    );
                  },
                  child: const Text('Review'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionsSection(BuildContext context, UserSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK ACTIONS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ActionChip(
              key: const Key('quick_action_scan_asset'),
              avatar: const Icon(Icons.qr_code_scanner,
                  size: 18, color: AppTheme.railwayBlue),
              label: const Text('Scan Asset'),
              onPressed: () {
                showDialog<String>(
                  context: context,
                  builder: (_) => const QrScannerDialog(),
                );
              },
            ),
            if (sessionAllows(session, 'complaints.create') ||
                sessionAllows(session, 'complaints.view'))
              ActionChip(
                key: const Key('quick_action_complaint'),
                avatar: const Icon(Icons.report_problem_outlined,
                    size: 18, color: AppTheme.accentOrange),
                label: const Text('Log Complaint'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ComplaintCreateScreen(),
                    ),
                  );
                },
              ),
            if (sessionAllows(session, 'inspections.create') ||
                sessionAllows(session, 'inspections.view'))
              ActionChip(
                key: const Key('quick_action_inspection'),
                avatar: const Icon(Icons.fact_check_outlined,
                    size: 18, color: AppTheme.moduleInspections),
                label: const Text('Inspection'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const InspectionCreateScreen(),
                    ),
                  );
                },
              ),
            if (sessionAllows(session, 'maintenance.view'))
              ActionChip(
                key: const Key('quick_action_work_orders'),
                avatar: const Icon(Icons.assignment_outlined,
                    size: 18, color: AppTheme.primaryDark),
                label: const Text('Work Orders'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorkOrderListScreen(),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderProfile(BuildContext context, UserSession currentSession) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('home_profile_button'),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const UserProfileScreen(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              const SizedBox(width: 8),
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
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),
                    Text(
                      currentSession.primaryRole.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.75),
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

    if (sessionAllows(session, 'dashboard.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_dashboard'),
        title: 'Dashboard',
        subtitle: 'Org-wide status & attention overview',
        icon: Icons.dashboard_outlined,
        emoji: '📊',
        color: AppTheme.moduleDashboard,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const DashboardScreen(),
            ),
          );
        },
      ));
    }

    if (sessionAllows(session, 'maintenance.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_maintenance'),
        title: 'Maintenance',
        subtitle: 'Compliance & job work management',
        icon: Icons.build_circle_outlined,
        emoji: '🧰',
        color: AppTheme.moduleMaintenance,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const MaintenanceScreen(),
            ),
          );
        },
      ));
    }

    if (sessionAllows(session, 'complaints.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_complaints'),
        title: 'Complaints',
        subtitle: 'Log and track field complaints',
        icon: Icons.report_problem_outlined,
        emoji: '🚨',
        color: AppTheme.moduleComplaints,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ComplaintListScreen(),
            ),
          );
        },
      ));
    }

    if (sessionAllows(session, 'inspections.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_inspections'),
        title: 'Inspections',
        subtitle: 'Field inspections & requests',
        icon: Icons.fact_check_outlined,
        emoji: '🔍',
        color: AppTheme.moduleInspections,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const InspectionListScreen(),
            ),
          );
        },
      ));
    }

    if (sessionAllows(session, 'assets.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_assets'),
        title: 'Assets',
        subtitle: 'Search equipment & scan barcodes',
        icon: Icons.qr_code_scanner_outlined,
        emoji: '📦',
        color: AppTheme.moduleAssets,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AssetListScreen(),
            ),
          );
        },
      ));
    }

    if (sessionAllows(session, 'reports.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_reports'),
        title: 'Reports & Audit',
        subtitle: 'Maintenance register & audit trail',
        icon: Icons.description_outlined,
        emoji: '📄',
        color: AppTheme.moduleReports,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ReportsScreen(),
            ),
          );
        },
      ));
    }

    if (_showEnergyPlaceholder(session)) {
      modules.add(_buildModuleCard(
        key: const Key('module_energy'),
        title: 'Energy & Solar',
        subtitle: 'Meter photos & bills — coming soon',
        icon: Icons.solar_power_outlined,
        emoji: '☀️',
        color: AppTheme.moduleEnergy,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const EnergyPlaceholderScreen(),
            ),
          );
        },
      ));
    }

    if (modules.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.borderGrey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderGrey),
        ),
        child: const Column(
          children: [
            Icon(Icons.lock_outline, size: 40, color: AppTheme.textMuted),
            SizedBox(height: 8),
            Text(
              'No operational modules enabled by server permissions.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
        return GridView(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 150,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: modules,
        );
      },
    );
  }

  Widget _buildModuleCard({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required String emoji,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      key: key,
      elevation: 2,
      margin: EdgeInsets.zero,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.borderGrey, width: 0.8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  height: 1.2,
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
