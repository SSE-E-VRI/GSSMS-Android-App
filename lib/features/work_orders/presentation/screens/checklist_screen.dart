import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';

class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({super.key, required this.recordId});

  final int recordId;

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(checklistControllerProvider(widget.recordId).notifier).loadRecord();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checklistControllerProvider(widget.recordId));

    ref.listen(checklistControllerProvider(widget.recordId), (prev, next) {
      if (next is ChecklistCompleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maintenance execution completed successfully!'),
            backgroundColor: AppTheme.railwayGreen,
          ),
        );
        Navigator.of(context).pop();
      } else if (next is ChecklistLoaded && next.errorMessage != null) {
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
        title: Text('Checklist #${widget.recordId}'),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SyncStatusBadge(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(checklistControllerProvider(widget.recordId).notifier)
                .loadRecord(),
          ),
        ],
      ),
      body: _buildBody(state),
      bottomNavigationBar: _buildBottomBar(state),
    );
  }

  Widget _buildBody(ChecklistState state) {
    if (state is ChecklistLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is ChecklistError) {
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
                    .read(checklistControllerProvider(widget.recordId).notifier)
                    .loadRecord(),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is ChecklistLoaded) {
      final record = state.record;
      final lines = state.displayedLines;
      final categories = state.subCategories;

      return Column(
        children: [
          _buildProgressCard(record),
          if (categories.isNotEmpty) _buildCategoryFilter(categories, state.activeSubCategory),
          Expanded(
            child: lines.isEmpty
                ? const Center(child: Text('No checklist items in this category.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _ChecklistLineCard(
                        // Keyed by line identity so per-line editing state is not
                        // reused for a different line when the category filter
                        // changes the order of this list.
                        key: ValueKey(lines[index].id),
                        line: lines[index],
                        onSave: (edit) {
                          unawaited(ref
                              .read(checklistControllerProvider(widget.recordId).notifier)
                              .submitLineObservation(
                                lineId: lines[index].id,
                                value: edit.value,
                                status: edit.status,
                                statusOptionId: edit.statusOptionId,
                                actionOptionId: edit.actionOptionId,
                                remarks: edit.remarks,
                              ));
                        },
                      );
                    },
                  ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildProgressCard(MaintenanceRecord record) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Execution Progress: ${(record.progress * 100).toInt()}%',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                '${record.completedLines} of ${record.totalLines} completed',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: record.progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              color: record.progress == 1.0 ? AppTheme.railwayGreen : AppTheme.railwayBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter(List<String> categories, String? activeCategory) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('All Subsystems'),
                selected: activeCategory == null,
                onSelected: (_) => ref
                    .read(checklistControllerProvider(widget.recordId).notifier)
                    .setActiveSubCategory(null),
              ),
            ),
            ...categories.map((cat) {
              final isSelected = activeCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (_) => ref
                      .read(checklistControllerProvider(widget.recordId).notifier)
                      .setActiveSubCategory(cat),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget? _buildBottomBar(ChecklistState state) {
    if (state is! ChecklistLoaded) return null;

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
      child: ElevatedButton(
        key: const Key('complete_checklist_button'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.railwayGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: state.isSubmitting ? null : () => _showCompletionDialog(),
        child: state.isSubmitting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Text(
                'Complete & Submit Execution',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  /// Finalisation sheet: proof photo, technician signature and closing remarks.
  ///
  /// The server writes a signature row only when `technician_signature` is
  /// present and rejects TECH_COMPLETED unless remarks are at least
  /// [ChecklistController.minCompletionRemarksLength] characters, so both are
  /// collected and validated here rather than failing after the round trip.
  void _showCompletionDialog() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CompletionSheet(recordId: widget.recordId),
    ));
  }
}

class _CompletionSheet extends ConsumerStatefulWidget {
  const _CompletionSheet({required this.recordId});

  final int recordId;

  @override
  ConsumerState<_CompletionSheet> createState() => _CompletionSheetState();
}

class _CompletionSheetState extends ConsumerState<_CompletionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _remarksController = TextEditingController();
  final _technicianController = TextEditingController();
  final _otherStaffController = TextEditingController();

  EvidenceFile? _proof;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    final authState = ref.read(authControllerProvider);
    if (authState is Authenticated) {
      _technicianController.text = authState.session.displayName;
    }
  }

  @override
  void dispose() {
    _remarksController.dispose();
    _technicianController.dispose();
    _otherStaffController.dispose();
    super.dispose();
  }

  Future<void> _capture(ImageSource source) async {
    setState(() => _capturing = true);
    try {
      final file = await ref.read(evidenceServiceProvider).capture(source: source);
      if (!mounted) return;
      if (file != null && !file.isWithinSizeLimit) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That photo is over the 5 MB limit. Try again.'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
        return;
      }
      if (file != null) setState(() => _proof = file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not capture photo: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checklistControllerProvider(widget.recordId));
    final isSubmitting = state is ChecklistLoaded && state.isSubmitting;
    final record = state is ChecklistLoaded ? state.record : null;
    final outstanding = record == null ? 0 : record.totalLines - record.completedLines;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Finalize Execution',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Submit this maintenance execution for supervisor verification.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              if (outstanding > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.warningAmber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.warningAmber.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 18, color: AppTheme.warningAmber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$outstanding line(s) still unrecorded. The server will '
                          'reject completion until every line is submitted.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _buildProofField(),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('completion_technician_field'),
                controller: _technicianController,
                decoration: const InputDecoration(
                  labelText: 'Technician Name *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (val) => (val == null || val.trim().isEmpty)
                    ? 'Enter the technician name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('completion_other_staff_field'),
                controller: _otherStaffController,
                decoration: const InputDecoration(
                  labelText: 'Other Staff Involved (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('completion_remarks_field'),
                controller: _remarksController,
                decoration: const InputDecoration(
                  labelText: 'Technician Closing Remarks *',
                  helperText: 'At least 10 characters',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (val) {
                  final text = val?.trim() ?? '';
                  if (text.length < ChecklistController.minCompletionRemarksLength) {
                    return 'Remarks must be at least '
                        '${ChecklistController.minCompletionRemarksLength} characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  TextButton(
                    onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    key: const Key('completion_confirm_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.railwayGreen,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: isSubmitting ? null : _submit,
                    child: isSubmitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Confirm Completion'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProofField() {
    final proof = _proof;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Proof of Execution',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        if (proof != null)
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(proof.path),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${proof.fileName}\n${(proof.sizeBytes / 1024).round()} KB',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ),
              IconButton(
                key: const Key('completion_remove_proof'),
                icon: const Icon(Icons.close),
                tooltip: 'Remove photo',
                onPressed: () => setState(() => _proof = null),
              ),
            ],
          )
        else
          Row(
            children: [
              OutlinedButton.icon(
                key: const Key('completion_capture_photo'),
                onPressed: _capturing ? null : () => _capture(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Camera'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('completion_pick_photo'),
                onPressed: _capturing ? null : () => _capture(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Gallery'),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final otherStaff = _otherStaffController.text.trim();
    final ok = await ref
        .read(checklistControllerProvider(widget.recordId).notifier)
        .completeExecution(
          technicianName: _technicianController.text.trim(),
          remarks: _remarksController.text.trim(),
          proofJpegPath: _proof?.path,
          otherStaff: otherStaff.isEmpty ? null : otherStaff,
        );

    if (ok && mounted) Navigator.of(context).pop();
  }
}

/// One checklist line.
///
/// The input rendered depends on the line's `value_type`, mirroring the web
/// register: a status/action pair for inspection points, and typed measurement
/// fields — including three-phase RYB and Volt/Amp pairs — for parameters.
class _ChecklistLineCard extends StatefulWidget {
  const _ChecklistLineCard({
    super.key,
    required this.line,
    required this.onSave,
  });

  final MaintenanceRecordLine line;
  final void Function(ChecklistLineEdit edit) onSave;

  @override
  State<_ChecklistLineCard> createState() => _ChecklistLineCardState();
}

/// The values a line card reports back when it saves.
class ChecklistLineEdit {
  const ChecklistLineEdit({
    required this.value,
    required this.status,
    this.statusOptionId,
    this.actionOptionId,
    this.remarks,
  });

  /// String for scalar readings, `Map<String, String>` for RYB / Volt-Amp.
  final Object? value;
  final String status;
  final int? statusOptionId;
  final int? actionOptionId;
  final String? remarks;
}

class _ChecklistLineCardState extends State<_ChecklistLineCard> {
  /// How long typing must pause before the observation is pushed to the server.
  static const Duration _saveDebounce = Duration(milliseconds: 800);

  late final TextEditingController _valueController;
  late final TextEditingController _remarksController;
  late final FocusNode _valueFocus;
  late final FocusNode _remarksFocus;

  /// Controllers for the multi-part value types, keyed by component (R/Y/B...).
  final Map<String, TextEditingController> _componentControllers = {};
  final Map<String, FocusNode> _componentFocusNodes = {};

  late String _status;
  int? _statusOptionId;
  int? _actionOptionId;
  Timer? _debounceTimer;

  MaintenanceRecordLine get _line => widget.line;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(text: _line.scalarValue);
    _remarksController = TextEditingController(text: _line.observationAction ?? '');
    _valueFocus = FocusNode()..addListener(_onFocusChanged);
    _remarksFocus = FocusNode()..addListener(_onFocusChanged);

    final components = _line.componentValues;
    for (final key in _line.valueType.componentKeys) {
      _componentControllers[key] =
          TextEditingController(text: components[key] ?? '');
      _componentFocusNodes[key] = FocusNode()..addListener(_onFocusChanged);
    }

    _status = _line.status;
    _statusOptionId = _line.statusOptionId;
    _actionOptionId = _line.actionOptionId;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _valueFocus.removeListener(_onFocusChanged);
    _remarksFocus.removeListener(_onFocusChanged);
    _valueFocus.dispose();
    _remarksFocus.dispose();
    _valueController.dispose();
    _remarksController.dispose();
    for (final node in _componentFocusNodes.values) {
      node.removeListener(_onFocusChanged);
      node.dispose();
    }
    for (final controller in _componentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _anyFieldFocused =>
      _valueFocus.hasFocus ||
      _remarksFocus.hasFocus ||
      _componentFocusNodes.values.any((n) => n.hasFocus);

  /// Flush a pending edit as soon as the technician leaves the line, so a
  /// debounced keystroke is never lost by moving on quickly.
  void _onFocusChanged() {
    if (!_anyFieldFocused && _debounceTimer?.isActive == true) {
      _triggerSave(immediate: true);
    }
  }

  /// Text edits are debounced; discrete choices (chips, dropdowns) save at once.
  /// Saving on every keystroke would put one HTTP request - or one queued
  /// outbox command while offline - behind every character typed.
  void _triggerSave({bool immediate = false}) {
    _debounceTimer?.cancel();
    if (immediate) {
      _save();
      return;
    }
    _debounceTimer = Timer(_saveDebounce, _save);
  }

  Object? _currentValue() {
    if (_line.valueType.isMultiPart) {
      return {
        for (final key in _line.valueType.componentKeys)
          key: _componentControllers[key]?.text.trim() ?? '',
      };
    }
    final text = _valueController.text.trim();
    return text.isEmpty ? null : text;
  }

  void _save() {
    if (!mounted) return;
    final remarks = _remarksController.text.trim();
    widget.onSave(
      ChecklistLineEdit(
        value: _currentValue(),
        status: _status,
        statusOptionId: _statusOptionId,
        actionOptionId: _actionOptionId,
        remarks: remarks.isEmpty ? null : remarks,
      ),
    );
  }

  void _onStatusOptionChanged(int? value) {
    setState(() {
      _statusOptionId = value;
      // Actions belong to a specific status; clear a selection the new status
      // does not offer rather than sending one the backend will reject.
      final stillValid = _line.statusOptions
          .where((o) => o.id == value)
          .expand((o) => o.actionOptions)
          .any((a) => a.id == _actionOptionId);
      if (!stillValid) _actionOptionId = null;
    });
    _triggerSave(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final line = _line;

    return Card(
      key: Key('checklist_line_${line.id}'),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(line),
            const Divider(height: 18),
            ..._buildValueInput(line),
            if (line.statusOptions.isNotEmpty) ..._buildStatusAndAction(line),
            const SizedBox(height: 10),
            TextField(
              controller: _remarksController,
              focusNode: _remarksFocus,
              decoration: const InputDecoration(
                labelText: 'Notes / Corrective Action',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _triggerSave(),
              onEditingComplete: () => _triggerSave(immediate: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(MaintenanceRecordLine line) {
    final hasPoint = line.inspectionPoint != null &&
        line.inspectionPoint!.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.displayTitle,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (hasPoint) ...[
                const SizedBox(height: 2),
                Text(
                  line.itemName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (line.isRequired)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Text(
              'Required',
              style: TextStyle(fontSize: 10, color: AppTheme.errorRed),
            ),
          ),
        Icon(
          line.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
          color: line.isCompleted ? AppTheme.railwayGreen : Colors.grey,
          size: 20,
        ),
      ],
    );
  }

  /// The reading input for this line's value type.
  List<Widget> _buildValueInput(MaintenanceRecordLine line) {
    switch (line.valueType) {
      case MaintenanceValueType.ryb:
      case MaintenanceValueType.voltAmp:
        return [_buildComponentInputs(line)];

      case MaintenanceValueType.yesNo:
        return [_buildYesNoInput(line)];

      case MaintenanceValueType.status:
        // Status lines carry their reading in the status/action pair below.
        return const [];

      case MaintenanceValueType.number:
      case MaintenanceValueType.decimal:
      case MaintenanceValueType.text:
      case MaintenanceValueType.unknown:
        return [_buildScalarInput(line)];
    }
  }

  Widget _buildScalarInput(MaintenanceRecordLine line) {
    final isNumeric = line.valueType.isNumeric;
    final hasReference = line.referenceValue != null &&
        line.referenceValue!.trim().isNotEmpty;
    final hasUnit = line.unit != null && line.unit!.trim().isNotEmpty;
    return TextField(
      key: Key('line_value_${line.id}'),
      controller: _valueController,
      focusNode: _valueFocus,
      keyboardType: isNumeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: 'Reading',
        hintText: hasReference ? 'Reference: ${line.referenceValue}' : null,
        suffixText: hasUnit ? line.unit : null,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => _triggerSave(),
      onEditingComplete: () => _triggerSave(immediate: true),
    );
  }

  /// Three-phase (R/Y/B) or Volt/Amp readings, one field per component.
  Widget _buildComponentInputs(MaintenanceRecordLine line) {
    final keys = line.valueType.componentKeys;
    final hasUnit = line.unit != null && line.unit!.trim().isNotEmpty;
    return Row(
      children: [
        for (final key in keys) ...[
          Expanded(
            child: TextField(
              key: Key('line_${line.id}_component_$key'),
              controller: _componentControllers[key],
              focusNode: _componentFocusNodes[key],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: key,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _triggerSave(),
              onEditingComplete: () => _triggerSave(immediate: true),
            ),
          ),
          if (key != keys.last) const SizedBox(width: 8),
        ],
        if (hasUnit) ...[
          const SizedBox(width: 6),
          Text(
            line.unit!,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _buildYesNoInput(MaintenanceRecordLine line) {
    final current = _valueController.text.trim();
    return Row(
      children: [
        const Text(
          'Result: ',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8),
        for (final option in const ['Yes', 'No']) ...[
          ChoiceChip(
            key: Key('line_${line.id}_yesno_${option.toLowerCase()}'),
            label: Text(option),
            selected: current == option,
            onSelected: (selected) {
              if (!selected) return;
              setState(() => _valueController.text = option);
              _triggerSave(immediate: true);
            },
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  /// Status, then the actions that status permits. The action dropdown appears
  /// only once a status is chosen, matching the backend rule that an action
  /// must map to the selected status.
  List<Widget> _buildStatusAndAction(MaintenanceRecordLine line) {
    MaintenanceStatusOption? selectedStatus;
    for (final option in line.statusOptions) {
      if (option.id == _statusOptionId) {
        selectedStatus = option;
        break;
      }
    }
    final actions =
        selectedStatus?.actionOptions ?? const <MaintenanceActionOption>[];

    return [
      const SizedBox(height: 10),
      DropdownButtonFormField<int>(
        key: Key('line_${line.id}_status_option'),
        value: selectedStatus?.id,
        decoration: const InputDecoration(
          labelText: 'Status',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: line.statusOptions
            .map((opt) => DropdownMenuItem<int>(
                  value: opt.id,
                  child: Text(
                    opt.label,
                    style: TextStyle(
                      color: opt.isDeficiency ? AppTheme.errorRed : null,
                    ),
                  ),
                ))
            .toList(),
        onChanged: _onStatusOptionChanged,
      ),
      if (actions.isNotEmpty) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          key: Key('line_${line.id}_action_option'),
          value: actions.any((a) => a.id == _actionOptionId)
              ? _actionOptionId
              : null,
          decoration: const InputDecoration(
            labelText: 'Action Taken',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: actions
              .map((opt) => DropdownMenuItem<int>(
                    value: opt.id,
                    child: Text(
                      opt.label,
                      style: TextStyle(
                        color: opt.isDeficiency ? AppTheme.errorRed : null,
                      ),
                    ),
                  ))
              .toList(),
          onChanged: (val) {
            setState(() => _actionOptionId = val);
            _triggerSave(immediate: true);
          },
        ),
      ],
    ];
  }
}
