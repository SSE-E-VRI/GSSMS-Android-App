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
///
/// With [preserveOfflineQueue] only stale read caches are dropped; the offline
/// outbox and cache owner are kept so the same user can sync after re-login.
/// A different user's login still wipes everything (owner mismatch).
Future<bool> clearOperationalSession(Ref ref,
    {bool preserveOfflineQueue = false}) async {
  var ok = true;
  try {
    ref.read(syncManagerProvider.notifier).invalidateSessionBoundWork();
  } catch (e) {
    debugPrint('clearOperationalSession: invalidate failed: $e');
    ok = false;
  }
  try {
    final cache = ref.read(localCacheServiceProvider);
    if (preserveOfflineQueue) {
      await cache.clearReadCache();
    } else {
      await cache.clearAllCache();
    }
  } catch (e) {
    // SharedPreferences may be unavailable in unit tests; still invalidate.
    debugPrint('clearOperationalSession: cache clear failed: $e');
    ok = false;
  }
  for (final invalidate in _invalidates) {
    try {
      invalidate(ref);
    } catch (e) {
      // One provider being listened/disposed must not abort the rest of the
      // teardown — a partial wipe is exactly what this function guards
      // against, but each provider still deserves its own attempt.
      debugPrint('clearOperationalSession: invalidate failed: $e');
      ok = false;
    }
  }
  return ok;
}

typedef _Invalidate = void Function(Ref ref);

final List<_Invalidate> _invalidates = [
  (ref) => ref.invalidate(workOrderListControllerProvider),
  (ref) => ref.invalidate(workOrderDetailControllerProvider),
  (ref) => ref.invalidate(checklistControllerProvider),
  (ref) => ref.invalidate(verificationWorkspaceControllerProvider),
  (ref) => ref.invalidate(dashboardControllerProvider),
  (ref) => ref.invalidate(reportsControllerProvider),
  (ref) => ref.invalidate(complaintListControllerProvider),
  (ref) => ref.invalidate(inspectionListControllerProvider),
  (ref) => ref.invalidate(assetListControllerProvider),
  (ref) => ref.invalidate(assetDetailControllerProvider),
  (ref) => ref.invalidate(notificationsListProvider),
];
