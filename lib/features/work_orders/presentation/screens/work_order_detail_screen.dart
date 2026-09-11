import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/empty_state_view.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/skeleton_list.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/core/widgets/sticky_action_bar.dart';
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
import 'package:gssms_mobile/features/work_orders/presentation/work_order_status_style.dart';
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
  static final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  WorkOrderDetailController get _controller =>
      ref.read(workOrderDetailControllerProvider(widget.workOrderId).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)), 'maintenance.view')) {
        return;
      }
      _controller.loadDetail();
    });
  }

  @override
  Widget build(BuildContext context) {
    final detailState =
        ref.watch(workOrderDetailControllerProvider(widget.workOrderId));
    final userSession = sessionFromAuth(ref.watch(authControllerProvider));

    if (!sessionAllows(userSession, 'maintenance.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job Work')),
        body: const PermissionDeniedView(),
      );
    }

    ref.listen(workOrderDetailControllerProvider(widget.workOrderId), (prev, next) {
      if (next is WorkOrderDetailLoaded && next.errorMessage != null) {
        final tokens = context.gssms;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next.errorMessage!,
              style: TextStyle(color: tokens.danger.onSolid),
            ),
            backgroundColor: tokens.danger.solid,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Work'),
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
            tooltip: 'Refresh job work details',
            onPressed: _controller.loadDetail,
          ),
        ],
      ),
      body: _buildBody(detailState),
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
          SnackBar(content: Text('Could not export the PDF. ${userFacingError(e)}')),
        );
      }
    }
  }

  Widget _buildBody(WorkOrderDetailState state) {
    if (state is WorkOrderDetailLoading) {
      return const SingleChildScrollView(
        padding: EdgeInsets.only(top: GssmsSpacing.s8),
        child: SkeletonList(itemCount: 3),
      );
    }

    if (state is WorkOrderDetailError) {
      return EmptyStateView.error(
        title: 'Could not load this job work',
        message: state.message,
        onRetry: _controller.loadDetail,
      );
    }

    if (state is WorkOrderDetailLoaded) {
      final wo = state.workOrder;
      // Eager scroll view: a handful of sections, and every one of them should
      // exist for screen readers and find-in-page, not only what is on screen.
      return RefreshIndicator(
        onRefresh: _controller.loadDetail,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(GssmsSpacing.s16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusHeader(wo),
            const SizedBox(height: GssmsSpacing.s12),
            _buildAssetSection(wo),
            const SizedBox(height: GssmsSpacing.s12),
            _buildScheduleSection(wo),
            if (wo.description != null && wo.description!.isNotEmpty) ...[
              const SizedBox(height: GssmsSpacing.s12),
              SectionCard(
                title: 'Remarks / Notes',
                icon: Icons.notes_outlined,
                children: [TextWell(text: wo.description)],
              ),
            ],
            if (state.audit != null && state.audit!.events.isNotEmpty) ...[
              const SizedBox(height: GssmsSpacing.s12),
              _buildAuditTimeline(state.audit!),
            ] else if (wo.latestEventSummary != null) ...[
              // Fall back to the summary the list payload carries when the full
              // history could not be loaded (offline, or no audit permission).
              const SizedBox(height: GssmsSpacing.s12),
              _buildTimelineSection(wo.latestEventSummary!),
            ],
            const SizedBox(height: GssmsSpacing.s16),
          ],
        ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// WHAT IS THIS / WHAT STATE IS IT IN — reference, status and title first.
  Widget _buildStatusHeader(WorkOrder wo) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    return SectionCard(
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: GssmsSpacing.s8,
          runSpacing: GssmsSpacing.s4,
          children: [
            Text(
              wo.displayReference,
              style: textTheme.labelLarge?.copyWith(color: tokens.link),
            ),
            WorkOrderStatusChip(status: wo.status, filled: true),
          ],
        ),
        const SizedBox(height: GssmsSpacing.s8),
        Text(wo.displayTitle, style: textTheme.titleLarge),
        const SizedBox(height: GssmsSpacing.s12),
        Wrap(
          spacing: GssmsSpacing.s8,
          runSpacing: GssmsSpacing.s8,
          children: [
            WorkOrderPriorityChip(priority: wo.priority),
            StatusChip(label: wo.type.displayName, icon: Icons.category_outlined),
            if (wo.isSlaAtRisk)
              StatusChip(
                label: 'SLA ${wo.slaStatus!.replaceAll('_', ' ').toLowerCase()}',
                tone: GssmsTone.danger,
                icon: Icons.timer_off_outlined,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAssetSection(WorkOrder wo) {
    return SectionCard(
      title: 'Asset & Location Details',
      icon: Icons.precision_manufacturing_outlined,
      children: [
        InfoRow(label: 'Asset', value: wo.assetName, emptyText: 'Not linked'),
        if (wo.assetCriticality != null)
          InfoRow(label: 'Criticality', value: wo.assetCriticality),
        InfoRow(label: 'Station', value: wo.stationName),
        InfoRow(label: 'Depot', value: wo.depotName),
        if (wo.infrastructureName != null)
          InfoRow(
            label: 'Infrastructure',
            value: wo.infrastructureType == null
                ? wo.infrastructureName
                : '${wo.infrastructureName} (${wo.infrastructureType})',
          ),
      ],
    );
  }

  Widget _buildScheduleSection(WorkOrder wo) {
    return SectionCard(
      title: 'Assignment & Schedule',
      icon: Icons.event_note_outlined,
      children: [
        InfoRow(
          label: 'Assigned Technician',
          value: wo.assignedToName,
          emptyText: 'Unassigned',
        ),
        InfoRow(label: 'Reported By', value: wo.reportedByName, emptyText: 'System'),
        if (wo.verifiedByName != null)
          InfoRow(label: 'Verified By', value: wo.verifiedByName),
        if (wo.dueDate != null)
          InfoRow(label: 'Due Date', value: _dateFormat.format(wo.dueDate!)),
        if (wo.createdAt != null)
          InfoRow(label: 'Created', value: _dateTimeFormat.format(wo.createdAt!)),
        if (wo.reportCompletedAt != null)
          InfoRow(
            label: 'Technician Completed',
            value: _dateTimeFormat.format(wo.reportCompletedAt!),
          ),
      ],
    );
  }

  /// Full status history, newest first — MVP capability 9 (work-order audit
  /// timeline). Returns are highlighted because a rework loop is the thing a
  /// technician most needs to spot when picking a job back up.
  Widget _buildAuditTimeline(WorkOrderAudit audit) {
    final events = audit.eventsNewestFirst;
    return SectionCard(
      key: const Key('work_order_audit_timeline'),
      title: 'History',
      icon: Icons.history,
      trailing: audit.returnCount > 0
          ? StatusChip(
              label: 'Returned ${audit.returnCount}x',
              tone: GssmsTone.danger,
              icon: Icons.replay,
            )
          : null,
      children: [
        for (var i = 0; i < events.length; i++)
          _AuditRow(
            event: events[i],
            isLast: i == events.length - 1,
            dateFormat: _dateTimeFormat,
          ),
      ],
    );
  }

  Widget _buildTimelineSection(WorkOrderEventSummary event) {
    return SectionCard(
      title: 'Latest Activity',
      icon: Icons.history,
      children: [
        InfoRow(label: 'Event', value: event.eventType),
        InfoRow(label: 'Actor', value: event.actor),
        if (event.createdAt != null)
          InfoRow(label: 'Timestamp', value: _dateTimeFormat.format(event.createdAt!)),
        if (event.remarks != null && event.remarks!.isNotEmpty)
          InfoRow(label: 'Remarks', value: event.remarks),
      ],
    );
  }

  /// Bottom action bar: server `allowed` transitions, plus Start Execution /
  /// Open Checklist only when `maintenance.edit` and the matching allowed
  /// action is present. Status alone never shows a mutating control.
  Widget? _buildBottomActions(WorkOrderDetailState state, UserSession? session) {
    if (state is! WorkOrderDetailLoaded) return null;
    final wo = state.workOrder;
    final canEdit = sessionAllows(session, 'maintenance.edit');
    final canChecklist = canWriteChecklist(session);
    final allowed = state.actions;
    final busy = state.isTransitioning;

    final needsExecutionStart = wo.status == WorkOrderStatus.assigned ||
        wo.status == WorkOrderStatus.reworkRequired ||
        (wo.status == WorkOrderStatus.inProgress && wo.linkedRecordId == null);
    final canStart = canEdit &&
        needsExecutionStart &&
        (allowed?.allowsTarget('IN_PROGRESS') ?? false);

    Widget? primary;
    if (canStart) {
      primary = FilledButton.icon(
        key: const Key('action_start_execution'),
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow),
        label: Text(busy ? (state.actionMessage ?? 'Working…') : 'Start Execution'),
        onPressed: busy ? null : _startExecution,
      );
    } else if (canChecklist &&
        wo.status == WorkOrderStatus.inProgress &&
        ((allowed?.allowsTarget('TECH_COMPLETED') ?? false) ||
            (allowed?.allowsTarget('IN_PROGRESS') ?? false))) {
      primary = FilledButton.icon(
        key: const Key('action_open_checklist'),
        icon: const Icon(Icons.checklist),
        label: const Text('Open Checklist'),
        onPressed: () {
          final recordId = wo.linkedRecordId;
          if (recordId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No maintenance record is linked to this job work yet.'),
              ),
            );
            return;
          }
          unawaited(Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ChecklistScreen(recordId: recordId)),
          ));
        },
      );
    }

    // RBAC-06: defence in depth — every mutating control is gated by canEdit
    // even though the server's allowed-actions payload is role-aware.
    final serverActions = canEdit
        ? (state.actions?.allowed ?? const <WorkOrderAction>[])
            // Start Execution already performs the IN_PROGRESS transition
            // through the execute endpoint (which also creates the
            // maintenance record); a second raw "Start" button would offer a
            // path that skips the record.
            .where((a) => !(canStart && a.targetStatus.toUpperCase() == 'IN_PROGRESS'))
            .toList()
        : const <WorkOrderAction>[];

    final secondary = [
      for (final action in serverActions)
        _ServerActionButton(
          action: action,
          label: _actionLabel(action),
          filled: primary == null && serverActions.length == 1,
          onPressed: busy ? null : () => _onAllowedAction(action),
        ),
    ];

    if (primary == null && secondary.isEmpty) return null;
    return StickyActionBar(child: primary, children: secondary);
  }

  // The server labels the NEW → ASSIGNED transition "Assigned" (the resulting
  // state), but tapping it only opens the technician picker — nothing is
  // assigned yet. "Assign" reads as the action the button performs.
  String _actionLabel(WorkOrderAction action) {
    if (action.targetStatus.toUpperCase() == 'ASSIGNED') return 'Assign';
    return action.label;
  }

  Future<void> _startExecution() async {
    final recordId = await _controller.startExecution();
    if (!mounted) return;
    if (recordId != null) {
      unawaited(Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChecklistScreen(recordId: recordId)),
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
            builder: (_) => VerificationWorkspaceScreen(workOrderId: widget.workOrderId),
          ),
        ));
        return;
      default:
        _showTransitionDialog(action);
    }
  }

  /// Opens immediately with a loading state (the technician lookup used to run
  /// before the dialog appeared, so the tap looked ignored for up to 15 s).
  Future<void> _showAssignTechnicianDialog() async {
    final controller = _controller;
    // Future.sync: a lookup that throws synchronously still lands in the
    // dialog's error state instead of escaping before the dialog opens.
    final techniciansFuture =
        Future<List<Technician>>.sync(controller.fetchAssignableTechnicians);
    // The dialog's FutureBuilder subscribes a frame later; mark the future as
    // handled now so a fast failure is not reported as an uncaught error.
    techniciansFuture.ignore();
    int? selectedId;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Assign technician'),
          content: FutureBuilder<List<Technician>>(
            future: techniciansFuture,
            builder: (ctx, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 56,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  key: const Key('assign_technician_error'),
                  workOrderReadableError(snapshot.error!),
                );
              }
              final technicians = snapshot.data ?? const <Technician>[];
              if (technicians.isEmpty) {
                return const Text(
                  key: Key('assign_technician_empty'),
                  'No maintenance staff available to assign.',
                );
              }
              return DropdownButtonFormField<int>(
                key: const Key('assign_technician_dropdown'),
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Technician'),
                value: selectedId,
                items: [
                  for (final t in technicians)
                    DropdownMenuItem(
                      value: t.id,
                      child: Text(t.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => setState(() => selectedId = id),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('assign_technician_confirm'),
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
  /// require an explicit second confirmation so the server never receives an
  /// accidental terminal transition.
  void _showTransitionDialog(WorkOrderAction action) {
    final textController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final target = action.targetStatus.toUpperCase();
    final isHighRisk = target == 'VERIFIED' || target == 'CLOSED';
    final isDestructive = target == 'CANCELLED' || target == 'REWORK_REQUIRED';
    bool highRiskConfirmed = false;

    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final tokens = ctx.gssms;
          final textTheme = Theme.of(ctx).textTheme;
          return AlertDialog(
            title: Text(action.label),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _transitionConsequence(target),
                      style: textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
                    ),
                    const SizedBox(height: GssmsSpacing.s12),
                    if (action.requiresFailureCode)
                      const _Notice(
                        tone: GssmsTone.danger,
                        icon: Icons.report_outlined,
                        text: 'This job work is on a CRITICAL/HIGH asset, so the '
                            'server requires a failure code and restored time '
                            'before this transition (ISO 55000). These cannot be '
                            'recorded from the app yet — record them in the web '
                            'console first, or this action will be rejected.',
                      ),
                    TextFormField(
                      key: const Key('transition_remarks_field'),
                      controller: textController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText:
                            action.requiresReason ? 'Remarks *' : 'Remarks (optional)',
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
                      const SizedBox(height: GssmsSpacing.s12),
                      _Notice(
                        tone: GssmsTone.warning,
                        icon: Icons.verified_user_outlined,
                        text: '${action.label} ends active work on this job work '
                            'and is recorded permanently in its audit trail.',
                        child: InkWell(
                          onTap: () =>
                              setState(() => highRiskConfirmed = !highRiskConfirmed),
                          borderRadius: BorderRadius.circular(GssmsRadius.r4),
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(minHeight: GssmsSize.touchTarget),
                            child: Row(
                              children: [
                                Checkbox(
                                  key: const Key('high_risk_confirm_checkbox'),
                                  value: highRiskConfirmed,
                                  onChanged: (v) =>
                                      setState(() => highRiskConfirmed = v ?? false),
                                ),
                                const Expanded(
                                  child: Text('I have checked the work and confirm'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('transition_confirm_button'),
                style: isDestructive
                    ? FilledButton.styleFrom(
                        backgroundColor: tokens.danger.solid,
                        foregroundColor: tokens.danger.onSolid,
                      )
                    : null,
                onPressed: () {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  if (isHighRisk && !highRiskConfirmed) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Tick the confirmation to continue.')),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop();
                  unawaited(_controller.transitionStatus(
                    status: action.targetStatus,
                    remarks: textController.text.trim(),
                  ));
                },
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(textController.dispose));
  }

  /// Plain-language consequence for each server transition (confirmation UX:
  /// say what will happen, not "Are you sure?").
  static String _transitionConsequence(String target) {
    switch (target) {
      case 'IN_PROGRESS':
        return 'The job work moves to In Progress.';
      case 'ON_HOLD':
        return 'Work is paused. The job work stays assigned and can be resumed later.';
      case 'TECH_COMPLETED':
        return 'The job work is submitted for verification by the depot incharge.';
      case 'REWORK_REQUIRED':
        return 'The job work is returned to the technician for rework.';
      case 'CLOSED':
        return 'The job work is closed. No further work can be recorded on it.';
      case 'CANCELLED':
        return 'The job work is cancelled and will not be executed.';
      default:
        return 'The job work status will change to '
            '${WorkOrderStatus.fromString(target).displayName}.';
    }
  }
}

class _ServerActionButton extends StatelessWidget {
  const _ServerActionButton({
    required this.action,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final WorkOrderAction action;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  GssmsTone get _tone {
    switch (action.targetStatus.toUpperCase()) {
      case 'REWORK_REQUIRED':
      case 'CANCELLED':
        return GssmsTone.danger;
      case 'ON_HOLD':
        return GssmsTone.warning;
      case 'VERIFIED':
      case 'CLOSED':
      case 'TECH_COMPLETED':
        return GssmsTone.success;
      default:
        return GssmsTone.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.gssms.tone(_tone);
    final key = Key('action_${action.targetStatus.toLowerCase()}');
    final text = Text(label, textAlign: TextAlign.center, maxLines: 2);
    if (filled) {
      return FilledButton(
        key: key,
        style: FilledButton.styleFrom(
          backgroundColor: palette.solid,
          foregroundColor: palette.onSolid,
        ),
        onPressed: onPressed,
        child: text,
      );
    }
    return OutlinedButton(
      key: key,
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.foreground,
        side: BorderSide(color: palette.border, width: 1.5),
      ),
      onPressed: onPressed,
      child: text,
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({
    required this.event,
    required this.isLast,
    required this.dateFormat,
  });

  final WorkOrderAuditEvent event;
  final bool isLast;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final color = event.isReturn ? tokens.danger.foreground : tokens.link;
    final transition = (event.fromState != null && event.toState != null)
        ? '${WorkOrderStatus.fromString(event.fromState).displayName} → '
            '${WorkOrderStatus.fromString(event.toState).displayName}'
        : (event.toState != null
            ? WorkOrderStatus.fromString(event.toState).displayName
            : event.eventType);

    // Dot + divider layout: no IntrinsicHeight per row.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: GssmsSpacing.s4),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: GssmsSpacing.s12),
        Expanded(
          child: Container(
            padding: EdgeInsets.only(bottom: isLast ? 0 : GssmsSpacing.s12),
            margin: EdgeInsets.only(bottom: isLast ? 0 : GssmsSpacing.s12),
            decoration: isLast
                ? null
                : BoxDecoration(border: Border(bottom: BorderSide(color: tokens.border))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(transition, style: textTheme.titleSmall?.copyWith(color: color)),
                const SizedBox(height: GssmsSpacing.s2),
                Text(
                  [
                    if (event.actor != null) event.actor,
                    if (event.actorRole != null) '(${event.actorRole})',
                    if (event.timestamp != null) dateFormat.format(event.timestamp!),
                  ].whereType<String>().join(' · '),
                  style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
                if (event.reason != null && event.reason!.trim().isNotEmpty) ...[
                  const SizedBox(height: GssmsSpacing.s4),
                  Text(event.reason!, style: textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Tinted notice box used inside dialogs.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.tone,
    required this.icon,
    required this.text,
    this.child,
  });

  final GssmsTone tone;
  final IconData icon;
  final String text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = context.gssms.tone(tone);
    return Container(
      margin: const EdgeInsets.only(bottom: GssmsSpacing.s8),
      padding: const EdgeInsets.all(GssmsSpacing.s12),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(GssmsRadius.r8),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: palette.foreground),
              const SizedBox(width: GssmsSpacing.s8),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: palette.foreground),
                ),
              ),
            ],
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}
