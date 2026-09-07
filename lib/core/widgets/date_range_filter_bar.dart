import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Formats a calendar day for the maintenance/complaint/inspection query APIs.
String? formatApiDate(DateTime? date) {
  if (date == null) return null;
  return DateFormat('yyyy-MM-dd').format(date);
}

/// Compact from/to date chips plus a clear control.
///
/// Each chip opens [showDatePicker]. Used by Work Orders, Complaints, and
/// Inspections (and Reports) so the three list screens do not duplicate the row.
class DateRangeFilterBar extends StatelessWidget {
  const DateRangeFilterBar({
    super.key,
    this.from,
    this.to,
    required this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 8),
  });

  final DateTime? from;
  final DateTime? to;
  final void Function(DateTime? from, DateTime? to) onChanged;
  final EdgeInsetsGeometry padding;

  static final DateFormat _labelFormat = DateFormat('dd MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final hasRange = from != null || to != null;

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: _DateChip(
              key: const Key('date_range_from'),
              label: from == null ? 'From' : _labelFormat.format(from!),
              filled: from != null,
              onTap: () => _pick(context, isFrom: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _DateChip(
              key: const Key('date_range_to'),
              label: to == null ? 'To' : _labelFormat.format(to!),
              filled: to != null,
              onTap: () => _pick(context, isFrom: false),
            ),
          ),
          if (hasRange)
            IconButton(
              key: const Key('date_range_clear'),
              tooltip: 'Clear dates',
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => onChanged(null, null),
            ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context, {required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom ? (from ?? to ?? now) : (to ?? from ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;

    var nextFrom = isFrom ? picked : from;
    var nextTo = isFrom ? to : picked;
    if (nextFrom != null && nextTo != null && nextFrom.isAfter(nextTo)) {
      if (isFrom) {
        nextTo = nextFrom;
      } else {
        nextFrom = nextTo;
      }
    }
    onChanged(nextFrom, nextTo);
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: filled ? AppTheme.railwayBlue : AppTheme.borderGrey,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 14,
                color: filled ? AppTheme.railwayBlue : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: filled ? FontWeight.w600 : FontWeight.normal,
                    color: filled ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
