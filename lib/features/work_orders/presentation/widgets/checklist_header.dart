import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';

/// Full railway and location metadata header for the checklist screen.
class ChecklistHeader extends StatelessWidget {
  const ChecklistHeader({super.key, required this.record});

  final MaintenanceRecord record;

  @override
  Widget build(BuildContext context) {
    const notSpecified = 'Not specified';
    final dateStr = record.dateOfMaintenance != null
        ? DateFormat('dd/MM/yyyy').format(record.dateOfMaintenance!)
        : notSpecified;

    final orgLine = [record.divisionName, record.depotName]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' · ');

    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      // Same colour as the app bar above it, in either theme, so the header
      // reads as one identity band.
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor ?? AppTheme.primaryDark,
      ),
      child: SafeArea(
        bottom: false,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SOUTHERN RAILWAY',
                style: textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              if (orgLine.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  orgLine,
                  style: textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceAround,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _buildHeaderMeta(context, 'Location',
                        record.stationName ?? notSpecified),
                    _buildHeaderMeta(context, 'Schedule',
                        record.templateName ?? notSpecified),
                    _buildHeaderMeta(context, 'Job Work',
                        record.workOrderTicket ?? notSpecified),
                    _buildHeaderMeta(context, 'Date', dateStr),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderMeta(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(
        style: textTheme.labelSmall?.copyWith(color: Colors.white),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          TextSpan(
            text: value,
            // Amber on the navy band: ≈7.8:1, readable in sunlight.
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.warningAmber,
            ),
          ),
        ],
      ),
    );
  }
}
