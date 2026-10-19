import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/pm_approval_request.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

/// Which approval request the sheet raises.
enum PmApprovalRequestMode { skip, checklistChange }

/// Opens the PM skip / checklist-change request sheet. Resolves to `true`
/// when the server accepted the request, otherwise null/false.
Future<bool?> showPmApprovalRequestSheet(
  BuildContext context,
  WidgetRef ref,
  WorkOrder wo,
  PmApprovalRequestMode mode,
) {
  final repo = ref.read(workOrderRepositoryProvider);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => PmApprovalRequestSheet(
      workOrder: wo,
      mode: mode,
      repository: repo,
    ),
  );
}

/// Raise-only sheet for PM skip and checklist-change approval requests.
class PmApprovalRequestSheet extends StatefulWidget {
  const PmApprovalRequestSheet({
    super.key,
    required this.workOrder,
    required this.mode,
    required this.repository,
  });

  final WorkOrder workOrder;
  final PmApprovalRequestMode mode;
  final IWorkOrderRepository repository;

  /// Whether the request actions apply to [wo] for [session].
  static bool canShow(WorkOrder wo, UserSession? session) =>
      canRequestPmApproval(session) &&
      wo.type == WorkOrderType.preventive &&
      wo.originalScheduleId != null &&
      (wo.status == WorkOrderStatus.newOrder ||
          wo.status == WorkOrderStatus.assigned);

  static const skipInfo =
      'Skipping requires approval from Division Admin. Open Job Works will be '
      'cancelled and the next occurrence materialized upon approval.';
  static const changeInfo =
      'Checklist change requires Division Admin approval. Upon approval, open '
      'Job Works will be updated to the new checklist.';
  static const noAlternatives =
      'No eligible alternative checklists are available for this occurrence '
      '(must share schedule type and cover all checklist categories).';

  /// Validation for the remarks field; null when valid.
  static String? validateRemarks(String? value, {bool requireLong = false}) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Remarks are required';
    if (requireLong && text.length < 20) {
      return 'Remarks must be at least 20 characters for "Other"';
    }
    return null;
  }

  @override
  State<PmApprovalRequestSheet> createState() => _PmApprovalRequestSheetState();
}

class _PmApprovalRequestSheetState extends State<PmApprovalRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _remarksController = TextEditingController();
  String _reasonCode = 'ASSET_UNAVAILABLE';
  List<ScheduleAlternative>? _alternatives;
  int? _selectedAlternativeId;
  bool _loadingAlternatives = false;
  String? _loadError;
  bool _submitting = false;
  String? _submitError;

  bool get _isSkip => widget.mode == PmApprovalRequestMode.skip;
  int get _scheduleId => widget.workOrder.originalScheduleId!;

  @override
  void initState() {
    super.initState();
    if (!_isSkip) _loadAlternatives();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadAlternatives() async {
    setState(() {
      _loadingAlternatives = true;
      _loadError = null;
    });
    try {
      final list = await widget.repository.getScheduleAlternatives(_scheduleId);
      if (!mounted) return;
      setState(() {
        _alternatives = list;
        _selectedAlternativeId = list.isEmpty ? null : list.first.id;
        _loadingAlternatives = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = userFacingError(e);
        _loadingAlternatives = false;
      });
    }
  }

  bool get _canSubmit {
    if (_submitting) return false;
    if (_isSkip) return true;
    return !_loadingAlternatives && _selectedAlternativeId != null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final remarks = _remarksController.text.trim();
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      if (_isSkip) {
        await widget.repository.requestPmSkip(
          _scheduleId,
          reasonCode: _reasonCode,
          remarks: remarks,
        );
      } else {
        await widget.repository.requestChecklistChange(
          _scheduleId,
          maintenanceMasterId: _selectedAlternativeId!,
          remarks: remarks,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = userFacingError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final info = tokens.tone(GssmsTone.info);
    final danger = tokens.tone(GssmsTone.danger);
    final warning = tokens.tone(GssmsTone.warning);
    final title = _isSkip ? 'Request PM Skip' : 'Request Checklist Change';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(GssmsSpacing.s16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: GssmsSpacing.s12),
              _notice(
                key: const Key('pm_request_info'),
                text: _isSkip
                    ? PmApprovalRequestSheet.skipInfo
                    : PmApprovalRequestSheet.changeInfo,
                icon: Icons.info_outline,
                palette: info,
              ),
              const SizedBox(height: GssmsSpacing.s12),
              if (_isSkip)
                DropdownButtonFormField<String>(
                  key: const Key('pm_skip_reason'),
                  initialValue: _reasonCode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Reason *',
                    isDense: true,
                  ),
                  items: [
                    for (final e in kSkipReasonChoices.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(
                          e.key == 'OTHER'
                              ? 'Other (requires ≥ 20 characters)'
                              : e.value,
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _reasonCode = v ?? _reasonCode),
                )
              else
                ..._alternativeSection(warning, danger),
              const SizedBox(height: GssmsSpacing.s12),
              TextFormField(
                key: const Key('pm_request_remarks'),
                controller: _remarksController,
                enabled: !_submitting,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Remarks *',
                  alignLabelWithHint: true,
                ),
                validator: (v) => PmApprovalRequestSheet.validateRemarks(
                  v,
                  requireLong: _isSkip && _reasonCode == 'OTHER',
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: GssmsSpacing.s12),
                _notice(
                  key: const Key('pm_request_error'),
                  text: _submitError!,
                  icon: Icons.error_outline,
                  palette: danger,
                ),
              ],
              const SizedBox(height: GssmsSpacing.s16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('pm_request_cancel'),
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: GssmsSpacing.s12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('pm_request_submit'),
                      onPressed: _canSubmit ? _submit : null,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Submit Request'),
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

  List<Widget> _alternativeSection(
    GssmsTonePalette warning,
    GssmsTonePalette danger,
  ) {
    if (_loadingAlternatives) {
      return const [
        Center(
          child: Padding(
            padding: EdgeInsets.all(GssmsSpacing.s12),
            child: CircularProgressIndicator(key: Key('pm_alternatives_loading')),
          ),
        ),
      ];
    }
    if (_loadError != null) {
      return [
        _notice(
          key: const Key('pm_alternatives_error'),
          text: _loadError!,
          icon: Icons.error_outline,
          palette: danger,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _loadAlternatives,
            child: const Text('Retry'),
          ),
        ),
      ];
    }
    final list = _alternatives ?? const <ScheduleAlternative>[];
    if (list.isEmpty) {
      return [
        _notice(
          key: const Key('pm_no_alternatives'),
          text: PmApprovalRequestSheet.noAlternatives,
          icon: Icons.warning_amber_rounded,
          palette: warning,
        ),
      ];
    }
    return [
      DropdownButtonFormField<int>(
        key: const Key('pm_alternative_select'),
        initialValue: _selectedAlternativeId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'New Checklist *',
          isDense: true,
        ),
        items: [
          for (final a in list)
            DropdownMenuItem(
              value: a.id,
              child: Text(
                a.scheduleType == null || a.scheduleType!.isEmpty
                    ? a.name
                    : '${a.name} (${a.scheduleType})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _submitting
            ? null
            : (v) => setState(() => _selectedAlternativeId = v),
      ),
    ];
  }

  Widget _notice({
    required Key key,
    required String text,
    required IconData icon,
    required GssmsTonePalette palette,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(GssmsSpacing.s12),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(GssmsRadius.r8),
      ),
      child: Row(
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
    );
  }
}
