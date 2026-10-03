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

    final metas = <(String, String)>[
      ('Location', record.stationName ?? notSpecified),
      ('Schedule', record.templateName ?? notSpecified),
      ('Job Work', record.workOrderTicket ?? notSpecified),
      ('Date', dateStr),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      // Same colour as the app bar above it, in either theme, so the header
      // reads as one identity band.
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor ?? AppTheme.primaryDark,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SOUTHERN RAILWAY',
            textAlign: TextAlign.center,
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
              textAlign: TextAlign.center,
              style: textTheme.labelMedium?.copyWith(color: Colors.white70),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 16.0;
                // Two columns only when each half stays comfortably wide.
                final twoColumns = constraints.maxWidth >= 300 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 14 * 1.3;
                final itemWidth = twoColumns
                    ? ((constraints.maxWidth - gap) / 2).floorToDouble()
                    : constraints.maxWidth;
                return Wrap(
                  spacing: gap,
                  runSpacing: 6,
                  children: [
                    for (final m in metas)
                      SizedBox(
                        width: itemWidth,
                        child: _buildHeaderMeta(context, m.$1, m.$2),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMeta(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white70,
          ),
        ),
        Text(
          value,
          softWrap: true,
          // Amber on the navy band: ≈7.8:1, readable in sunlight.
          style: textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppTheme.warningAmber,
          ),
        ),
      ],
    );
  }
}
