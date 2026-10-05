import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Manages and caches the bundled Microsoft Selawik font family
/// (Regular and Bold are advance-compatible with Segoe UI; Semibold is not,
/// see tool/report_parity/BASELINE.md).
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

  /// Weight helper mapping CSS font-weight to the bundled faces:
  /// 400 -> regular
  /// 500 / 600 -> semibold (Chrome on Windows renders CSS 500 as Segoe UI
  ///   Semibold, measured in the reference PDFs)
  /// 700+ -> bold
  static pw.Font fontForWeight(int weight) {
    if (weight >= 700) return bold;
    if (weight >= 500) return semibold;
    return regular;
  }

  static final Map<pw.Font, TtfParser> _parsers = {};

  static TtfParser? _parserFor(pw.Font font) {
    if (font is! pw.TtfFont) return null;
    return _parsers.putIfAbsent(font, () => TtfParser(font.data));
  }

  /// Advance width in pt of [text] (a single line) set in the face for
  /// [weight] at [sizePt], using the font's real glyph advances (no kerning,
  /// exactly as the pdf package typesets it).
  static double advance(
    String text,
    double sizePt, {
    int weight = 400,
    double letterSpacingPt = 0,
  }) {
    if (text.isEmpty) return 0;
    final parser = _parserFor(fontForWeight(weight));
    if (parser == null) return text.runes.length * sizePt * 0.55;
    var em = 0.0;
    var count = 0;
    for (final code in text.runes) {
      final gid = parser.charToGlyphIndexMap[code] ?? 0;
      em += parser.glyphInfoMap[gid]?.advanceWidth ?? 0;
      count++;
    }
    return em * sizePt + letterSpacingPt * (count - 1);
  }
}
