import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// `GET /api/v1/maintenance/work-orders/reliability_metrics/?asset_id=&start_date=&end_date=`
/// scoped to one asset — the "Reliability Analysis (ISO 55000)" card on web
/// (`ReliabilityReport.jsx`). `mtbf`/`mttr`/`availability` are raw numbers
/// (hours / hours / percent) or `null` server-side — web formats them
/// client-side (`formatDuration`/`formatReliabilityMetric`), which
/// [displayMtbf]/[displayMttr]/[displayAvailability] below reproduce exactly,
/// including the "No failures"/"Not assessed"/"Insufficient data" fallbacks,
/// so mobile never invents a number the server didn't actually compute for a
/// data-sparse asset.
class ReliabilityMetrics extends Equatable {
  const ReliabilityMetrics({
    this.mtbfHours,
    this.mttrHours,
    this.availabilityPercent,
    this.failures = 0,
    this.completedFailures = 0,
    this.downtimeHours = 0,
    this.exposureHours = 0,
    this.operatingHours = 0,
    this.assessmentStatus,
    this.periodStart,
    this.periodEnd,
  });

  final double? mtbfHours;
  final double? mttrHours;
  final double? availabilityPercent;
  final int failures;
  final int completedFailures;
  final double downtimeHours;
  final double exposureHours;
  final double operatingHours;
  final String? assessmentStatus;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  static String _formatDuration(double hours) {
    if (hours == 0) return '0 min';
    final totalMinutes = (hours * 60).round();
    final days = totalMinutes ~/ (24 * 60);
    final remainder = totalMinutes % (24 * 60);
    final h = remainder ~/ 60;
    final m = remainder % 60;
    final parts = <String>[
      if (days > 0) '$days day${days == 1 ? '' : 's'}',
      if (h > 0) '$h hour${h == 1 ? '' : 's'}',
      if (m > 0 || (days == 0 && h == 0)) '$m min',
    ];
    return parts.join(', ');
  }

  String get displayMtbf {
    if (mtbfHours != null) return _formatDuration(mtbfHours!);
    if (assessmentStatus == 'NOT_ASSESSED') return 'Not assessed';
    if (failures == 0) return 'No failures';
    return 'Insufficient data';
  }

  String get displayMttr {
    if (mttrHours != null) return _formatDuration(mttrHours!);
    if (assessmentStatus == 'NOT_ASSESSED') return 'Not assessed';
    if (completedFailures == 0) return 'No completed failures';
    return 'Insufficient data';
  }

  String get displayAvailability =>
      availabilityPercent != null ? '${availabilityPercent!.toStringAsFixed(1)}%' : 'Not assessed';

  factory ReliabilityMetrics.fromJson(Map<String, dynamic> json) {
    final global = json['global'] is Map
        ? Map<String, dynamic>.from(json['global'] as Map)
        : const <String, dynamic>{};
    final period = json['period'] is Map
        ? Map<String, dynamic>.from(json['period'] as Map)
        : const <String, dynamic>{};
    DateTime? parseDate(dynamic v) =>
        v == null ? null : asJsonDateTime(v);
    double? asDoubleOrNull(dynamic v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
    double asDouble(dynamic v) => asDoubleOrNull(v) ?? 0;

    return ReliabilityMetrics(
      mtbfHours: asDoubleOrNull(global['mtbf']),
      mttrHours: asDoubleOrNull(global['mttr']),
      availabilityPercent: asDoubleOrNull(global['availability']),
      failures: asJsonInt(global['failures']) ?? 0,
      completedFailures: asJsonInt(json['completed_failures']) ?? 0,
      downtimeHours: asDouble(global['downtime_hours']),
      exposureHours: asDouble(json['exposure_hours']),
      operatingHours: asDouble(json['operating_hours']),
      assessmentStatus: asJsonString(json['assessment_status']),
      periodStart: parseDate(period['start']),
      periodEnd: parseDate(period['end']),
    );
  }

  @override
  List<Object?> get props => [
        mtbfHours,
        mttrHours,
        availabilityPercent,
        failures,
        completedFailures,
        downtimeHours,
        exposureHours,
        operatingHours,
        assessmentStatus,
        periodStart,
        periodEnd,
      ];
}
