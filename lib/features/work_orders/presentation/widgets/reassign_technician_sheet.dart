import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/technician.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

/// Minimum reason length enforced by the backend (after trimming).
const int kReassignReasonMinLength = 10;

/// Opens the "Reassign technician" bottom sheet. Resolves to `true` when the
/// server acknowledged the reassignment (the caller shows "Job Work
/// reassigned." and refreshes), otherwise `null` / `false`.
Future<bool?> showReassignTechnicianSheet(
  BuildContext context,
  WidgetRef ref,
  WorkOrder wo,
) {
  final repo = ref.read(workOrderRepositoryProvider);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ReassignTechnicianSheet(workOrder: wo, repository: repo),
  );
}

/// Reassign flow for an ASSIGNED Job Work. Online-only: failures are shown
/// inline and the sheet stays open.
class ReassignTechnicianSheet extends StatefulWidget {
  const ReassignTechnicianSheet({
    super.key,
    required this.workOrder,
    required this.repository,
  });

  final WorkOrder workOrder;
  final IWorkOrderRepository repository;

  /// Whether the reassign action should be offered at all.
  static bool canShow(WorkOrder wo, UserSession? s) =>
      canReassignWorkOrder(s) &&
      wo.status == WorkOrderStatus.assigned &&
      wo.assignedToId != null;

  /// Validator for the reason field.
  static String? validateReason(String? value) {
    if ((value ?? '').trim().length < kReassignReasonMinLength) {
      return 'A reason of at least $kReassignReasonMinLength characters is required.';
    }
    return null;
  }

  @override
  State<ReassignTechnicianSheet> createState() =>
      _ReassignTechnicianSheetState();
}

class _ReassignTechnicianSheetState extends State<ReassignTechnicianSheet> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  late final Future<List<Technician>> _techniciansFuture;
  int? _selectedId;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Future.sync: a synchronous throw still lands in the error state.
    _techniciansFuture = Future<List<Technician>>.sync(
      () => widget.repository
          .fetchAssignableTechnicians(depotId: widget.workOrder.depotId),
    );
    _techniciansFuture.ignore();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final technicianId = _selectedId;
    if (technicianId == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.reassignWorkOrder(
        widget.workOrder.id,
        technicianId: technicianId,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = userFacingError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final theme = Theme.of(context);
    final wo = widget.workOrder;
    final current = (wo.assignedToName?.trim().isNotEmpty ?? false)
        ? wo.assignedToName!.trim()
        : 'User #${wo.assignedToId}';

    return Padding(
      padding: EdgeInsets.only(
        left: GssmsSpacing.s16,
        right: GssmsSpacing.s16,
        top: GssmsSpacing.s16,
        bottom: MediaQuery.of(context).viewInsets.bottom + GssmsSpacing.s16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reassign technician', style: theme.textTheme.titleLarge),
              const SizedBox(height: GssmsSpacing.s12),
              Text(
                'Current technician',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: tokens.textSecondary),
              ),
              Text(
                current,
                key: const Key('reassign_current_assignee'),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: GssmsSpacing.s12),
              FutureBuilder<List<Technician>>(
                future: _techniciansFuture,
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 56,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text(
                      key: const Key('reassign_technician_error'),
                      userFacingError(snapshot.error!),
                      style: TextStyle(color: tokens.danger.foreground),
                    );
                  }
                  final technicians = [
                    for (final t in snapshot.data ?? const <Technician>[])
                      if (t.id != wo.assignedToId) t,
                  ];
                  if (technicians.isEmpty) {
                    return const Text(
                      key: Key('reassign_technician_empty'),
                      'No other maintenance staff available.',
                    );
                  }
                  return DropdownButtonFormField<int>(
                    key: const Key('reassign_technician_dropdown'),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'New technician',
                    ),
                    initialValue: _selectedId,
                    items: [
                      for (final t in technicians)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(t.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (id) => setState(() => _selectedId = id),
                  );
                },
              ),
              const SizedBox(height: GssmsSpacing.s12),
              TextFormField(
                key: const Key('reassign_reason_field'),
                controller: _reasonController,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText:
                      'Why is this Job Work being reassigned? (min 10 characters)',
                ),
                validator: ReassignTechnicianSheet.validateReason,
              ),
              const SizedBox(height: GssmsSpacing.s8),
              Text(
                "Recorded in the Job Work's audit trail.",
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: tokens.textSecondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: GssmsSpacing.s8),
                Text(
                  _error!,
                  key: const Key('reassign_error'),
                  style: TextStyle(color: tokens.danger.foreground),
                ),
              ],
              const SizedBox(height: GssmsSpacing.s16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: GssmsSpacing.s8),
                  Expanded(
                    child: FilledButton(
                      key: const Key('reassign_confirm'),
                      onPressed:
                          (_selectedId == null || _submitting) ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Reassign'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
