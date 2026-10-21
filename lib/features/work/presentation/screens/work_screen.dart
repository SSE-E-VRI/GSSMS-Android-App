import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/gssms_spacing.dart';
import '../../../auth/domain/models/user_session.dart';
import '../../../auth/domain/rbac.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/permission_denied_view.dart';
import '../../../complaints/presentation/screens/complaint_list_screen.dart';
import '../../../deficiencies/presentation/screens/deficiency_list_screen.dart';
import '../../../inspections/presentation/screens/inspection_list_screen.dart';
import '../../../work_orders/presentation/screens/work_order_list_screen.dart';

/// Unified Work destination hosting role-permitted work streams:
/// - Work Orders (`maintenance.view`)
/// - Breakdowns (`complaints.view`)
/// - Inspections (`inspections.view`)
/// - Deficiencies (`assets.view`)
///
/// Uses an inline filter-pill row ([ChoiceChip]s) when multiple streams are permitted,
/// or renders the single permitted stream directly without tab chrome.
class WorkScreen extends ConsumerStatefulWidget {
  const WorkScreen({super.key, this.session});

  final UserSession? session;

  @override
  ConsumerState<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends ConsumerState<WorkScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final effectiveSession =
        widget.session ?? sessionFromAuth(ref.watch(authControllerProvider));

    final items = <_WorkStreamItem>[];

    if (sessionAllows(effectiveSession, 'maintenance.view')) {
      items.add(const _WorkStreamItem(
        label: 'Job Works',
        icon: Icons.assignment_outlined,
        widget: WorkOrderListScreen(isEmbedded: true),
      ));
    }
    if (sessionAllows(effectiveSession, 'complaints.view')) {
      items.add(const _WorkStreamItem(
        label: 'Breakdowns',
        icon: Icons.report_problem_outlined,
        widget: ComplaintListScreen(isEmbedded: true),
      ));
    }
    if (sessionAllows(effectiveSession, 'inspections.view')) {
      items.add(const _WorkStreamItem(
        label: 'Inspections',
        icon: Icons.fact_check_outlined,
        widget: InspectionListScreen(isEmbedded: true),
      ));
    }
    if (canViewDeficiencyModule(effectiveSession)) {
      items.add(const _WorkStreamItem(
        label: 'Deficiencies',
        icon: Icons.rule_outlined,
        widget: DeficiencyListScreen(isEmbedded: true),
      ));
    }

    if (items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Work')),
        body: const PermissionDeniedView(),
      );
    }

    if (items.length == 1) {
      return Scaffold(
        body: items.first.widget,
      );
    }

    final currentIndex = _selectedIndex.clamp(0, items.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Hub'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: GssmsSpacing.s16,
              vertical: GssmsSpacing.s8,
            ),
            child: Row(
              children: [
                for (int i = 0; i < items.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: i < items.length - 1 ? GssmsSpacing.s8 : 0,
                    ),
                    child: ChoiceChip(
                      avatar: Icon(items[i].icon, size: 18),
                      label: Text(items[i].label),
                      selected: currentIndex == i,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedIndex = i);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: currentIndex,
              children: items.map((e) => e.widget).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkStreamItem {
  const _WorkStreamItem({
    required this.label,
    required this.icon,
    required this.widget,
  });

  final String label;
  final IconData icon;
  final Widget widget;
}
