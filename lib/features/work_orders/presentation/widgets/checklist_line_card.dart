import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';

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

class ChecklistLineCard extends StatefulWidget {
  const ChecklistLineCard({
    super.key,
    required this.line,
    required this.onSave,
  });

  final MaintenanceRecordLine line;
  final void Function(ChecklistLineEdit edit) onSave;

  @override
  State<ChecklistLineCard> createState() => _ChecklistLineCardState();
}

class _ChecklistLineCardState extends State<ChecklistLineCard> {
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, line),
            const Divider(height: 18),
            ..._buildValueInput(line),
            if (line.statusOptions.isNotEmpty) ..._buildStatusAndAction(line),
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
          child: Text(
            'Deficiency flagged - pending severity review',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
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
}
