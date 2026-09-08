import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../assets/presentation/screens/asset_list_screen.dart';
import '../../../auth/domain/models/user_session.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../complaints/presentation/screens/complaint_list_screen.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../energy/presentation/screens/energy_placeholder_screen.dart';
import '../../../inspections/presentation/screens/inspection_list_screen.dart';
import '../../../maintenance/presentation/screens/maintenance_screen.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../reports/presentation/screens/reports_screen.dart';
import '../../../work_orders/presentation/screens/work_order_list_screen.dart';

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
        title: const Text('GSSMS Operations'),
        actions: [
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
            // User Profile Card
            _buildProfileCard(),
            const SizedBox(height: 16),

            // Scope & Org Details Card
            _buildScopeCard(),
            const SizedBox(height: 24),

            // Available Operational Modules (strictly permission gated)
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

  Widget _buildProfileCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppTheme.primaryBlue.withOpacity(0.12),
              child: Text(
                session.displayName.isNotEmpty
                    ? session.displayName.substring(0, 1).toUpperCase()
                    : 'U',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryBlue,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          session.primaryRole.displayName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (session.has2FA)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, size: 12, color: Colors.green.shade700),
                              const SizedBox(width: 4),
                              Text(
                                '2FA Active',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeCard() {
    final scope = session.scope;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 20, color: AppTheme.primaryBlue),
                const SizedBox(width: 8),
                const Text(
                  'Organizational Scope',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Level: ${scope.level.value}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (scope.depot != null || session.depotName != null)
              _buildScopeRow('Depot', session.depotName ?? scope.depot?.name ?? 'N/A'),
            if (scope.division != null)
              _buildScopeRow('Division', scope.division?.name ?? 'N/A'),
            if (scope.zone != null)
              _buildScopeRow('Zone', scope.zone?.name ?? 'N/A'),
            if (session.validUntil != null)
              _buildScopeRow(
                'Access Valid Until',
                session.validUntil!.toLocal().toString().split('.')[0],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark),
          ),
        ],
      ),
    );
  }

  Widget _buildModulesGrid(BuildContext context) {
    final modules = <Widget>[];

    // Dashboard module
    if (session.hasPermission('dashboard.view') || session.hasPermission('maintenance.view')) {
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

    // Maintenance Management module
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

    // Work Orders module (gated strictly by server permission).
    // There is no `work_orders` module in the RBAC catalogue — work orders live
    // under `maintenance` ("Maintenance & Work Orders", rbac/registry.py MODULES),
    // so `maintenance.view` is the only permission that can ever grant this tile.
    if (session.hasPermission('maintenance.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_work_orders'),
        title: 'Work Orders',
        subtitle: 'Assigned maintenance & checklists',
        icon: Icons.assignment_outlined,
        emoji: '🛠️',
        color: AppTheme.primaryBlue,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const WorkOrderListScreen(),
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

    // Reports module. The register_report endpoint's read gate
    // (MaintenanceRecordPermission.has_permission, safe methods) accepts
    // EITHER maintenance.view OR reports.view — matching only the first would
    // hide this tile from a reports-only auditor/HQ role the server would
    // actually let in.
    if (session.hasPermission('maintenance.view') || session.hasPermission('reports.view')) {
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

    // Energy module — honest placeholder until GAP-04 lands (Phase 5)
    if (session.hasPermission('energy.view')) {
      modules.add(_buildModuleCard(
        key: const Key('module_energy'),
        title: 'Energy & Solar',
        subtitle: 'Grid readings and solar logs — coming soon',
        icon: Icons.solar_power_outlined,
        emoji: '⚡',
        color: Colors.indigo,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EnergyPlaceholderScreen()),
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
