import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Manages and caches the bundled Microsoft Selawik font family
/// (metric-compatible with Segoe UI).
class ReportFonts {
  ReportFonts._();

  static pw.Font? _regular;
  static pw.Font? _semibold;
  static pw.Font? _bold;

  static pw.Font get regular => _regular!;
  static pw.Font get semibold => _semibold!;
  static pw.Font get bold => _bold!;

  /// Loads fonts from rootBundle if not already cached.
  static Future<void> load() async {
    if (_regular != null && _semibold != null && _bold != null) return;

    final regData = await rootBundle.load('assets/fonts/report/selawk.ttf');
    final semiData = await rootBundle.load('assets/fonts/report/selawksb.ttf');
    final boldData = await rootBundle.load('assets/fonts/report/selawkb.ttf');

    _regular = pw.Font.ttf(regData);
    _semibold = pw.Font.ttf(semiData);
    _bold = pw.Font.ttf(boldData);
  }

  /// Weight helper mapping CSS font-weight:
  /// 400 / 500 -> regular
  /// 600 -> semibold
  /// 700+ -> bold
  static pw.Font fontForWeight(int weight) {
    if (weight >= 700) return bold;
    if (weight >= 600) return semibold;
    return regular;
  }
}
