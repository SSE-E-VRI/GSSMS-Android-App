import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../assets/presentation/screens/asset_list_screen.dart';
import '../../../auth/domain/models/auth_role.dart';
import '../../../auth/domain/models/user_session.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/screens/user_profile_screen.dart';
import '../../../complaints/presentation/screens/complaint_list_screen.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../energy/presentation/screens/energy_placeholder_screen.dart';
import '../../../inspections/presentation/screens/inspection_list_screen.dart';
import '../../../maintenance/presentation/screens/maintenance_screen.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../reports/presentation/screens/reports_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.session,
  });

  final UserSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('GSSMS Operations'),
        actions: [
          _buildHeaderProfile(context),
          if (session.hasPermission('maintenance.view'))
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Operational Modules',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 12),
            _buildModulesGrid(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderProfile(BuildContext context) {
    final initial = session.displayName.isNotEmpty
        ? session.displayName.substring(0, 1).toUpperCase()
        : 'U';

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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white.withOpacity(0.18),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.displayName,
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
                      session.primaryRole.displayName,
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

  Widget _buildModulesGrid(BuildContext context) {
    final modules = <Widget>[];

    // Dashboard module — `dashboard.view` only. Do not widen with
    // maintenance.view (MAINTENANCE_STAFF has no dashboard.view).
    if (session.hasPermission('dashboard.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_dashboard'),
        title: 'Dashboard',
        subtitle: 'Org-wide status & attention overview',
        icon: Icons.dashboard_outlined,
        emoji: '📊',
        color: AppTheme.railwayBlue,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const DashboardScreen(),
            ),
          );
        },
      ));
    }

    // Maintenance module — the single entry point for Job Works / Work
    // Orders (there is no `work_orders` module in the RBAC catalogue; work
    // orders live under `maintenance`, so a separate tile only duplicated
    // this one). Reach the list via Maintenance → Job Works / Work Orders.
    if (session.hasPermission('maintenance.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_maintenance'),
        title: 'Maintenance',
        subtitle: 'Compliance & job work management',
        icon: Icons.build_circle_outlined,
        emoji: '🧰',
        color: Colors.purple,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const MaintenanceScreen(),
            ),
          );
        },
      ));
    }

    // Complaints module
    if (session.hasPermission('complaints.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_complaints'),
        title: 'Complaints',
        subtitle: 'Log and track field complaints',
        icon: Icons.report_problem_outlined,
        emoji: '🚨',
        color: AppTheme.accentOrange,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ComplaintListScreen(),
            ),
          );
        },
      ));
    }

    // Inspections module
    if (session.hasPermission('inspections.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_inspections'),
        title: 'Inspections',
        subtitle: 'Field inspections & requests',
        icon: Icons.fact_check_outlined,
        emoji: '🔍',
        color: Colors.teal,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const InspectionListScreen(),
            ),
          );
        },
      ));
    }

    // Assets module
    if (session.hasPermission('assets.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_assets'),
        title: 'Assets',
        subtitle: 'Search equipment & scan barcodes',
        icon: Icons.qr_code_scanner_outlined,
        emoji: '📦',
        color: Colors.teal,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AssetListScreen(),
            ),
          );
        },
      ));
    }

    // Reports module — `reports.view` only. Do not widen with maintenance.view.
    if (session.hasPermission('reports.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_reports'),
        title: 'Reports & Audit',
        subtitle: 'Maintenance register & audit trail',
        icon: Icons.description_outlined,
        emoji: '📄',
        color: Colors.deepOrange,
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
        color: Colors.indigo,
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
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Column(
          children: [
            Icon(Icons.info_outline, color: Colors.grey, size: 32),
            SizedBox(height: 8),
            Text(
              'No operational modules enabled by server permissions.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: modules,
    );
  }

  bool _showEnergyPlaceholder(UserSession session) {
    if (session.roles.contains(AuthRole.ebBillClerk)) return true;
    if (session.permissions.contains('*')) return false;
    return session.permissions.any((p) => p.startsWith('energy.'));
  }

  Widget _buildModuleCard({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? emoji,
  }) {
    return Card(
      key: key,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.12),
                    radius: 20,
                    child: Icon(icon, color: color, size: 22),
                  ),
                  if (emoji != null)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 13, height: 1)),
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
