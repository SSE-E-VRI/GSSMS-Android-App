import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/technician.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/verification_workspace_screen.dart';
import 'package:gssms_mobile/features/work_orders/services/work_order_pdf_service.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

class WorkOrderDetailScreen extends ConsumerStatefulWidget {
  const WorkOrderDetailScreen({super.key, required this.workOrderId});

  final int workOrderId;

  @override
  ConsumerState<WorkOrderDetailScreen> createState() => _WorkOrderDetailScreenState();
}

class _WorkOrderDetailScreenState extends ConsumerState<WorkOrderDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)), 'maintenance.view')) {
        return;
      }
      ref
          .read(workOrderDetailControllerProvider(widget.workOrderId).notifier)
          .loadDetail();
    });
  }

  @override
  Widget build(BuildContext context) {
    final detailState =
        ref.watch(workOrderDetailControllerProvider(widget.workOrderId));
    final authState = ref.watch(authControllerProvider);
    final userSession = sessionFromAuth(authState);

    if (!sessionAllows(userSession, 'maintenance.view')) {
      return Scaffold(
        appBar: AppBar(title: Text('Work Order #${widget.workOrderId}')),
        body: const PermissionDeniedView(),
      );
    }

    ref.listen(workOrderDetailControllerProvider(widget.workOrderId), (prev, next) {
      if (next is WorkOrderDetailLoaded && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Work Order #${widget.workOrderId}'),
        actions: [
          // Web per-row PDF action — share/print the Job Work sheet.
          if (canExportPdf(userSession))
            IconButton(
            key: const Key('work_order_pdf_button'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
            onPressed: detailState is WorkOrderDetailLoaded
                ? () => _exportPdf(detailState)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh work order details',
            onPressed: () => ref
                .read(workOrderDetailControllerProvider(widget.workOrderId).notifier)
                .loadDetail(),
          ),
        ],
      ),
      body: _buildBody(detailState, userSession),
      bottomNavigationBar: _buildBottomActions(detailState, userSession),
    );
  }

  Future<void> _exportPdf(WorkOrderDetailLoaded loaded) async {
    try {
      final doc = await WorkOrderPdfService.build(
        loaded.workOrder,
        audit: loaded.audit,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name:
            'JobWork_${loaded.workOrder.displayReference.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to export PDF: $e'),
              backgroundColor: AppTheme.errorRed),
        );
      }
    }
  }

  Widget _buildBody(WorkOrderDetailState state, dynamic session) {
    if (state is WorkOrderDetailLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is WorkOrderDetailError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.errorRed),
              const SizedBox(height: 12),
              Text(
                state.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .read(workOrderDetailControllerProvider(widget.workOrderId).notifier)
                    .loadDetail(),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is WorkOrderDetailLoaded) {
      final wo = state.workOrder;
      final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusHeader(wo),
            const SizedBox(height: 16),
            _buildAssetSection(wo),
            const SizedBox(height: 16),
            _buildScheduleSection(wo, dateFormat),
            const SizedBox(height: 16),
            if (wo.description != null && wo.description!.isNotEmpty) ...[
              _buildDescriptionSection(wo),
              const SizedBox(height: 16),
            ],
            if (state.audit != null && state.audit!.events.isNotEmpty) ...[
              _buildAuditTimeline(state.audit!, dateFormat),
              const SizedBox(height: 16),
            ] else if (wo.latestEventSummary != null) ...[
              // Fall back to the summary the list payload carries when the full
              // history could not be loaded (offline, or no audit permission).
              _buildTimelineSection(wo.latestEventSummary!, dateFormat),
              const SizedBox(height: 16),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildStatusHeader(WorkOrder wo) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    wo.status.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  backgroundColor: _getStatusColor(wo.status),
                ),
                Chip(
                  label: Text('Priority: ${wo.priority.displayName}'),
                  backgroundColor: _getPriorityColor(wo.priority).withOpacity(0.15),
                  side: BorderSide(color: _getPriorityColor(wo.priority)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              wo.displayReference,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.railwayBlue,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              wo.displayTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Type: ${wo.type.displayName}',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            if (wo.isSlaAtRisk) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppTheme.errorRed),
                  const SizedBox(width: 4),
                  Text(
                    'SLA ${wo.slaStatus}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.errorRed,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAssetSection(WorkOrder wo) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Asset & Location Details',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            _infoRow('Asset', wo.assetName ?? 'N/A'),
            if (wo.assetCriticality != null) _infoRow('Criticality', wo.assetCriticality!),
            _infoRow('Station', wo.stationName ?? 'N/A'),
            _infoRow('Depot', wo.depotName ?? 'N/A'),
            if (wo.infrastructureName != null)
              _infoRow('Infrastructure', '${wo.infrastructureName} (${wo.infrastructureType ?? "N/A"})'),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleSection(WorkOrder wo, DateFormat dateFormat) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assignment & Schedule',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            _infoRow('Assigned Technician', wo.assignedToName ?? 'Unassigned'),
            _infoRow('Reported By', wo.reportedByName ?? 'System'),
            if (wo.verifiedByName != null) _infoRow('Verified By', wo.verifiedByName!),
            if (wo.dueDate != null) _infoRow('Due Date', DateFormat('dd MMM yyyy').format(wo.dueDate!)),
            if (wo.createdAt != null) _infoRow('Created At', dateFormat.format(wo.createdAt!)),
            if (wo.reportCompletedAt != null)
              _infoRow('Tech Completed At', dateFormat.format(wo.reportCompletedAt!)),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionSection(WorkOrder wo) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Remarks / Notes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            Text(wo.description!, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  /// Full status history, newest first — MVP capability 9 (work-order audit
  /// timeline). Returns are highlighted because a rework loop is the thing a
  /// technician most needs to spot when picking a job back up.
  Widget _buildAuditTimeline(WorkOrderAudit audit, DateFormat dateFormat) {
    final events = audit.eventsNewestFirst;

    return Card(
      key: const Key('work_order_audit_timeline'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (audit.returnCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Returned ${audit.returnCount}x',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.errorRed,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 20),
            for (var i = 0; i < events.length; i++)
              _buildAuditRow(events[i], dateFormat, isLast: i == events.length - 1),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditRow(
    WorkOrderAuditEvent event,
    DateFormat dateFormat, {
    required bool isLast,
  }) {
    final color = event.isReturn ? AppTheme.errorRed : AppTheme.railwayBlue;
    final transition = (event.fromState != null && event.toState != null)
        ? '${WorkOrderStatus.fromString(event.fromState).displayName} → '
            '${WorkOrderStatus.fromString(event.toState).displayName}'
        : (event.toState != null
            ? WorkOrderStatus.fromString(event.toState).displayName
            : event.eventType);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: Colors.grey.shade300),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transition,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (event.actor != null) event.actor,
                      if (event.actorRole != null) '(${event.actorRole})',
                      if (event.timestamp != null) dateFormat.format(event.timestamp!),
                    ].whereType<String>().join(' · '),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  if (event.reason != null && event.reason!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      event.reason!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSection(WorkOrderEventSummary event, DateFormat dateFormat) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Latest Activity Event',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            _infoRow('Event', event.eventType),
            _infoRow('Actor', event.actor),
            if (event.createdAt != null) _infoRow('Timestamp', dateFormat.format(event.createdAt!)),
            if (event.remarks != null && event.remarks!.isNotEmpty)
              _infoRow('Remarks', event.remarks!),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  /// Bottom action bar: server `allowed` transitions, plus Start Execution /
  /// Open Checklist only when `maintenance.edit` and the matching allowed
  /// action is present. Status alone never shows a mutating control.
  Widget? _buildBottomActions(
      WorkOrderDetailState state, UserSession? session) {
    if (state is! WorkOrderDetailLoaded) return null;
    final wo = state.workOrder;
    final actions = <Widget>[];
    final canEdit = sessionAllows(session, 'maintenance.edit');
    final canChecklist = canWriteChecklist(session);
    final allowed = state.actions;

    final needsExecutionStart = wo.status == WorkOrderStatus.assigned ||
        wo.status == WorkOrderStatus.reworkRequired ||
        (wo.status == WorkOrderStatus.inProgress && wo.linkedRecordId == null);
    final canStart = canEdit &&
        needsExecutionStart &&
        (allowed?.allowsTarget('IN_PROGRESS') ?? false);
    if (canStart) {
      actions.add(
        Expanded(
          child: ElevatedButton.icon(
            key: const Key('action_start_execution'),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Execution'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.railwayBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: state.isTransitioning ? null : _startExecution,
          ),
        ),
      );
    } else if (canChecklist &&
        wo.status == WorkOrderStatus.inProgress &&
        ((allowed?.allowsTarget('TECH_COMPLETED') ?? false) ||
            (allowed?.allowsTarget('IN_PROGRESS') ?? false))) {
      actions.add(
        Expanded(
          child: ElevatedButton.icon(
            key: const Key('action_open_checklist'),
            icon: const Icon(Icons.checklist),
            label: const Text('Open Checklist'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.railwayBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () {
              final recordId = wo.linkedRecordId;
              if (recordId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No maintenance record linked to this work order yet.'),
                  ),
                );
                return;
              }
              unawaited(Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChecklistScreen(recordId: recordId),
                ),
              ));
            },
          ),
        ),
      );
    }

    // RBAC-06: defence in depth. The server's `allowed-actions` payload is
    // already role/scope-aware (WorkOrderLifecycleService.can_transition), so
    // this loop is not reachable by an under-permissioned session today — but
    // every other mutating control on this screen is gated by `canEdit`
    // first, and this was the one that wasn't. "Status alone never shows a
    // mutating control" (see the doc comment above) should hold even if the
    // server payload is ever stale or malformed.
    for (final action in canEdit ? (state.actions?.allowed ?? const []) : const <WorkOrderAction>[]) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 12));
      actions.add(
        Expanded(
          child: ElevatedButton(
            key: Key('action_${action.targetStatus.toLowerCase()}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _actionColor(action.targetStatus),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: state.isTransitioning
                ? null
                : () => _onAllowedAction(action),
            child: Text(_actionLabel(action), textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (actions.isEmpty) return null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(children: actions),
    );
  }

  // The server labels the NEW → ASSIGNED transition "Assigned" (the resulting
  // state), but tapping it only opens the technician picker — nothing is
  // assigned yet. "Assign" reads as the action the button performs.
  String _actionLabel(WorkOrderAction action) {
    if (action.targetStatus.toUpperCase() == 'ASSIGNED') return 'Assign';
    return action.label;
  }

  Color _actionColor(String targetStatus) {
    switch (targetStatus.toUpperCase()) {
      case 'REWORK_REQUIRED':
      case 'CANCELLED':
        return AppTheme.errorRed;
      case 'ON_HOLD':
        return Colors.amber.shade800;
      default:
        return AppTheme.railwayGreen;
    }
  }

  Future<void> _startExecution() async {
    final recordId = await ref
        .read(workOrderDetailControllerProvider(widget.workOrderId).notifier)
        .startExecution();
    if (!mounted) return;
    if (recordId != null) {
      unawaited(Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChecklistScreen(recordId: recordId),
        ),
      ));
      return;
    }
    // Offline-queued (not a hard failure) leaves an informational message on
    // the reloaded WorkOrderDetailLoaded state instead of a WorkOrderDetailError.
    final current = ref.read(workOrderDetailControllerProvider(widget.workOrderId));
    if (current is WorkOrderDetailLoaded && current.actionMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(current.actionMessage!)),
      );
    }
  }

  void _onAllowedAction(WorkOrderAction action) {
    switch (action.targetStatus.toUpperCase()) {
      case 'ASSIGNED':
        _showAssignTechnicianDialog();
        return;
      case 'VERIFIED':
        unawaited(Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                VerificationWorkspaceScreen(workOrderId: widget.workOrderId),
          ),
        ));
        return;
      default:
        _showTransitionDialog(action);
    }
  }

  Future<void> _showAssignTechnicianDialog() async {
    final controller =
        ref.read(workOrderDetailControllerProvider(widget.workOrderId).notifier);

    List<Technician>? technicians;
    String? loadError;
    try {
      technicians = await controller.fetchAssignableTechnicians();
    } catch (e) {
      loadError = workOrderReadableError(e);
    }
    if (!mounted) return;

    int? selectedId;
    final errorMessage = loadError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Assign technician'),
          content: errorMessage != null
              ? Text(
                  key: const Key('assign_technician_error'),
                  errorMessage,
                )
              : (technicians == null || technicians.isEmpty)
                  ? const Text(
                      key: Key('assign_technician_empty'),
                      'No maintenance staff available to assign.',
                    )
                  : DropdownButtonFormField<int>(
                      key: const Key('assign_technician_dropdown'),
                      decoration: const InputDecoration(
                        labelText: 'Technician',
                      ),
                      value: selectedId,
                      items: technicians
                          .map(
                            (t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(t.name),
                            ),
                          )
                          .toList(),
                      onChanged: (id) => setState(() => selectedId = id),
                    ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const Key('assign_technician_confirm'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(88, 48),
              ),
              onPressed: selectedId == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      unawaited(controller.assignAndActivate(selectedId!));
                    },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  /// Confirmation for a server-offered transition. Remarks are mandatory when
  /// the server marks the action `requires_reason`, so the write is not sent
  /// only to come back as a validation error.
  ///
  /// VERIFIED and CLOSED are high-risk terminal transitions (§7.2, §8.3) and
  /// require an explicit second confirmation. Full biometric/TOTP integration
  /// (local_auth + /auth/totp/verify) is planned for Phase 2; this gate enforces
  /// the UX contract now so the server never receives an accidental terminal
  /// transition.
  void _showTransitionDialog(WorkOrderAction action) {
    final textController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final isHighRisk = action.targetStatus.toUpperCase() == 'VERIFIED' ||
        action.targetStatus.toUpperCase() == 'CLOSED';
    bool highRiskConfirmed = false;

    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(action.label),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (action.requiresFailureCode)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'This work order is on a CRITICAL/HIGH asset, so the server '
                      'requires a failure code and restored time on it before this '
                      'transition is allowed (ISO 55000). Neither can be recorded '
                      'from the app yet — record them in the web console first, or '
                      'this action will be rejected.',
                      style: TextStyle(fontSize: 12, color: AppTheme.errorRed),
                    ),
                  ),
                TextFormField(
                  key: const Key('transition_remarks_field'),
                  controller: textController,
                  decoration: InputDecoration(
                    labelText: action.requiresReason ? 'Remarks *' : 'Remarks (optional)',
                    hintText: 'Add notes for this status change',
                  ),
                  maxLines: 3,
                  validator: (val) {
                    if (action.requiresReason && (val == null || val.trim().isEmpty)) {
                      return 'Remarks are required for this action';
                    }
                    return null;
                  },
                ),
                if (isHighRisk) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.verified_user, size: 18, color: Colors.amber.shade800),
                            const SizedBox(width: 6),
                            const Text('High-risk transition', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'VERIFIED / CLOSED ends the audit trail. Biometric or TOTP confirmation will be required here (Phase 2). Please confirm you intend to permanently close this work.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => setState(() => highRiskConfirmed = !highRiskConfirmed),
                          borderRadius: BorderRadius.circular(4),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Row(
                              children: [
                                Checkbox(
                                  key: const Key('high_risk_confirm_checkbox'),
                                  value: highRiskConfirmed,
                                  onChanged: (v) => setState(() => highRiskConfirmed = v ?? false),
                                ),
                                const Expanded(child: Text('I confirm this terminal transition', style: TextStyle(fontSize: 12))),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const Key('transition_confirm_button'),
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                if (isHighRisk && !highRiskConfirmed) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Please confirm the high-risk transition'), backgroundColor: AppTheme.errorRed),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                unawaited(ref
                    .read(workOrderDetailControllerProvider(widget.workOrderId).notifier)
                    .transitionStatus(
                      status: action.targetStatus,
                      remarks: textController.text.trim(),
                    ));
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    ).whenComplete(textController.dispose));
  }

  Color _getStatusColor(WorkOrderStatus status) {
    switch (status) {
      case WorkOrderStatus.newOrder:
        return Colors.blueGrey;
      case WorkOrderStatus.assigned:
        return Colors.blue;
      case WorkOrderStatus.inProgress:
        return Colors.orange;
      case WorkOrderStatus.techCompleted:
        return Colors.teal;
      case WorkOrderStatus.verified:
      case WorkOrderStatus.closed:
        return AppTheme.railwayGreen;
      case WorkOrderStatus.reworkRequired:
        return AppTheme.errorRed;
      case WorkOrderStatus.onHold:
        return Colors.amber.shade800;
      case WorkOrderStatus.cancelled:
        return Colors.grey;
      case WorkOrderStatus.unknown:
        return Colors.grey;
    }
  }

  Color _getPriorityColor(WorkOrderPriority priority) {
    switch (priority) {
      case WorkOrderPriority.critical:
        return Colors.red.shade900;
      case WorkOrderPriority.high:
        return AppTheme.errorRed;
      case WorkOrderPriority.medium:
        return Colors.orange.shade700;
      case WorkOrderPriority.low:
        return Colors.green;
    }
  }
}
