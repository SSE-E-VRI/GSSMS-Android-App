import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/services/report_pdf/segoe_kerning.dart';

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

  /// Tracking in em applied to every CSS weight 500-699 run (Semibold).
  ///
  /// Selawik Semibold is not metric compatible with Segoe UI Semibold (93 of
  /// 95 ASCII advances differ, digits by up to 40%). Measured over the 828
  /// Semibold words printed by the 13 web reference PDFs (Selawik Semibold
  /// advances plus Segoe's kerning against Chrome's real word widths): the
  /// least-squares tracking is -0.0105 em per glyph gap, and -0.010 em takes
  /// the mean absolute word-width error from 0.61pt to 0.20pt (p95 1.65pt ->
  /// 1.35pt, max 4.5pt -> 3.1pt). The residual is per glyph (digits, a few
  /// letters), which one tracking value cannot fix. Regular and Bold advances
  /// are identical to Segoe's, so they need none.
  static const double semiboldTrackingEm = -0.010;

  /// Tracking in em applied to italic runs. Selawik has no italic; the report
  /// shears Regular, which is wider than Segoe UI Italic. Measured over the
  /// 29 italic lines of the web PDFs (Selawik Regular advances against Chrome's
  /// real Segoe UI Italic line widths): least-squares -0.0177 em per glyph gap;
  /// -0.018 takes the mean absolute line-width error from 2.9pt to 0.8pt (max
  /// 4.1pt -> 1.8pt).
  static const double italicTrackingEm = -0.018;

  /// Tracking (em) the weight-[weight] face needs to match Segoe UI.
  static double trackingEm(int weight, {bool italic = false}) =>
      (weight >= 500 && weight < 700 ? semiboldTrackingEm : 0.0) +
      (italic ? italicTrackingEm : 0.0);

  /// Pair kerning in em of [text] (adjacent code points) as Chrome applies it
  /// with Segoe UI's GPOS `kern` feature; the pdf package has no kerning.
  /// Semibold and Bold have their own tables.
  static double kerningEm(String text, {int weight = 400}) {
    final table = weight >= 700
        ? segoeBoldKerning
        : weight >= 500
            ? segoeSemiboldKerning
            : segoeRegularKerning;
    var units = 0;
    int? prev;
    for (final r in text.runes) {
      if (prev != null) {
        units += table[String.fromCharCode(prev) + String.fromCharCode(r)] ?? 0;
      }
      prev = r;
    }
    return units / 2048;
  }

  /// Width in pt of one space of [font] at [sizePt].
  static double spaceAdvance(pw.Font font, double sizePt) {
    final parser = _parserFor(font);
    if (parser == null) return sizePt * 0.274;
    final gid = parser.charToGlyphIndexMap[0x20] ?? 0;
    return (parser.glyphInfoMap[gid]?.advanceWidth ?? 0.274) * sizePt;
  }

  static final Map<pw.Font, TtfParser> _parsers = {};

  static TtfParser? _parserFor(pw.Font font) {
    if (font is! pw.TtfFont) return null;
    return _parsers.putIfAbsent(font, () => TtfParser(font.data));
  }

  /// Advance width in pt of [text] (a single line) set in the face for
  /// [weight] at [sizePt], using the font's real glyph advances (no kerning,
  /// exactly as the pdf package typesets it) plus what [cssRich] adds to match
  /// Chrome: the Semibold tracking and Segoe UI's pair kerning.
  static double advance(
    String text,
    double sizePt, {
    int weight = 400,
    double letterSpacingPt = 0,
    bool italic = false,
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
    return (em + kerningEm(text, weight: weight)) * sizePt +
        (letterSpacingPt + trackingEm(weight, italic: italic) * sizePt) *
            (count - 1);
  }
}
