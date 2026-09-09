import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

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

class ChecklistLineCard extends ConsumerStatefulWidget {
  const ChecklistLineCard({
    super.key,
    required this.line,
    required this.onSave,
    this.recordId,
    this.isPastTechCompleted = false,
    this.onCapturePhoto,
    this.onDeletePhoto,
    this.onRetryPhoto,
  });

  final MaintenanceRecordLine line;
  final void Function(ChecklistLineEdit edit) onSave;
  final int? recordId;
  final bool isPastTechCompleted;
  final Future<void> Function(EvidenceKind kind, ImageSource source)? onCapturePhoto;
  final Future<void> Function(LineAttachment attachment)? onDeletePhoto;
  final Future<void> Function(LineAttachment attachment)? onRetryPhoto;

  @override
  ConsumerState<ChecklistLineCard> createState() => _ChecklistLineCardState();
}

class _ChecklistLineCardState extends ConsumerState<ChecklistLineCard> {
  /// How long typing must pause before the observation is pushed to the server.
  static const Duration _saveDebounce = Duration(milliseconds: 800);

  bool _attachmentsExpanded = false;

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

  /// Auth headers for loading protected evidence images. `protected_media`
  /// requires authentication and `Image.network` sends none by itself, so
  /// synced photos would otherwise render as broken images.
  Map<String, String>? _authHeaders() {
    final token =
        sessionFromAuth(ref.read(authControllerProvider))?.accessToken;
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(text: _line.scalarValue);
    _remarksController =
        TextEditingController(text: _line.observationAction ?? '');
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
  void didUpdateWidget(covariant ChecklistLineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.line != oldWidget.line) {
      if (!_valueFocus.hasFocus &&
          _valueController.text != widget.line.scalarValue) {
        _valueController.text = widget.line.scalarValue;
      }
      if (!_remarksFocus.hasFocus &&
          _remarksController.text != (widget.line.observationAction ?? '')) {
        _remarksController.text = widget.line.observationAction ?? '';
      }
      final components = widget.line.componentValues;
      for (final key in widget.line.valueType.componentKeys) {
        final focus = _componentFocusNodes[key];
        final ctrl = _componentControllers[key];
        if (ctrl != null && focus != null && !focus.hasFocus) {
          ctrl.text = components[key] ?? '';
        }
      }
      _status = widget.line.status;
      _statusOptionId = widget.line.statusOptionId;
      _actionOptionId = widget.line.actionOptionId;
    }
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
      if (value != null) {
        final matchedOption = _line.statusOptions.firstWhere(
          (o) => o.id == value,
          orElse: () => _line.statusOptions.first,
        );
        _status = matchedOption.semantic ?? 'OK';
      }
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, line),
            const Divider(height: 10),
            ..._buildValueInput(line),
            if (line.statusOptions.isNotEmpty) ..._buildStatusAndAction(line),
            _buildAttachmentsSection(line),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, MaintenanceRecordLine line) {
    final textTheme = Theme.of(context).textTheme;
    final hasPoint = line.inspectionPoint != null &&
        line.inspectionPoint!.trim().isNotEmpty;
    final hasObservations =
        line.isCompleted || line.recordedValue != null || line.statusOptionId != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.displayTitle,
                style: textTheme.titleMedium,
              ),
              if (hasPoint) ...[
                const SizedBox(height: 2),
                Text(
                  line.itemName,
                  style: textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (line.isRequired)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              'Required',
              style: textTheme.labelSmall?.copyWith(
                color: AppTheme.errorRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (hasObservations) ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  line.isSaved ? Icons.check : Icons.sync,
                  size: 14,
                  color: line.isSaved
                      ? AppTheme.successGreen
                      : AppTheme.warningAmber,
                ),
                const SizedBox(width: 3),
                Text(
                  line.isSaved ? 'saved' : 'queued',
                  style: textTheme.labelSmall?.copyWith(
                    color: line.isSaved
                        ? AppTheme.successGreen
                        : AppTheme.warningAmber,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: line.isCompleted
                ? AppTheme.successGreen
                : AppTheme.borderGrey,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.check,
            color: line.isCompleted ? Colors.white : Colors.transparent,
            size: 16,
          ),
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

  Color _getComponentColor(String key) {
    switch (key.toUpperCase()) {
      case 'R':
        return AppTheme.errorRed;
      case 'Y':
        return AppTheme.warningAmber;
      case 'B':
        return AppTheme.primaryBlue;
      default:
        return AppTheme.railwayBlue;
    }
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
                labelStyle: TextStyle(
                  color: _getComponentColor(key),
                  fontWeight: FontWeight.bold,
                ),
                isDense: true,
                focusedBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: _getComponentColor(key), width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                      color: _getComponentColor(key).withOpacity(0.6)),
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _triggerSave(),
              onEditingComplete: () => _triggerSave(immediate: true),
            ),
          ),
          if (key != keys.last) const SizedBox(width: 8),
        ],
        if (hasUnit) ...[
          const SizedBox(width: 8),
          Text(
            '(${line.unit!})',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildYesNoInput(MaintenanceRecordLine line) {
    final current = _valueController.text.trim();
    return Row(
      children: [
        Text(
          'Result: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(width: 8),
        for (final option in const ['Yes', 'No']) ...[
          ChoiceChip(
            key: Key('line_${line.id}_yesno_${option.toLowerCase()}'),
            label: Text(option),
            selected: current == option,
            materialTapTargetSize: MaterialTapTargetSize.padded,
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

  String _statusOptionGlyph(MaintenanceStatusOption opt) {
    final lower = opt.label.toLowerCase();
    if (opt.isDeficiency || _isDeficientLabel(opt.label)) {
      if (lower.contains('failed') ||
          lower.contains('damaged') ||
          lower.contains('defective') ||
          lower.contains('abnormal')) {
        return '✕ ';
      }
      return '! ';
    }
    if (lower.contains('ok') ||
        lower.contains('normal') ||
        lower.contains('pass') ||
        lower.contains('good')) {
      return '✓ ';
    }
    return '• ';
  }

  bool _isDeficientLabel(String label) {
    final lower = label.toLowerCase();
    return lower.contains('dirty') ||
        lower.contains('defect') ||
        lower.contains('fail') ||
        lower.contains('abnormal') ||
        lower.contains('damaged') ||
        lower.contains('not working');
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _statusOptionGlyph(opt),
                        style: TextStyle(
                          color: opt.isDeficiency ? AppTheme.errorRed : null,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        opt.label,
                        style: TextStyle(
                          color: opt.isDeficiency ? AppTheme.errorRed : null,
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
        onChanged: _onStatusOptionChanged,
      ),
      if (selectedStatus != null &&
          (selectedStatus.isDeficiency ||
              _isDeficientLabel(selectedStatus.label))) ...[
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.warningAmber,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              const Text('! ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
              Expanded(
                child: Text(
                  'Deficiency flagged - pending severity review',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
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

  Future<void> _handleCapture(EvidenceKind kind, ImageSource source) async {
    try {
      final evidenceService = ref.read(evidenceServiceProvider);
      final nearCap = await evidenceService.isStorageNearCap();
      if (nearCap && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Storage warning: Pending evidence photos exceed 200MB. Consider syncing before taking more photos.',
            ),
            backgroundColor: AppTheme.warningAmber,
            duration: Duration(seconds: 4),
          ),
        );
      }

      if (widget.onCapturePhoto != null) {
        await widget.onCapturePhoto!(kind, source);
        return;
      }

      if (widget.recordId == null) return;

      final evidence = await evidenceService.capture(kind: kind, source: source);
      if (evidence == null || !mounted) return;

      await ref
          .read(checklistControllerProvider(widget.recordId!).notifier)
          .uploadLineAttachment(
            lineId: widget.line.id,
            kind: kind.name.toUpperCase(),
            imagePath: evidence.path,
            capturedAt: DateTime.now(),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture photo: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    }
  }

  Future<void> _handleDelete(LineAttachment attachment) async {
    if (widget.isPastTechCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete attachments after technician completion.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Photo'),
        content: Text(
          'Are you sure you want to delete this ${attachment.kind.toLowerCase()} photo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    if (widget.onDeletePhoto != null) {
      await widget.onDeletePhoto!(attachment);
      return;
    }

    if (widget.recordId == null) return;

    await ref
        .read(checklistControllerProvider(widget.recordId!).notifier)
        .deleteLineAttachment(
          lineId: widget.line.id,
          attachmentId: attachment.id,
          localPath: attachment.localPath,
          idempotencyKey: attachment.idempotencyKey,
        );
  }

  Future<void> _handleRetry(LineAttachment attachment) async {
    if (widget.onRetryPhoto != null) {
      await widget.onRetryPhoto!(attachment);
      return;
    }
    if (widget.recordId == null) return;
    await ref
        .read(checklistControllerProvider(widget.recordId!).notifier)
        .retryAttachment(attachment);
  }

  void _showFullscreenImage(LineAttachment attachment) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppTheme.primaryDark,
              child: Row(
                children: [
                  Text(
                    '${attachment.kind} Photo',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.65,
              ),
              child: InteractiveViewer(
                child: attachment.localPath != null &&
                        File(attachment.localPath!).existsSync()
                    ? Image.file(
                        File(attachment.localPath!),
                        fit: BoxFit.contain,
                      )
                    : attachment.url.isNotEmpty
                        ? Image.network(
                            attachment.url,
                            headers: _authHeaders(),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image, size: 64, color: AppTheme.textSecondary),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.image_not_supported, size: 64, color: AppTheme.textSecondary),
                          ),
              ),
            ),
            if (attachment.capturedAt != null || attachment.uploadedBy != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (attachment.capturedAt != null)
                      Text(
                        'Captured: ${attachment.capturedAt!.toLocal().toString().split('.').first}',
                        style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                    if (attachment.uploadedBy != null)
                      Text(
                        'By: ${attachment.uploadedBy}',
                        style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsSection(MaintenanceRecordLine line) {
    final beforeAtts = line.attachments.where((a) => a.kind == 'BEFORE').toList();
    final afterAtts = line.attachments.where((a) => a.kind == 'AFTER').toList();
    final duringAtts = line.attachments.where((a) => a.kind == 'DURING').toList();

    final countSummary = duringAtts.isEmpty
        ? 'Before ${beforeAtts.length} · After ${afterAtts.length}'
        : 'Before ${beforeAtts.length} · During ${duringAtts.length} · After ${afterAtts.length}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        InkWell(
          key: Key('line_${line.id}_attachments_toggle'),
          onTap: () => setState(() => _attachmentsExpanded = !_attachmentsExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.borderGrey.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.photo_camera_outlined,
                  size: 18,
                  color: (beforeAtts.isNotEmpty || afterAtts.isNotEmpty || duringAtts.isNotEmpty)
                      ? AppTheme.railwayBlue
                      : AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    countSummary,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _attachmentsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_attachmentsExpanded) ...[
          const SizedBox(height: 10),
          _buildAttachmentStrip(
            kind: EvidenceKind.before,
            title: 'Before Photos',
            attachments: beforeAtts,
          ),
          if (duringAtts.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildAttachmentStrip(
              kind: EvidenceKind.during,
              title: 'During Photos',
              attachments: duringAtts,
            ),
          ],
          const SizedBox(height: 10),
          _buildAttachmentStrip(
            kind: EvidenceKind.after,
            title: 'After Photos',
            attachments: afterAtts,
          ),
        ],
      ],
    );
  }

  Widget _buildAttachmentStrip({
    required EvidenceKind kind,
    required String title,
    required List<LineAttachment> attachments,
  }) {
    final canAdd = attachments.length < 3 && !widget.isPastTechCompleted;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderGrey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$title (${attachments.length}/3)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
              ),
              const Spacer(),
              // Camera button >= 48dp touch target
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  key: Key('line_${widget.line.id}_camera_${kind.name}'),
                  icon: const Icon(Icons.photo_camera, size: 22),
                  tooltip: 'Capture from camera',
                  onPressed: canAdd ? () => _handleCapture(kind, ImageSource.camera) : null,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Gallery button >= 48dp touch target
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  key: Key('line_${widget.line.id}_gallery_${kind.name}'),
                  icon: const Icon(Icons.photo_library_outlined, size: 22),
                  tooltip: 'Select from gallery',
                  onPressed: canAdd ? () => _handleCapture(kind, ImageSource.gallery) : null,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          if (attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No photos captured yet.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final att in attachments) ...[
                    _buildThumbnail(att),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThumbnail(LineAttachment attachment) {
    Color badgeColor;
    IconData badgeIcon;
    String badgeText;

    if (attachment.isFailed) {
      badgeColor = AppTheme.errorRed;
      badgeIcon = Icons.warning_amber_rounded;
      badgeText = 'failed';
    } else if (attachment.isPending) {
      badgeColor = AppTheme.warningAmber;
      badgeIcon = Icons.sync;
      badgeText = 'queued';
    } else {
      badgeColor = AppTheme.successGreen;
      badgeIcon = Icons.check_circle;
      badgeText = 'uploaded';
    }

    final hasLocal = attachment.localPath != null &&
        File(attachment.localPath!).existsSync();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          key: Key('line_attachment_thumb_${attachment.idempotencyKey ?? attachment.id}'),
          onTap: () => _showFullscreenImage(attachment),
          // Delete is hidden past TECH_COMPLETED (server rule); the dialog
          // handler keeps a refusal backstop for races.
          onLongPress: widget.isPastTechCompleted
              ? null
              : () => _handleDelete(attachment),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 76,
                  height: 76,
                  color: AppTheme.borderGrey.withOpacity(0.3),
                  child: hasLocal
                      ? Image.file(
                          File(attachment.localPath!),
                          fit: BoxFit.cover,
                        )
                      : attachment.url.isNotEmpty
                          ? Image.network(
                              attachment.url,
                              headers: _authHeaders(),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image,
                                color: AppTheme.textSecondary,
                              ),
                            )
                          : const Icon(
                              Icons.image,
                              color: AppTheme.textSecondary,
                            ),
                ),
              ),
              // Icon-only sync badge: glyph + colour (never colour alone),
              // with a tooltip instead of sub-12sp text.
              Positioned(
                top: 3,
                right: 3,
                child: Tooltip(
                  message: badgeText,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(badgeIcon, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (attachment.isFailed) ...[
          const SizedBox(height: 4),
          SizedBox(
            height: 28,
            child: TextButton.icon(
              key: Key('retry_attachment_${attachment.idempotencyKey ?? attachment.id}'),
              icon: const Icon(Icons.refresh, size: 13, color: AppTheme.errorRed),
              label: Text(
                'Retry',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.errorRed,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(48, 28),
              ),
              onPressed: () => _handleRetry(attachment),
            ),
          ),
        ],
      ],
    );
  }
}
