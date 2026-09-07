import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';

class StatusDonutChart extends StatelessWidget {
  const StatusDonutChart({
    super.key,
    required this.segments,
    required this.total,
    this.title = 'Job Work Overview',
  });

  final List<WorkOrderStatusSegment> segments;
  final int total;
  final String title;

  Color _parseColor(String? hex, int index) {
    if (hex != null && hex.isNotEmpty) {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) {
        final val = int.tryParse('FF$clean', radix: 16);
        if (val != null) return Color(val);
      }
    }
    const defaultColors = [
      AppTheme.railwayGreen,
      AppTheme.warningAmber,
      AppTheme.errorRed,
      AppTheme.railwayBlue,
      Colors.purple,
      Colors.teal,
    ];
    return defaultColors[index % defaultColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final displaySegments = segments.isEmpty
        ? const [WorkOrderStatusSegment(label: 'No Data', count: 1, colorHex: 'CCCCCC')]
        : segments;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.railwayBlue),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: Stack(
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 50,
                      sections: List.generate(displaySegments.length, (i) {
                        final seg = displaySegments[i];
                        final color = _parseColor(seg.colorHex, i);
                        return PieChartSectionData(
                          color: color,
                          value: seg.count.toDouble(),
                          title: '',
                          radius: 20,
                        );
                      }),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$total',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: List.generate(displaySegments.length, (i) {
                final seg = displaySegments[i];
                final color = _parseColor(seg.colorHex, i);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${seg.label}: ${seg.count}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
