import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/verification_workspace_controller.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/verification_workspace_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';

class VerificationWorkspaceScreen extends ConsumerStatefulWidget {
  const VerificationWorkspaceScreen({super.key, required this.workOrderId});

  final int workOrderId;

  @override
  ConsumerState<VerificationWorkspaceScreen> createState() =>
      _VerificationWorkspaceScreenState();
}

class _VerificationWorkspaceScreenState
    extends ConsumerState<VerificationWorkspaceScreen> {
  final _remarksController = TextEditingController();
  bool _highRiskConfirmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)), 'maintenance.edit')) {
        return;
      }
      ref
          .read(verificationWorkspaceControllerProvider(widget.workOrderId).notifier)
          .load();
      ref
          .read(workOrderDetailControllerProvider(widget.workOrderId).notifier)
          .loadDetail();
    });
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = sessionAllows(sessionOf(ref), 'maintenance.edit');
    if (!canEdit) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verify work order')),
        body: const PermissionDeniedView(),
      );
    }

    final state =
        ref.watch(verificationWorkspaceControllerProvider(widget.workOrderId));
    final detailState =
        ref.watch(workOrderDetailControllerProvider(widget.workOrderId));
    final submitting = (state is VerificationWorkspaceLoaded && state.isSubmitting) ||
        (detailState is WorkOrderDetailLoaded && detailState.isTransitioning);
    final returnAction = detailState is WorkOrderDetailLoaded
        ? detailState.actions?.enabledAction('REWORK_REQUIRED')
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify work order')),
      body: _buildBody(state),
      bottomNavigationBar: state is VerificationWorkspaceLoaded
          ? _buildActions(
              canVerify: state.workspace.canVerify,
              submitting: submitting,
              returnAction: returnAction,
            )
          : null,
    );
  }

  Widget _buildBody(VerificationWorkspaceState state) {
    if (state is VerificationWorkspaceLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is VerificationWorkspaceError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .read(
                      verificationWorkspaceControllerProvider(widget.workOrderId)
                          .notifier,
                    )
                    .load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (state is! VerificationWorkspaceLoaded) {
      return const SizedBox.shrink();
    }

    final workspace = state.workspace;
    final lines = workspace.record?.activeLines ?? const [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!workspace.canVerify) ...[
          _banner(
            key: const Key('verify_blocked_banner'),
            color: AppTheme.errorRed,
            title: 'Verification is blocked',
            lines: workspace.disabledReasons.isEmpty
                ? const ['The server will not allow this work order to be verified.']
                : workspace.disabledReasons,
          ),
          const SizedBox(height: 12),
        ],
        if (workspace.deficiencyCount > 0) ...[
          _banner(
            key: const Key('deficiency_banner'),
            color: Colors.orange.shade800,
            title: '${workspace.deficiencyCount} deficienc${workspace.deficiencyCount == 1 ? 'y' : 'ies'} recorded',
            lines: workspace.deficiencies,
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          'Checklist',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppTheme.railwayBlue,
          ),
        ),
        const SizedBox(height: 10),
        if (lines.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No checklist lines on this record.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          ...lines.map(_buildLineCard),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('verify_remarks_field'),
          controller: _remarksController,
          decoration: const InputDecoration(
            labelText: 'Remarks (optional)',
            hintText: 'Notes for this verification',
          ),
          maxLines: 3,
        ),
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
                  const Text(
                    'High-risk transition',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Verify records you as the supervisor on this work order. Confirm you have reviewed the checklist.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              InkWell(
                onTap: () => setState(() => _highRiskConfirmed = !_highRiskConfirmed),
                borderRadius: BorderRadius.circular(4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Checkbox(
                        key: const Key('verify_high_risk_confirm'),
                        value: _highRiskConfirmed,
                        onChanged: (v) => setState(() => _highRiskConfirmed = v ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          'I confirm this verification',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _banner({
    required Key key,
    required Color color,
    required String title,
    required List<String> lines,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(line, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildLineCard(MaintenanceRecordLine line) {
    final reading = _readingText(line);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.displayTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor(line).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    line.status,
                    style: TextStyle(
                      color: _statusColor(line),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Equipment: ${line.itemName}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            if (reading.isNotEmpty)
              Text(
                'Reading: $reading',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            if (line.observationAction != null &&
                line.observationAction!.trim().isNotEmpty)
              Text(
                'Remarks: ${line.observationAction}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
          ],
        ),
      ),
    );
  }

  String _readingText(MaintenanceRecordLine line) {
    if (line.valueType.isMultiPart) {
      final parts = line.componentValues.entries
          .where((e) => e.value.trim().isNotEmpty)
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      return parts;
    }
    final scalar = line.scalarValue.trim();
    if (scalar.isEmpty) return '';
    final unit = line.unit?.trim();
    if (unit != null && unit.isNotEmpty) return '$scalar $unit';
    return scalar;
  }

  Color _statusColor(MaintenanceRecordLine line) {
    final lower = line.status.toLowerCase();
    if (line.deficiency != null && line.deficiency!.trim().isNotEmpty) {
      return AppTheme.errorRed;
    }
    if (lower.contains('fail') ||
        lower.contains('defect') ||
        lower.contains('abnormal') ||
        lower.contains('dirty')) {
      return AppTheme.errorRed;
    }
    return AppTheme.railwayGreen;
  }

  Widget _buildActions({
    required bool canVerify,
    required bool submitting,
    required WorkOrderAction? returnAction,
  }) {
    return SafeArea(
      child: Container(
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
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('return_to_technician_button'),
                onPressed: (returnAction == null || submitting)
                    ? null
                    : () => _showReturnDialog(returnAction),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.errorRed,
                  side: const BorderSide(color: AppTheme.errorRed),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Return to Technician', textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                key: const Key('verify_confirm_button'),
                onPressed: (!canVerify || submitting) ? null : _confirmVerify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.railwayGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Verify'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmVerify() async {
    if (!_highRiskConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm this verification'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }
    final remarks = _remarksController.text.trim();
    final ok = await ref
        .read(workOrderDetailControllerProvider(widget.workOrderId).notifier)
        .verifyWorkOrder(remarks: remarks.isEmpty ? null : remarks);
    if (!mounted) return;
    if (ok) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _showFailureMessage();
  }

  Future<void> _showReturnDialog(WorkOrderAction action) async {
    final textController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final remarks = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action.label),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('transition_remarks_field'),
            controller: textController,
            decoration: const InputDecoration(
              labelText: 'Remarks *',
              hintText: 'Add notes for this status change',
            ),
            maxLines: 3,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Remarks are required for this action';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('transition_confirm_button'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(88, 48),
            ),
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.of(ctx).pop(textController.text.trim());
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (remarks == null || remarks.isEmpty || !mounted) return;
    await _returnToTechnician(remarks);
  }

  Future<void> _returnToTechnician(String remarks) async {
    final ok = await ref
        .read(workOrderDetailControllerProvider(widget.workOrderId).notifier)
        .transitionStatus(status: 'REWORK_REQUIRED', remarks: remarks);
    if (!mounted) return;
    if (ok) {
      // Leave the workspace on success: it was built from a snapshot of the
      // record at TECH_COMPLETED, and canVerify/the checklist here are now
      // stale for a work order that just moved to REWORK_REQUIRED — staying
      // would let Verify still be tapped against that stale state.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _showFailureMessage();
  }

  void _showFailureMessage() {
    final state = ref.read(workOrderDetailControllerProvider(widget.workOrderId));
    final message = switch (state) {
      WorkOrderDetailError(:final message) => message,
      WorkOrderDetailLoaded(:final errorMessage?) => errorMessage,
      _ => 'The request failed. Please try again.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.errorRed),
    );
  }
}
