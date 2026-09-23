import 'package:flutter/foundation.dart';
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
/// Returns true when the wipe fully succeeded; false when cache clearing
/// failed (caller should surface it — a failed wipe leaks prior user data).
Future<bool> clearOperationalSession(Ref ref) async {
  var ok = true;
  try {
    ref.read(syncManagerProvider.notifier).invalidateSessionBoundWork();
  } catch (e) {
    debugPrint('clearOperationalSession: invalidate failed: $e');
    ok = false;
  }
  try {
    await ref.read(localCacheServiceProvider).clearAllCache();
  } catch (e) {
    // SharedPreferences may be unavailable in unit tests; still invalidate.
    debugPrint('clearOperationalSession: clearAllCache failed: $e');
    ok = false;
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
  } catch (e) {
    debugPrint('clearOperationalSession: invalidate providers failed: $e');
    ok = false;
  }
  return ok;
}
