import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_mode_controller.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../../auth/domain/models/auth_role.dart';
import '../../../auth/domain/models/user_session.dart';
import '../../../auth/domain/rbac.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/screens/user_profile_screen.dart';
import '../../../auth/presentation/widgets/sign_out_confirmation.dart';
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
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;

    void open(Widget screen) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    Widget moduleTile({
      required Key key,
      required IconData icon,
      required Color color,
      required String title,
      String? subtitle,
      required Widget screen,
    }) {
      return ListTile(
        key: key,
        leading: Icon(icon, color: context.moduleColor(color)),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right, size: GssmsSize.iconMd),
        onTap: () => open(screen),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('More Operations'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: GssmsSpacing.s16),
        children: [
          // Profile card — deliberately the brand navy in both themes so it
          // reads as the identity header, matching the app bar.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GssmsSpacing.s16),
            child: Material(
              color: AppTheme.primaryDark,
              borderRadius: BorderRadius.circular(GssmsRadius.r12),
              child: InkWell(
                key: const Key('more_profile_card'),
                borderRadius: BorderRadius.circular(GssmsRadius.r12),
                onTap: () => open(const UserProfileScreen()),
                child: Padding(
                  padding: const EdgeInsets.all(GssmsSpacing.s16),
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
                      const SizedBox(width: GssmsSpacing.s16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentSession.displayName,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: GssmsSpacing.s2),
                            Text(
                              currentSession.primaryRole.displayName,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withOpacity(0.85),
                                height: 1.15,
                              ),
                            ),
                            if (currentSession.depotName != null) ...[
                              const SizedBox(height: GssmsSpacing.s2),
                              Text(
                                currentSession.depotName!,
                                style: textTheme.labelSmall?.copyWith(
                                  color: Colors.white.withOpacity(0.75),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: GssmsSpacing.s16),

          const _SectionLabel('OPERATIONAL MODULES'),
          if (sessionAllows(currentSession, 'dashboard.view'))
            moduleTile(
              key: const Key('more_menu_dashboard'),
              icon: Icons.dashboard_outlined,
              color: AppTheme.moduleDashboard,
              title: 'Dashboard',
              subtitle: 'Org-wide KPI & status summary',
              screen: const DashboardScreen(),
            ),
          if (sessionAllows(currentSession, 'maintenance.view'))
            moduleTile(
              key: const Key('more_menu_maintenance'),
              icon: Icons.build_circle_outlined,
              color: AppTheme.moduleMaintenance,
              title: 'Maintenance Management',
              subtitle: 'Compliance & job work distribution',
              screen: const MaintenanceScreen(),
            ),
          if (sessionAllows(currentSession, 'reports.view'))
            moduleTile(
              key: const Key('more_menu_reports'),
              icon: Icons.description_outlined,
              color: AppTheme.moduleReports,
              title: 'Reports & Audit',
              subtitle: 'Maintenance register & audit trail',
              screen: const ReportsScreen(),
            ),
          if (_showEnergyPlaceholder(currentSession))
            moduleTile(
              key: const Key('more_menu_energy'),
              icon: Icons.solar_power_outlined,
              color: AppTheme.moduleEnergy,
              title: 'Energy & Solar',
              subtitle: 'Meter readings & bills',
              screen: const EnergyPlaceholderScreen(),
            ),

          const Divider(height: GssmsSpacing.s24),

          const _SectionLabel('APPEARANCE'),
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: GssmsSpacing.s16,
              vertical: GssmsSpacing.s8,
            ),
            child: _ThemeModeSelector(),
          ),

          const Divider(height: GssmsSpacing.s24),

          const _SectionLabel('ACCOUNT'),
          if (sessionAllows(currentSession, 'maintenance.view'))
            ListTile(
              key: const Key('more_menu_notifications'),
              leading: Icon(Icons.notifications_outlined, color: tokens.link),
              title: const Text('Notifications'),
              trailing: const Icon(Icons.chevron_right, size: GssmsSize.iconMd),
              onTap: () => open(const NotificationsScreen()),
            ),
          ListTile(
            key: const Key('more_menu_profile'),
            leading: Icon(Icons.person_outline, color: tokens.link),
            title: const Text('My Profile'),
            trailing: const Icon(Icons.chevron_right, size: GssmsSize.iconMd),
            onTap: () => open(const UserProfileScreen()),
          ),

          const SizedBox(height: GssmsSpacing.s12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GssmsSpacing.s16),
            child: OutlinedButton.icon(
              key: const Key('more_menu_logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.danger.foreground,
                side: BorderSide(color: tokens.danger.border),
              ),
              onPressed: () => confirmAndSignOut(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GssmsSpacing.s20,
        GssmsSpacing.s8,
        GssmsSpacing.s16,
        GssmsSpacing.s4,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.gssms.textSecondary,
                letterSpacing: 0.6,
              ),
        ),
      ),
    );
  }
}

/// System / Light / Dark. Applies immediately (no restart) and is persisted by
/// [ThemeModeController].
class _ThemeModeSelector extends ConsumerWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SegmentedButton<ThemeMode>(
      key: const Key('more_theme_mode_selector'),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          icon: Icon(Icons.brightness_auto_outlined),
          label: Text('System'),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode_outlined),
          label: Text('Light'),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode_outlined),
          label: Text('Dark'),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selection) {
        unawaited(
          ref.read(themeModeProvider.notifier).setThemeMode(selection.first),
        );
      },
    );
  }
}
