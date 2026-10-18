import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';

/// Form section capturing ISO 55000 failure code classification and restored
/// time for Critical and High criticality asset breakdown & rectification logs.
class FailureDetailsSection extends StatelessWidget {
  const FailureDetailsSection({
    super.key,
    this.assetCriticality,
    required this.requiresFailureDetails,
    this.failureCode,
    this.onFailureCodeChanged,
    this.restoredTime,
    this.onRestoredTimeChanged,
    this.breakdownTime,
    this.failureCodeOptions = const [],
    this.enabled = true,
    this.failureCodeError,
    this.restoredTimeError,
  });

  final String? assetCriticality;
  final bool requiresFailureDetails;
  final int? failureCode;
  final ValueChanged<int?>? onFailureCodeChanged;
  final DateTime? restoredTime;
  final ValueChanged<DateTime?>? onRestoredTimeChanged;
  final DateTime? breakdownTime;
  final List<FailureCodeOption> failureCodeOptions;
  final bool enabled;
  final String? failureCodeError;
  final String? restoredTimeError;

  static final DateFormat _dateTimeFormat =
      DateFormat('dd MMM yyyy, hh:mm a');

  Future<void> _pickRestoredDateTime(BuildContext context) async {
    if (!enabled) return;
    final initial = restoredTime ?? DateTime.now();
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      helpText: 'Select restored date',
    );
    if (pickedDate == null || !context.mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Select restored time',
    );
    if (pickedTime == null || !context.mounted) return;

    final dt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    onRestoredTimeChanged?.call(dt);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final theme = Theme.of(context);
    final isCritical = const {'CRITICAL', 'HIGH'}
        .contains((assetCriticality ?? '').toUpperCase().trim());

    // Guard: Ensure selected value exists in options, else null.
    final selectedCode = failureCodeOptions.any((fc) => fc.id == failureCode)
        ? failureCode
        : null;

    return SectionCard(
      title: 'Failure Code & Restoration Details',
      icon: Icons.sell_outlined,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (requiresFailureDetails)
            const StatusChip(
              key: Key('iso55000_mandatory_badge'),
              label: 'ISO 55000 Mandatory',
              tone: GssmsTone.danger,
              icon: Icons.shield_outlined,
            )
          else
            const StatusChip(
              label: 'Optional',
              tone: GssmsTone.neutral,
            ),
          if (assetCriticality != null && assetCriticality!.isNotEmpty) ...[
            const SizedBox(width: GssmsSpacing.s6),
            StatusChip(
              key: const Key('asset_criticality_badge'),
              label: assetCriticality!,
              tone: isCritical ? GssmsTone.warning : GssmsTone.neutral,
            ),
          ],
        ],
      ),
      children: [
        if (requiresFailureDetails) ...[
          Container(
            padding: const EdgeInsets.all(GssmsSpacing.s12),
            decoration: BoxDecoration(
              color: tokens.tone(GssmsTone.info).background,
              borderRadius: BorderRadius.circular(GssmsRadius.r8),
              border: Border.all(color: tokens.tone(GssmsTone.info).border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: tokens.tone(GssmsTone.info).foreground,
                ),
                const SizedBox(width: GssmsSpacing.s8),
                Expanded(
                  child: Text(
                    'ISO 55000 compliance requires Failure Code classification and Restored Time for Critical and High criticality assets before Technical Completion.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.tone(GssmsTone.info).foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: GssmsSpacing.s12),
        ],

        // Failure Code Dropdown
        DropdownButtonFormField<int?>(
          key: const Key('failure_code_dropdown'),
          value: selectedCode,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: requiresFailureDetails
                ? 'Failure Code *'
                : 'Failure Code',
            errorText: failureCodeError,
            helperText:
                'Equipment failure cause category and classification code.',
            helperMaxLines: 2,
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('-- Select Failure Code --'),
            ),
            ...failureCodeOptions.map(
              (fc) => DropdownMenuItem<int?>(
                key: Key('failure_code_option_${fc.id}'),
                value: fc.id,
                child: Text(
                  fc.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: enabled
              ? (val) => onFailureCodeChanged?.call(val)
              : null,
        ),
        const SizedBox(height: GssmsSpacing.s16),

        // Restored Time Header + "Set to Now" Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              requiresFailureDetails ? 'RESTORED TIME *' : 'RESTORED TIME',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: restoredTimeError != null
                    ? theme.colorScheme.error
                    : tokens.textSecondary,
              ),
            ),
            if (enabled)
              TextButton.icon(
                key: const Key('set_to_now_button'),
                onPressed: () => onRestoredTimeChanged?.call(DateTime.now()),
                icon: const Icon(Icons.access_time, size: 16),
                label: const Text('Set to Now'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GssmsSpacing.s8,
                    vertical: GssmsSpacing.s4,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: GssmsSpacing.s4),

        // Restored Time Picker Field
        InkWell(
          key: const Key('restored_time_picker'),
          onTap: enabled ? () => _pickRestoredDateTime(context) : null,
          borderRadius: BorderRadius.circular(GssmsRadius.r8),
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              errorText: restoredTimeError,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (restoredTime != null && enabled)
                    IconButton(
                      key: const Key('clear_restored_time_button'),
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Clear restored time',
                      onPressed: () => onRestoredTimeChanged?.call(null),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.calendar_today_outlined, size: 20),
                  ),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(GssmsRadius.r8),
              ),
            ),
            child: Text(
              restoredTime != null
                  ? _dateTimeFormat.format(restoredTime!)
                  : 'Select restored date & time',
              style: restoredTime != null
                  ? theme.textTheme.bodyMedium
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
            ),
          ),
        ),

        const SizedBox(height: GssmsSpacing.s4),
        Text(
          breakdownTime != null
              ? 'Breakdown occurred: ${_dateTimeFormat.format(breakdownTime!)}'
              : 'Timestamp when asset was returned to operational service.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
      ],
    );
  }
}
