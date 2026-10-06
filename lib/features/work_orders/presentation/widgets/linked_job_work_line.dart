import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_navigation.dart';

/// Maps raw Job Work status string to web status label (WO_STATUS_LABELS in jobWorkStatus.js).
String jobWorkStatusLabel(String? status) {
  if (status == null || status.trim().isEmpty) return 'Job Work Linked';
  final normalized = status.trim().toUpperCase();
  switch (normalized) {
    case 'NEW':
    case 'ASSIGNED':
      return 'Assigned - Not Started';
    case 'IN_PROGRESS':
      return 'In Progress';
    case 'REWORK_REQUIRED':
      return 'Rework Required';
    case 'TECH_COMPLETED':
      return 'Pending Verification';
    case 'ON_HOLD':
      return 'On Hold';
    case 'VERIFIED':
      return 'Verified';
    case 'CLOSED':
      return 'Closed';
    case 'CANCELLED':
      return 'Cancelled';
    default:
      final woStatus = WorkOrderStatus.fromString(normalized);
      if (woStatus != WorkOrderStatus.unknown) {
        return woStatus.displayName;
      }
      return status.replaceAll('_', ' ');
  }
}

/// A compact, single-line affordance showing the linked Job Work reference and status:
/// `"Job Work <ticket> · <Job Work status label>"`
/// Tapping opens the linked Job Work screen guarded by user permissions.
class LinkedJobWorkLine extends ConsumerWidget {
  const LinkedJobWorkLine({
    super.key,
    required this.workOrderId,
    this.ticketNumber,
    this.workOrderStatus,
  });

  final int workOrderId;
  final String? ticketNumber;
  final String? workOrderStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final ticket = (ticketNumber != null && ticketNumber!.trim().isNotEmpty)
        ? ticketNumber!.trim()
        : '#$workOrderId';
    final statusLabel = jobWorkStatusLabel(workOrderStatus);

    return InkWell(
      onTap: () {
        final authState = ref.read(authControllerProvider);
        final session = authState is Authenticated ? authState.session : null;
        openWorkOrderGuarded(
          context: context,
          session: session,
          workOrderId: workOrderId,
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.link, size: 14, color: tokens.link),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Job Work $ticket · $statusLabel',
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.link,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
