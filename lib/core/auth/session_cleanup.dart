import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/assets/presentation/controllers/asset_controllers.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:gssms_mobile/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/verification_workspace_controller.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

/// Drop offline WO/record/outbox cache and in-memory list/detail providers
/// so a later login on a shared device cannot read the previous user's data.
Future<void> clearOperationalSession(Ref ref) async {
  try {
    ref.read(syncManagerProvider.notifier).invalidateSessionBoundWork();
  } catch (_) {}
  try {
    await ref.read(localCacheServiceProvider).clearAllCache();
  } catch (_) {
    // SharedPreferences may be unavailable in unit tests; still invalidate.
  }
  try {
    ref.invalidate(workOrderListControllerProvider);
    ref.invalidate(workOrderDetailControllerProvider);
    ref.invalidate(checklistControllerProvider);
    ref.invalidate(verificationWorkspaceControllerProvider);
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(reportsControllerProvider);
    ref.invalidate(complaintListControllerProvider);
    ref.invalidate(inspectionListControllerProvider);
    ref.invalidate(assetListControllerProvider);
    ref.invalidate(assetDetailControllerProvider);
    ref.invalidate(notificationsListProvider);
  } catch (_) {}
}
