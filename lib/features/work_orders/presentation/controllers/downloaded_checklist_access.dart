import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

/// Grants access only to an already downloaded checklist for its technician.
/// This never manufactures a server transition or authorizes replay.
final downloadedChecklistAccessProvider =
    FutureProvider.autoDispose.family<bool, WorkOrder>((ref, order) async {
  final session = sessionFromAuth(ref.watch(authControllerProvider));
  final userId = session?.userId;
  if (userId == null ||
      !canWriteChecklist(session) ||
      order.assignedToId != userId ||
      order.status != WorkOrderStatus.inProgress ||
      order.linkedRecordId == null) {
    return false;
  }
  final cache = ref.read(localCacheServiceProvider);
  if (await cache.getCacheOwnerUserId() != userId) return false;
  final record = await cache.getCachedMaintenanceRecord(order.linkedRecordId!);
  return record != null &&
      record.id == order.linkedRecordId &&
      record.workOrderId == order.id &&
      await cache.getCacheOwnerUserId() == userId;
});
