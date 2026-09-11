import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/domain/models/user_session.dart';
import '../../../auth/domain/rbac.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/permission_denied_view.dart';
import '../../../complaints/presentation/screens/complaint_list_screen.dart';
import '../../../inspections/presentation/screens/inspection_list_screen.dart';
import '../../../work_orders/presentation/screens/work_order_list_screen.dart';

/// Unified Work destination hosting role-permitted work streams:
/// - Work Orders (`maintenance.view`)
/// - Complaints (`complaints.view`)
/// - Inspections (`inspections.view`)
///
/// Uses a [TabBar] when multiple streams are permitted, or renders the single
/// permitted stream directly without tab chrome.
class WorkScreen extends ConsumerWidget {
  const WorkScreen({super.key, this.session});

  final UserSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveSession =
        session ?? sessionFromAuth(ref.watch(authControllerProvider));

    final tabs = <Tab>[];
    final views = <Widget>[];

    if (sessionAllows(effectiveSession, 'maintenance.view')) {
      tabs.add(const Tab(
        text: 'Job Works',
        icon: Icon(Icons.assignment_outlined),
      ));
      views.add(const WorkOrderListScreen(isEmbedded: true));
    }
    if (sessionAllows(effectiveSession, 'complaints.view')) {
      tabs.add(const Tab(
        text: 'Complaints',
        icon: Icon(Icons.report_problem_outlined),
      ));
      views.add(const ComplaintListScreen(isEmbedded: true));
    }
    if (sessionAllows(effectiveSession, 'inspections.view')) {
      tabs.add(const Tab(
        text: 'Inspections',
        icon: Icon(Icons.fact_check_outlined),
      ));
      views.add(const InspectionListScreen(isEmbedded: true));
    }

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Work')),
        body: const PermissionDeniedView(),
      );
    }

    if (tabs.length == 1) {
      return Scaffold(
        body: views.first,
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Work Hub'),
          bottom: TabBar(
            tabs: tabs,
            isScrollable: tabs.length > 3,
            indicatorColor: AppTheme.accentOrange,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
        ),
        body: TabBarView(
          children: views,
        ),
      ),
    );
  }
}
