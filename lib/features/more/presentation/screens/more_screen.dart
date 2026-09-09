import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../../auth/domain/models/auth_role.dart';
import '../../../auth/domain/models/user_session.dart';
import '../../../auth/domain/rbac.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/screens/user_profile_screen.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../energy/presentation/screens/energy_placeholder_screen.dart';
import '../../../maintenance/presentation/screens/maintenance_screen.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../reports/presentation/screens/reports_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key, this.session});

  final UserSession? session;

  static bool _showEnergyPlaceholder(UserSession session) {
    if (session.primaryRole == AuthRole.ebBillClerk) return true;
    if (session.roles.contains(AuthRole.ebBillClerk)) return true;
    if (session.permissions.contains('*')) return false;
    return session.permissions.any((p) => p.startsWith('energy.'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveSession =
        session ?? sessionFromAuth(ref.watch(authControllerProvider));

    if (effectiveSession == null) {
      return const SizedBox.shrink();
    }
    final currentSession = effectiveSession;

    return Scaffold(
      appBar: AppBar(
        title: const Text('More Operations'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // Profile Card Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: AppTheme.primaryDark,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                key: const Key('more_profile_card'),
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const UserProfileScreen(),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ProfileAvatar(
                        userId: currentSession.userId,
                        photoUrl: currentSession.profilePicture,
                        displayName: currentSession.displayName,
                        radius: 24,
                        backgroundColor: Colors.white.withOpacity(0.18),
                        foregroundColor: Colors.white,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentSession.displayName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              currentSession.primaryRole.displayName,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.8),
                                    height: 1.15,
                                  ),
                            ),
                            if (currentSession.depotName != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                currentSession.depotName!,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color:
                                          Colors.white.withOpacity(0.65),
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Operational Modules Section
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
            child: Text(
              'OPERATIONAL MODULES',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
            ),
          ),

          if (sessionAllows(currentSession, 'dashboard.view'))
            ListTile(
              key: const Key('more_menu_dashboard'),
              leading: const Icon(Icons.dashboard_outlined,
                  color: AppTheme.moduleDashboard),
              title: const Text('Dashboard'),
              subtitle: const Text('Org-wide KPI & status summary'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DashboardScreen()),
                );
              },
            ),

          if (sessionAllows(currentSession, 'maintenance.view'))
            ListTile(
              key: const Key('more_menu_maintenance'),
              leading: const Icon(Icons.build_circle_outlined,
                  color: AppTheme.moduleMaintenance),
              title: const Text('Maintenance Management'),
              subtitle: const Text('Compliance & job work distribution'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MaintenanceScreen()),
                );
              },
            ),

          if (sessionAllows(currentSession, 'reports.view'))
            ListTile(
              key: const Key('more_menu_reports'),
              leading: const Icon(Icons.description_outlined,
                  color: AppTheme.moduleReports),
              title: const Text('Reports & Audit'),
              subtitle: const Text('Maintenance register & audit trail'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReportsScreen()),
                );
              },
            ),

          if (_showEnergyPlaceholder(currentSession))
            ListTile(
              key: const Key('more_menu_energy'),
              leading: const Icon(Icons.solar_power_outlined,
                  color: AppTheme.moduleEnergy),
              title: const Text('Energy & Solar'),
              subtitle: const Text('Meter readings & bills'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const EnergyPlaceholderScreen()),
                );
              },
            ),

          const Divider(height: 24),

          // Account & Preferences
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
            child: Text(
              'ACCOUNT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
            ),
          ),

          if (sessionAllows(currentSession, 'maintenance.view'))
            ListTile(
              key: const Key('more_menu_notifications'),
              leading: const Icon(Icons.notifications_outlined,
                  color: AppTheme.railwayBlue),
              title: const Text('Notifications'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const NotificationsScreen()),
                );
              },
            ),

          ListTile(
            key: const Key('more_menu_profile'),
            leading: const Icon(Icons.person_outline,
                color: AppTheme.railwayBlue),
            title: const Text('My Profile'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const UserProfileScreen()),
              );
            },
          ),

          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              key: const Key('more_menu_logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.errorRed,
                side: const BorderSide(color: AppTheme.errorRed),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                ref.read(authControllerProvider.notifier).logout();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
            ),
          ),
        ],
      ),
    );
  }
}
