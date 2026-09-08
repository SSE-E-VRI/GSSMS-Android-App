import 'package:flutter/material.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';

/// Deep-link into a Job Work only when the JWT holds `maintenance.view`.
Future<void> openWorkOrderGuarded({
  required BuildContext context,
  required UserSession? session,
  required int workOrderId,
}) async {
  if (!sessionAllows(session, 'maintenance.view')) {
    if (context.mounted) {
      showPermissionDeniedSnackBar(
        context,
        message: 'You do not have permission to view Job Works.',
      );
    }
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => WorkOrderDetailScreen(workOrderId: workOrderId),
    ),
  );
}
