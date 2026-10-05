import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/report_fonts.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/report_pdf_theme.dart';

export 'package:gssms_mobile/features/work_orders/services/report_pdf/report_fonts.dart';
export 'package:gssms_mobile/features/work_orders/services/report_pdf/report_pdf_theme.dart';

/// Cmap-aware safe string mapping.
/// Selawik includes: — (0x2014), – (0x2013), · (0x00B7), • (0x2022),
/// ‘ ’ “ ” (0x2018, 0x2019, 0x201C, 0x201D), … (0x2026).
/// Only maps code points Selawik lacks (₹ -> Rs.).
String pdfSafe(String? s) {
  if (s == null || s.isEmpty) return '';
  return s.replaceAll('₹', 'Rs.');
}

/// Chrome's A4 (595.92 x 842.88pt) with the 1cm print margin (27.75pt), the
/// page the web report is printed on. `PdfPageFormat.a4` is 595.28 x 841.89.
const PdfPageFormat reportPageFormat = PdfPageFormat(
  595.92,
  842.88,
  marginLeft: 27.75,
  marginTop: 27.75,
  marginBottom: 27.75,
  // Chrome lays the report out 720px (540pt) wide from the left margin: the
  // right margin takes the remaining 0.42pt of the page.
  marginRight: 595.92 - 27.75 - reportContentWidth,
);

/// Width in pt of the report content column (720 css px).
const double reportContentWidth = 540.0;

const pdfBorderColor = ReportPdfTheme.border;
const pdfBorderSide = pw.BorderSide(color: pdfBorderColor, width: 0.75);

/// The CSS line-height inherited by report text (Bootstrap body 1.5 for the
/// Checklist and Inspection reports, `.reportContainer` 1.4 for Breakdown and
/// Rectification). [JobWorkReportPdfService] sets this before building each
/// kind; primitives that take an optional `lineHeight` fall back to it.
class ReportRoot {
  ReportRoot._();
  static double lineHeight = 1.5;
}

// ---------------------------------------------------------------------------
// P1: CSS line boxes
// ---------------------------------------------------------------------------

/// Selawik hhea metrics: ascender 2027, descender -431 per 2048 em, so a
/// natural (pdf `Text`) line is 1.2002 em and its baseline sits 0.98975 em
/// below the line top.
const double _selawikLineHeight = 1.2002;
const double _selawikBaseline = 0.98975;

/// Segoe UI hhea ascent / descent in em (2210 / 514 per 2048).
const double _segoeAscent = 2210 / 2048;
const double _segoeDescent = 514 / 2048;

/// CSS px -> pt.
const double _pxToPt = 0.75;

/// Chrome's rounding of a font metric in px (Skia `SkScalarRoundToScalar`).
double _roundPx(double v) => (v + 0.5).floorToDouble();

/// Distance in pt from the top of a CSS line box (line-height [lineHeight],
/// inherited as a number) to its baseline for Segoe UI at [sizePt], following
/// Chrome's integer-px model: ascent and descent are rounded to whole px, the
/// half-leading is `floor((line-height - (ascent + descent)) / 2)` px (LayoutNG
/// `CalculateLeadingSpace`), and the baseline is half-leading + ascent. This
/// reproduces the web print exactly, e.g. 13.5pt for 12pt text at 1.5.
double cssBaselinePt(double lineHeight, double sizePt) {
  final px = sizePt / _pxToPt;
  final ascent = _roundPx(_segoeAscent * px);
  final descent = _roundPx(_segoeDescent * px);
  // LayoutUnit precision is 1/64 px.
  final lhPx = (lineHeight * px * 64).floorToDouble() / 64;
  final halfLeading = ((lhPx - (ascent + descent)) / 2).floorToDouble();
  return (halfLeading + ascent) * _pxToPt;
}

/// `TextStyle.lineSpacing` that turns pdf's 1.2002 em natural line pitch into
/// a CSS pitch of [lineHeight] * [sizePt].
double cssLineSpacing(double lineHeight, double sizePt) =>
    (lineHeight - _selawikLineHeight) * sizePt;

/// Space above the first line so its baseline matches CSS. [strutSizePt] is
/// the font size of the line's strut (the block's own font) when it differs
/// from the text [sizePt] (a small inline span in a larger block).
double cssInsetTop(double lineHeight, double sizePt, {double? strutSizePt}) =>
    cssBaselinePt(lineHeight, strutSizePt ?? sizePt) -
    _selawikBaseline * sizePt;

/// Space below the last line so a block of n lines is exactly
/// n * lineHeight * strut size tall. Can be negative (line-height 1.2): the
/// negative padding is honoured by [pw.Padding] (box shrinks, child paints
/// below its box by the same amount).
double cssInsetBottom(double lineHeight, double sizePt, {double? strutSizePt}) =>
    lineHeight * (strutSizePt ?? sizePt) -
    cssInsetTop(lineHeight, sizePt, strutSizePt: strutSizePt) -
    _selawikLineHeight * sizePt;

/// One run of a [cssRich] paragraph. Unset fields inherit from the paragraph.
class CssSpan {
  const CssSpan(
    this.text, {
    this.weight,
    this.color,
    this.sizePx,
    this.sizePt,
    this.trailingGapPt = 0,
    this.letterSpacingEm,
  });

  final String text;
  final int? weight;
  final PdfColor? color;
  final double? sizePx;
  final double? sizePt;

  /// Extra space in pt after the last glyph (CSS `margin-right` on an inline
  /// label). The gap is exact; it may be negative. The text must not end in
  /// whitespace.
  final double trailingGapPt;

  /// CSS `letter-spacing` in em for this run (overrides the paragraph's).
  final double? letterSpacingEm;
}

/// Letter spacings below this (pt) are applied as plain `letterSpacing` (the
/// Semibold tracking compensation); larger ones get the exact CSS treatment
/// described at [_cssSpans].
const double _exactSpacingPt = 0.2;

/// One styled run of a [cssRich] paragraph with every inherited value
/// resolved (text already upper-cased / pdf-safe).
class _Run {
  const _Run(this.text, this.weight, this.color, this.pt, this.lsPt, this.gap);
  final String text;
  final int weight;
  final PdfColor color;
  final double pt;
  final double lsPt;
  final double gap;
  _Run withText(String t, {double? gap}) =>
      _Run(t, weight, color, pt, lsPt, gap ?? 0);
}

/// Slant of Segoe UI Italic (post.italicAngle -12 degrees): tan(12 deg).
const double _italicSlant = 0.2126;

/// A paragraph of mixed-weight runs with CSS line-height semantics: every
/// line box is [lineHeight] * size tall and the first baseline sits exactly
/// where Chrome puts it. Replaces `pw.RichText`.
///
/// [strutSizePt] is the block's own font size when the text is a smaller
/// inline span inside a larger block (line box and baseline follow the strut).
///
/// Italic text (Selawik has no italic) is Regular sheared by Segoe UI
/// Italic's 12 degrees about each line's baseline, so it is wrapped here
/// (greedy, with Segoe-compatible advances, kerning and tracking) and every
/// line sheared on its own; a single shear of the whole paragraph would shift
/// each line by its height.
pw.Widget cssRich(
  List<CssSpan> spans, {
  double sizePx = 13.0,
  double? sizePt,
  int weight = 400,
  PdfColor color = ReportPdfTheme.inkPrint,
  required double lineHeight,
  double? strutSizePt,
  bool upper = false,
  double? letterSpacingEm,
  bool italic = false,
  pw.TextAlign? align,
  int? maxLines,
  bool softWrap = true,
}) {
  final basePt = sizePt ?? ReportPdfTheme.px(sizePx);
  final strutPt = strutSizePt ?? basePt;
  final lineSpacing = lineHeight * strutPt - _selawikLineHeight * basePt;

  final runs = <_Run>[];
  for (final s in spans) {
    if (s.text.isEmpty) continue;
    final pt = s.sizePt ??
        (s.sizePx != null ? ReportPdfTheme.px(s.sizePx!) : basePt);
    final text = upper ? pdfSafe(s.text).toUpperCase() : pdfSafe(s.text);
    runs.add(_Run(text, s.weight ?? weight, s.color ?? color, pt,
        (s.letterSpacingEm ?? letterSpacingEm ?? 0) * pt, s.trailingGapPt));
  }

  pw.Widget plain(List<_Run> line, {required bool wrap}) {
    final children = <pw.TextSpan>[];
    for (final r in line) {
      children.addAll(_cssSpans(
        r.text,
        font: ReportFonts.fontForWeight(r.weight),
        weight: r.weight,
        sizePt: r.pt,
        color: r.color,
        letterSpacingPt: r.lsPt,
        trackingPt: ReportFonts.trackingEm(r.weight, italic: italic) * r.pt,
        gapPt: r.gap,
        lineSpacing: lineSpacing,
      ));
    }
    return _SnapBaseline(
      baseline: cssBaselinePt(lineHeight, strutPt),
      child: pw.Padding(
        padding: pw.EdgeInsets.only(
          top: cssInsetTop(lineHeight, basePt, strutSizePt: strutSizePt),
          bottom: cssInsetBottom(lineHeight, basePt, strutSizePt: strutSizePt),
        ),
        child: pw.RichText(
          text: pw.TextSpan(
            style: pw.TextStyle(font: ReportFonts.regular),
            children: children,
          ),
          textAlign: align,
          maxLines: maxLines,
          softWrap: wrap,
        ),
      ),
    );
  }

  if (!italic) return plain(runs, wrap: softWrap);

  final shear = Matrix4.identity()
    ..setEntry(0, 1, _italicSlant)
    // Keep the first baseline in place (the pivot is the top-left corner).
    ..setEntry(0, 3, _italicSlant * cssBaselinePt(lineHeight, strutPt));
  return pw.LayoutBuilder(builder: (context, constraints) {
    final maxW = softWrap && constraints != null && constraints.hasBoundedWidth
        ? constraints.maxWidth
        : double.infinity;
    var lines = _wrapRuns(runs, maxW);
    if (maxLines != null && lines.length > maxLines) {
      lines = lines.sublist(0, maxLines);
    }
    final stretch = align != null &&
        align != pw.TextAlign.left &&
        align != pw.TextAlign.start &&
        maxW.isFinite;
    return pw.Column(
      crossAxisAlignment:
          stretch ? pw.CrossAxisAlignment.stretch : pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        for (final line in lines)
          pw.Transform(
            alignment: pw.Alignment.topLeft,
            transform: shear,
            child: plain(line, wrap: false),
          ),
      ],
    );
  });
}

/// Greedy line breaking of [runs] at spaces within [maxW] (CSS `normal` /
/// `pre-wrap`: a newline breaks, a word wider than the line stays whole), measured
/// with the Segoe-compatible advances ([ReportFonts.advance]).
List<List<_Run>> _wrapRuns(List<_Run> runs, double maxW) {
  final lines = <List<_Run>>[[]];
  var x = 0.0;
  var lineHasWord = false;

  double width(_Run r, String t, {bool gap = false}) =>
      ReportFonts.advance(t, r.pt,
          weight: r.weight, letterSpacingPt: r.lsPt, italic: true) +
      r.lsPt +
      (gap ? r.gap : 0);

  void add(_Run r, String t, {double gap = 0}) {
    final line = lines.last;
    if (line.isNotEmpty &&
        line.last.weight == r.weight &&
        line.last.color == r.color &&
        line.last.pt == r.pt &&
        line.last.lsPt == r.lsPt &&
        line.last.gap == 0) {
      line[line.length - 1] = line.last.withText(line.last.text + t, gap: gap);
    } else {
      line.add(r.withText(t, gap: gap));
    }
  }

  void newLine() {
    // Trailing spaces hang off the end of a wrapped line.
    final line = lines.last;
    while (line.isNotEmpty && line.last.text.trim().isEmpty) {
      line.removeLast();
    }
    if (line.isNotEmpty && line.last.text.endsWith(' ')) {
      final l = line.last;
      line[line.length - 1] = l.withText(l.text.trimRight(), gap: l.gap);
    }
    lines.add([]);
    x = 0;
    lineHasWord = false;
  }

  for (final r in runs) {
    final tokens = RegExp(r'\n|[^\S\n]+|[^\s]+')
        .allMatches(r.text)
        .map((m) => m[0]!)
        .toList();
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      final last = i == tokens.length - 1;
      if (t == '\n') {
        newLine();
        continue;
      }
      final isSpace = t.trim().isEmpty;
      final w = width(r, t, gap: last);
      if (!isSpace && lineHasWord && x + w > maxW + 0.001) newLine();
      if (isSpace && !lineHasWord && lines.length > 1) {
        // Spaces at the start of a wrapped line are dropped.
        continue;
      }
      add(r, t, gap: last ? r.gap : 0);
      x += w;
      if (!isSpace) lineHasWord = true;
    }
  }
  return lines;
}

/// Longest word (glyphs) whose kerning is applied pair by pair; longer words
/// spread it evenly over their glyphs.
const int _kernSplitMaxGlyphs = 4;

/// Turns one CSS run into pdf [pw.TextSpan]s with CSS spacing and kerning.
///
/// The pdf package advances a span of one word by `advance + (n + 1) * ls`
/// (n glyphs: `n - 1` between glyphs plus two from its end-of-span
/// bookkeeping) and has no kerning, whereas CSS adds `ls` after every glyph
/// (spaces included) and Chrome applies Segoe UI's pair kerning. So:
///  * a letter-spaced word is a span of its own with
///    `ls = (kerning + n * css-ls [+ gap]) / (n + 1)`, which advances exactly as
///    CSS does (kerning spread evenly); its spaces grow by `ls` through
///    `wordSpacing`;
///  * in unspaced text a kerned word of up to [_kernSplitMaxGlyphs] glyphs, or
///    a word with a [CssSpan.trailingGapPt], is split so each glyph that
///    precedes a kern (or the gap) is a one-glyph span with `ls = kern / 2`
///    (pdf doubles it): glyph positions stay exact. Longer kerned words are one
///    span with the even spread;
///  * everything else stays in plain runs (`ls` 0, or the tiny Semibold
///    tracking), which are exact.
List<pw.TextSpan> _cssSpans(
  String text, {
  required pw.Font font,
  required int weight,
  required double sizePt,
  required PdfColor color,
  required double letterSpacingPt,
  required double trackingPt,
  required double gapPt,
  required double lineSpacing,
}) {
  pw.TextSpan make(String t, {double ls = 0, double? wordSpacing}) =>
      pw.TextSpan(
        text: t,
        style: pw.TextStyle(
          font: font,
          fontSize: sizePt,
          color: color,
          letterSpacing: ls,
          wordSpacing: wordSpacing,
          lineSpacing: lineSpacing,
        ),
      );

  final ls = letterSpacingPt + trackingPt;
  final exactLs = letterSpacingPt.abs() >= _exactSpacingPt;
  final tokens =
      RegExp(r'\S+|\s+').allMatches(text).map((m) => m[0]!).toList();
  var lastWord = -1;
  final kerned = <int>{};
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].trim().isEmpty) continue;
    lastWord = i;
    if (ReportFonts.kerningEm(tokens[i], weight: weight) != 0) kerned.add(i);
  }
  if (!exactLs && gapPt == 0 && kerned.isEmpty) return [make(text, ls: ls)];

  final spaceWs = exactLs ? _spaceScale(font, sizePt, ls) : null;
  final out = <pw.TextSpan>[];
  final plain = StringBuffer();
  void flush() {
    if (plain.isEmpty) return;
    out.add(make(plain.toString(), ls: ls));
    plain.clear();
  }

  // Kerning in pt between glyph j and j + 1 of [glyphs].
  double pairKern(List<String> glyphs, int j) =>
      ReportFonts.kerningEm(glyphs[j] + glyphs[j + 1], weight: weight) *
      sizePt;

  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t.trim().isEmpty) {
      if (exactLs) {
        flush();
        out.add(make(t, ls: 0, wordSpacing: spaceWs));
      } else {
        plain.write(t);
      }
      continue;
    }
    final gap = i == lastWord ? gapPt : 0.0;
    final glyphs = [for (final r in t.runes) String.fromCharCode(r)];
    final n = glyphs.length;
    if (exactLs) {
      flush();
      final k = ReportFonts.kerningEm(t, weight: weight) * sizePt;
      out.add(make(t, ls: (k + n * ls + gap) / (n + 1)));
    } else if (gap != 0 || (kerned.contains(i) && n <= _kernSplitMaxGlyphs)) {
      // One-glyph spans for the glyphs followed by a kern or the gap.
      for (var j = 0; j < n; j++) {
        final after = (j + 1 < n ? pairKern(glyphs, j) : 0.0) +
            (j == n - 1 ? gap : 0.0);
        if (after == 0) {
          plain.write(glyphs[j]);
        } else {
          flush();
          out.add(make(glyphs[j], ls: ls + after / 2));
        }
      }
    } else if (kerned.contains(i)) {
      flush();
      final k = ReportFonts.kerningEm(t, weight: weight) * sizePt;
      out.add(make(t, ls: (k + n * ls) / (n + 1)));
    } else {
      plain.write(t);
    }
  }
  flush();
  return out;
}

/// `TextStyle.wordSpacing` (a multiplier of the space advance) that makes each
/// space [extraPt] wider.
double _spaceScale(pw.Font font, double sizePt, double extraPt) {
  if (extraPt == 0) return 1.0;
  final space = ReportFonts.spaceAdvance(font, sizePt);
  return space <= 0 ? 1.0 : 1.0 + extraPt / space;
}

/// Styled text matching CSS font-size, line-height, letter-spacing, and
/// weight. [lineHeight] defaults to the report's inherited line-height
/// ([ReportRoot.lineHeight]).
pw.Widget cssText(
  String? text, {
  double sizePx = 13.0,
  double? sizePt,
  int weight = 400,
  PdfColor color = ReportPdfTheme.inkPrint,
  double? lineHeight,
  double? strutSizePt,
  bool upper = false,
  double? letterSpacingEm,
  bool italic = false,
  pw.TextAlign? align,
  int? maxLines,
  bool softWrap = true,
}) =>
    cssRich(
      [CssSpan(text ?? '')],
      sizePx: sizePx,
      sizePt: sizePt,
      weight: weight,
      color: color,
      lineHeight: lineHeight ?? ReportRoot.lineHeight,
      strutSizePt: strutSizePt,
      upper: upper,
      letterSpacingEm: letterSpacingEm,
      italic: italic,
      align: align,
      maxLines: maxLines,
      softWrap: softWrap,
    );

/// Width in pt of [text] (single line) at [sizePt] in the face for [weight].
double measureText(String text, double sizePt,
    {int weight = 400, double letterSpacingPt = 0, bool italic = false}) {
  var w = 0.0;
  for (final line in pdfSafe(text).split('\n')) {
    w = math.max(
        w,
        ReportFonts.advance(line, sizePt,
            weight: weight, letterSpacingPt: letterSpacingPt, italic: italic));
  }
  return w;
}

/// Kept for callers of the old helper; uses the real Selawik advances.
double measureSelawikWidth(String text, double fontSizePt) =>
    measureText(text, fontSizePt);

// ---------------------------------------------------------------------------
// P2: border-box emulation
// ---------------------------------------------------------------------------

/// One CSS border side.
class CssSide {
  const CssSide(this.width, this.color, {this.dashed = false});
  final double width;
  final PdfColor color;
  final bool dashed;
}

// ---------------------------------------------------------------------------
// Pixel snapping
// ---------------------------------------------------------------------------

/// Chrome paints boxes, borders, images and text baselines on whole device
/// px (1px = 0.75pt, the page origin is a px boundary) whatever the fractional
/// layout position. [PxSnap] snaps local paint coordinates the same way using
/// the canvas transform to find their absolute position on the page.
class PxSnap {
  PxSnap._(this._tx, this._ty, this._pageH, this._okX, this._okY);

  factory PxSnap.of(pw.Context context) {
    if (!kPixelSnap) return PxSnap._(0, 0, 0, false, false);
    final m = context.canvas.getTransform().storage;
    return PxSnap._(
      m[12],
      m[13],
      context.page.pageFormat.height,
      (m[0] - 1).abs() < 1e-9 && m[4].abs() < 1e-9 && m[1].abs() < 1e-9,
      (m[5] - 1).abs() < 1e-9 && m[1].abs() < 1e-9,
    );
  }

  final double _tx;
  final double _ty;
  final double _pageH;
  final bool _okX;
  final bool _okY;

  /// Snaps a local x (pt) to the px grid.
  double x(double v) =>
      !_okX ? v : ((v + _tx) / _pxToPt).roundToDouble() * _pxToPt - _tx;

  /// Snaps a local y (pt, pdf y-up) to the px grid measured from the page top.
  double y(double v) => !_okY
      ? v
      : _pageH -
          ((_pageH - (v + _ty)) / _pxToPt).roundToDouble() * _pxToPt -
          _ty;

  /// Absolute distance in pt from the page top of local y [v].
  double downFromTop(double v) => _pageH - (v + _ty);

  /// Snaps the rect (x, y up-from-bottom, w, h) edge by edge, like Chrome's
  /// pixel-snapped box.
  PdfRect rect(double x0, double y0, double w, double h) {
    final sx0 = x(x0);
    final sx1 = x(x0 + w);
    final sy0 = y(y0);
    final sy1 = y(y0 + h);
    return PdfRect(sx0, sy0, sx1 - sx0, sy1 - sy0);
  }
}

/// Switch for [PxSnap] (off = the unsnapped fractional positions).
const bool kPixelSnap = true;

/// Snaps the first baseline of a text block to a whole px like Chrome (the
/// block's top is where [baseline] pt below it the first baseline sits).
class _SnapBaseline extends pw.SingleChildWidget {
  _SnapBaseline({required this.baseline, required pw.Widget child})
      : super(child: child);

  final double baseline;

  @override
  void paint(pw.Context context) {
    super.paint(context);
    if (child == null) return;
    final snap = PxSnap.of(context);
    final top = box!.y + box!.height;
    final base = snap.downFromTop(top) + baseline;
    final snapped = (base / _pxToPt).roundToDouble() * _pxToPt;
    final shift = snap._okY ? base - snapped : 0.0;
    final mat = Matrix4.identity()..translate(box!.x, box!.y + shift);
    context.canvas
      ..saveContext()
      ..setTransform(mat);
    child!.paint(context);
    context.canvas.restoreContext();
  }
}

/// Snaps the rect of an image to whole px (edge by edge, so size changes by
/// up to a px like Chrome's pixel-snapped image rect).
class _SnapRect extends pw.SingleChildWidget {
  _SnapRect({required pw.Widget child}) : super(child: child);

  @override
  void paint(pw.Context context) {
    super.paint(context);
    if (child == null) return;
    final snap = PxSnap.of(context);
    final b = box!;
    final r = snap.rect(b.x, b.y, b.width, b.height);
    final sx = b.width > 0 ? r.width / b.width : 1.0;
    final sy = b.height > 0 ? r.height / b.height : 1.0;
    final mat = Matrix4.identity()
      ..translate(r.x, r.y)
      ..scale(sx, sy, 1);
    context.canvas
      ..saveContext()
      ..setTransform(mat);
    child!.paint(context);
    context.canvas.restoreContext();
  }
}

/// A `pw.Table` border painted the way Chrome paints collapsed borders: every
/// grid line is one filled rect on the pixel grid ([PxSnap]), horizontal lines
/// run the full width and the vertical lines run between them, so no joint is
/// painted twice (stacked, centred, anti-aliased strokes would darken it).
/// Sides that are [pw.BorderSide.none] are not painted; the lines are centred
/// on the table box edges and on the cell edges, as pw.Table's strokes were.
class CssTableBorder extends pw.TableBorder {
  const CssTableBorder({
    pw.BorderSide left = pw.BorderSide.none,
    pw.BorderSide top = pw.BorderSide.none,
    pw.BorderSide right = pw.BorderSide.none,
    pw.BorderSide bottom = pw.BorderSide.none,
    pw.BorderSide horizontalInside = pw.BorderSide.none,
    pw.BorderSide verticalInside = pw.BorderSide.none,
  }) : super(
          left: left,
          top: top,
          right: right,
          bottom: bottom,
          horizontalInside: horizontalInside,
          verticalInside: verticalInside,
        );

  bool _on(pw.BorderSide s) => s.style.paint && s.width > 0;

  @override
  void paintTable(pw.Context context, PdfRect box,
      [List<double?>? widths, List<double>? heights]) {
    final canvas = context.canvas;
    final snap = PxSnap.of(context);

    // Horizontal lines (centre y, side), top to bottom.
    final hs = <(double, pw.BorderSide)>[];
    if (_on(top)) hs.add((box.top, top));
    if (_on(horizontalInside) && heights != null) {
      var y = box.top;
      for (final h in heights.sublist(0, heights.length - 1)) {
        y -= h;
        hs.add((y, horizontalInside));
      }
    }
    if (_on(bottom)) hs.add((box.y, bottom));

    // Vertical lines (centre x, side), left to right.
    final vs = <(double, pw.BorderSide)>[];
    if (_on(left)) vs.add((box.x, left));
    if (_on(verticalInside) && widths != null) {
      var x = box.x;
      for (final w in widths.sublist(0, widths.length - 1)) {
        x += w!;
        vs.add((x, verticalInside));
      }
    }
    if (_on(right)) vs.add((box.right, right));

    void fill(PdfColor c, double x, double y, double w, double h) {
      final r = snap.rect(x, y, w, h);
      canvas
        ..setFillColor(c)
        ..drawRect(r.x, r.y, r.width, r.height)
        ..fillPath();
    }

    // Extent of the horizontals: out to the outer verticals' half widths.
    final xl = box.x - (_on(left) ? left.width / 2 : 0);
    final xr = box.right + (_on(right) ? right.width / 2 : 0);
    for (final (y, side) in hs) {
      fill(side.color, xl, y - side.width / 2, xr - xl, side.width);
    }
    // Verticals run between consecutive horizontals (or the box edges).
    final ys = <(double, double)>[]; // (top edge, bottom edge) of each gap
    var gapTop = box.top;
    for (final (y, side) in hs) {
      final edgeTop = y + side.width / 2;
      if (y >= box.top - 1e-6) {
        gapTop = y - side.width / 2;
        continue;
      }
      if (edgeTop < gapTop) ys.add((gapTop, edgeTop));
      gapTop = y - side.width / 2;
    }
    ys.add((gapTop, box.y + (_on(bottom) ? bottom.width / 2 : 0)));
    for (final (x, side) in vs) {
      for (final (t, b) in ys) {
        if (t <= b) continue;
        fill(side.color, x - side.width / 2, b, side.width, t - b);
      }
    }
  }
}

/// A CSS box (`box-sizing: border-box`). Unlike `pw.Container`, borders take
/// layout space and paint inside the border box, exactly like CSS: the
/// content offset is border + padding, and a border of width w covers
/// [edge, edge + w]. Straight borders are painted as fills like Chrome does;
/// a uniform border with [radius] is stroked on the border centre-line.
///
/// [width] / [height] / [minHeight] are border-box sizes (excluding margin).
/// Without [width] the box fills the available width when it is bounded
/// ([fillWidth]) and shrink-wraps otherwise.
class CssBox extends pw.Widget {
  CssBox({
    this.child,
    this.margin = pw.EdgeInsets.zero,
    this.padding = pw.EdgeInsets.zero,
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.radius = 0,
    this.background,
    this.width,
    this.height,
    this.minHeight,
    this.alignment,
    this.fillWidth = true,
  });

  /// Uniform border on all four sides.
  factory CssBox.bordered({
    pw.Widget? child,
    required CssSide side,
    pw.EdgeInsets margin = pw.EdgeInsets.zero,
    pw.EdgeInsets padding = pw.EdgeInsets.zero,
    double radius = 0,
    PdfColor? background,
    double? width,
    double? height,
    double? minHeight,
    pw.Alignment? alignment,
    bool fillWidth = true,
  }) =>
      CssBox(
        child: child,
        margin: margin,
        padding: padding,
        top: side,
        right: side,
        bottom: side,
        left: side,
        radius: radius,
        background: background,
        width: width,
        height: height,
        minHeight: minHeight,
        alignment: alignment,
        fillWidth: fillWidth,
      );

  final pw.Widget? child;
  final pw.EdgeInsets margin;
  final pw.EdgeInsets padding;
  final CssSide? top;
  final CssSide? right;
  final CssSide? bottom;
  final CssSide? left;
  final double radius;
  final PdfColor? background;
  final double? width;
  final double? height;
  final double? minHeight;
  final pw.Alignment? alignment;
  final bool fillWidth;

  double get _bt => top?.width ?? 0;
  double get _br => right?.width ?? 0;
  double get _bb => bottom?.width ?? 0;
  double get _bl => left?.width ?? 0;

  PdfPoint _childOffset = PdfPoint.zero;

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    final insetH = margin.horizontal + _bl + _br + padding.horizontal;
    final insetV = margin.vertical + _bt + _bb + padding.vertical;

    double innerMaxW;
    var tightW = false;
    if (width != null) {
      innerMaxW = math.max(0.0, width! - _bl - _br - padding.horizontal);
      tightW = true;
    } else if (constraints.hasBoundedWidth) {
      innerMaxW = math.max(0.0, constraints.maxWidth - insetH);
      tightW = fillWidth;
    } else {
      innerMaxW = double.infinity;
    }
    final innerMinW = tightW
        ? innerMaxW
        : math.max(0.0, constraints.minWidth - insetH);

    double? innerFixedH;
    if (height != null) {
      innerFixedH = math.max(0.0, height! - _bt - _bb - padding.vertical);
    }
    final innerMinH = innerFixedH ??
        math.max(
          minHeight == null
              ? 0.0
              : math.max(0.0, minHeight! - _bt - _bb - padding.vertical),
          math.max(0.0, constraints.minHeight - insetV),
        );
    final innerMaxH = innerFixedH ??
        (constraints.hasBoundedHeight
            ? math.max(innerMinH, constraints.maxHeight - insetV)
            : double.infinity);

    var cw = 0.0;
    var ch = 0.0;
    if (child != null) {
      child!.layout(
        context,
        pw.BoxConstraints(
          minWidth: math.min(innerMinW, innerMaxW),
          maxWidth: innerMaxW,
          minHeight: 0,
          maxHeight: innerMaxH,
        ),
        parentUsesSize: true,
      );
      cw = child!.box!.width;
      ch = child!.box!.height;
    }

    final innerW = tightW ? innerMaxW : math.max(cw, innerMinW);
    final innerH = innerFixedH ?? math.max(ch, innerMinH);

    box = constraints.constrainRect(
        width: innerW + insetH, height: innerH + insetV);

    if (child != null) {
      if (alignment != null) {
        final r = alignment!.inscribe(
            PdfPoint(cw, ch), PdfRect(0, 0, innerW, innerH));
        _childOffset = PdfPoint(r.x, r.y);
      } else {
        // Top-left aligned: the child's top edge is at the content top.
        _childOffset = PdfPoint(0, innerH - ch);
      }
    }
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final canvas = context.canvas;
    final x0 = box!.x + margin.left;
    final y0 = box!.y + margin.bottom;
    final w = box!.width - margin.horizontal;
    final h = box!.height - margin.vertical;
    // Backgrounds and borders paint on the pixel-snapped box.
    final sr = PxSnap.of(context).rect(x0, y0, w, h);

    final uniform = top != null &&
        top!.width > 0 &&
        top!.width == _br &&
        _br == _bb &&
        _bb == _bl &&
        top!.color == right?.color &&
        right?.color == bottom?.color &&
        bottom?.color == left?.color;

    if (background != null) {
      canvas.setFillColor(background!);
      if (radius > 0) {
        pw.BorderRadius.all(pw.Radius.circular(radius))
            .paint(context, sr);
      } else {
        canvas.drawRect(sr.x, sr.y, sr.width, sr.height);
      }
      canvas.fillPath();
    }

    if (radius > 0 && uniform) {
      final bw = top!.width;
      canvas
        ..saveContext()
        ..setLineJoin(PdfLineJoin.miter)
        ..setStrokeColor(top!.color)
        ..setLineWidth(bw);
      if (top!.dashed) canvas.setLineDashPattern([bw * 3, bw * 3], 0);
      pw.BorderRadius.all(pw.Radius.circular(math.max(0.0, radius - bw / 2)))
          .paint(context,
              PdfRect(sr.x + bw / 2, sr.y + bw / 2, sr.width - bw, sr.height - bw));
      canvas
        ..strokePath()
        ..restoreContext();
    } else {
      void edge(CssSide? s, double x, double y, double ew, double eh,
          {required bool horizontal}) {
        if (s == null || s.width <= 0) return;
        if (s.dashed) {
          final bw = s.width;
          canvas
            ..saveContext()
            ..setStrokeColor(s.color)
            ..setLineWidth(bw)
            ..setLineDashPattern([bw * 3, bw * 3], 0);
          if (horizontal) {
            canvas.drawLine(x, y + eh / 2, x + ew, y + eh / 2);
          } else {
            canvas.drawLine(x + ew / 2, y, x + ew / 2, y + eh);
          }
          canvas
            ..strokePath()
            ..restoreContext();
          return;
        }
        canvas
          ..setFillColor(s.color)
          ..drawRect(x, y, ew, eh)
          ..fillPath();
      }

      edge(top, sr.x, sr.y + sr.height - _bt, sr.width, _bt, horizontal: true);
      edge(bottom, sr.x, sr.y, sr.width, _bb, horizontal: true);
      edge(left, sr.x, sr.y + _bb, _bl, sr.height - _bt - _bb,
          horizontal: false);
      edge(right, sr.x + sr.width - _br, sr.y + _bb, _br,
          sr.height - _bt - _bb,
          horizontal: false);
    }

    if (child != null) {
      final mat = Matrix4.identity()
        ..translate(
          x0 + _bl + padding.left + _childOffset.x,
          y0 + _bb + padding.bottom + _childOffset.y,
        );
      canvas
        ..saveContext()
        ..setTransform(mat);
      child!.paint(context);
      canvas.restoreContext();
    }
  }
}

// ---------------------------------------------------------------------------
// Page-break helpers
// ---------------------------------------------------------------------------

/// Height of the area content can flow in on the page being laid out: the
/// page height minus the margins carried by its [PdfPageFormat]. The report
/// pages are `reportPageFormat` (27.75pt margins, ~787pt usable); a MultiPage
/// built on `PdfPageFormat.a4` would carry 2cm margins and read as 728.5pt.
double _usablePageHeight(pw.Context context) =>
    context.page.pageFormat.availableHeight;

/// Single-child container that avoids page break inside when possible: it
/// moves to the next page when it does not fit and only spans pages once it
/// is taller than a whole page content area (latched, like Chrome's
/// `break-inside: avoid`). Modeled on pdf's Inseparable widget.
class AvoidBreakInside extends pw.SingleChildWidget {
  AvoidBreakInside({required pw.Widget child}) : super(child: child);

  bool _tooTall = false;

  @override
  bool get canSpan => _tooTall && super.canSpan;

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    super.layout(context, constraints, parentUsesSize: parentUsesSize);
    if (box != null && box!.height > _usablePageHeight(context)) {
      _tooTall = true;
    }
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    paintChild(context);
  }
}

/// Keep together helper: avoids breaking across pages if the content fits on one page.
pw.Widget keepTogether(List<pw.Widget> children) => AvoidBreakInside(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: children,
      ),
    );

// ---------------------------------------------------------------------------
// P6: card and section heading
// ---------------------------------------------------------------------------

/// Card container per theme `.card`: 0.75pt #d1d5db border, 3pt radius,
/// padding 7.8 x 10.2pt, margin-bottom 9pt (border-box).
pw.Widget reportCard(
  List<pw.Widget> children, {
  pw.EdgeInsets? padding,
  pw.EdgeInsets? margin,
  PdfColor? background,
}) {
  return AvoidBreakInside(
    child: CssBox.bordered(
      margin: margin ?? const pw.EdgeInsets.only(bottom: 9.0),
      padding: padding ??
          const pw.EdgeInsets.symmetric(vertical: 7.8, horizontal: 10.2),
      side: const CssSide(0.75, ReportPdfTheme.border),
      radius: 3.0,
      background: background,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: children,
      ),
    ),
  );
}

/// Section heading per `.sectionHeading`: 10.2pt bold UPPERCASE #1f4e79,
/// 0.75pt #e8eef5 bottom rule, padding-bottom 3pt, margin-bottom 4.8pt, with
/// the inherited line-height.
pw.Widget sectionHeading(String text,
        {double? lineHeight, PdfColor color = ReportPdfTheme.accent}) =>
    CssBox(
      margin: const pw.EdgeInsets.only(bottom: 4.8),
      padding: const pw.EdgeInsets.only(bottom: 3.0),
      bottom: const CssSide(0.75, ReportPdfTheme.accentTint),
      child: cssText(
        text,
        sizePt: 10.2,
        weight: 700,
        upper: true,
        lineHeight: lineHeight,
        color: color,
      ),
    );

pw.Widget subHeading(String text, {double? lineHeight}) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
      child: cssText(
        text,
        sizePx: 12.0,
        weight: 700,
        lineHeight: lineHeight,
        color: ReportPdfTheme.ink,
      ),
    );

// ---------------------------------------------------------------------------
// P4: status badge
// ---------------------------------------------------------------------------

/// Status badge per `.badge`: 9pt bold, line-height 1.3, padding 1.2 x 5.4pt,
/// 0.75pt border, radius 2.25pt, inline-block (shrink-wrapped).
pw.Widget statusBadge(String tone, String label) {
  final (fg, bg, border) = switch (tone) {
    'ok' => (ReportPdfTheme.okFg, ReportPdfTheme.okBg, ReportPdfTheme.okBorder),
    'bad' =>
      (ReportPdfTheme.badFg, ReportPdfTheme.badBg, ReportPdfTheme.badBorder),
    'warn' => (
        ReportPdfTheme.warnFg,
        ReportPdfTheme.warnBg,
        ReportPdfTheme.warnBorder
      ),
    _ => (
        ReportPdfTheme.neutralFg,
        ReportPdfTheme.neutralBg,
        ReportPdfTheme.neutralBorder
      ),
  };

  return CssBox.bordered(
    fillWidth: false,
    padding: const pw.EdgeInsets.symmetric(
        vertical: ReportPdfTheme.badgePadV,
        horizontal: ReportPdfTheme.badgePadH),
    side: CssSide(0.75, border),
    radius: ReportPdfTheme.badgeRadius,
    background: bg,
    child: cssText(
      label,
      sizePt: ReportPdfTheme.badgeFontPt,
      weight: 700,
      color: fg,
      lineHeight: ReportPdfTheme.badgeLineHeight,
      softWrap: false,
    ),
  );
}

// ---------------------------------------------------------------------------
// P8 / P9: thumbnails and photo grids
// ---------------------------------------------------------------------------

/// Thumb box width / height in pt (110 x 85 css px), including the border.
const double thumbBoxW = 82.5;
const double thumbBoxH = 63.75;

/// Truncates photo caption to the tile content width (102px = 76.5pt),
/// matching Bootstrap `.text-truncate`: the longest prefix that fits with the
/// ellipsis (a trailing space before it stays, as in Chrome), measured with
/// the Segoe-compatible advances and pair kerning of [measureText].
String truncateCaption(String text,
    {double maxWidthPt = 76.5, double fontSizePt = 10.5}) {
  final safe = pdfSafe(text).trim();
  if (safe.isEmpty) return safe;
  if (measureText(safe, fontSizePt) <= maxWidthPt) return safe;
  const ellipsis = '…';
  for (var i = safe.length - 1; i >= 1; i--) {
    final candidate = '${safe.substring(0, i)}$ellipsis';
    if (measureText(candidate, fontSizePt) <= maxWidthPt) return candidate;
  }
  return ellipsis;
}

/// Thumbnail per `.thumb`: 82.5 x 63.75pt including the 0.75pt border
/// (content 78 x 59.25), radius 2.25pt. The image is contain-fitted into
/// 79.5 x 60.75pt (max 106 x 81 css px), never upscaled, and centred.
pw.Widget thumb(Uint8List? bytes, {String? caption}) {
  const imgW = 79.5;
  const imgH = 60.75;

  pw.Widget inner;
  if (bytes != null && bytes.isNotEmpty) {
    try {
      final image = pw.MemoryImage(bytes);
      final nw = (image.width ?? 1).toDouble() * 0.75;
      final nh = (image.height ?? 1).toDouble() * 0.75;
      final scale = math.min(1.0, math.min(imgW / nw, imgH / nh));
      inner = _SnapRect(
          child: pw.Image(image,
              width: nw * scale, height: nh * scale, fit: pw.BoxFit.fill));
    } catch (_) {
      inner = _unavailable(imgW, imgH);
    }
  } else {
    inner = _unavailable(imgW, imgH);
  }

  final container = CssBox.bordered(
    fillWidth: false,
    width: thumbBoxW,
    height: thumbBoxH,
    // 1.5pt (2px) padding; the image may overflow the 78 x 59.25 content box
    // by 0.75pt, so the layout box here is the 79.5 x 60.75 image area.
    padding: const pw.EdgeInsets.all(0.75),
    side: const CssSide(0.75, ReportPdfTheme.border),
    radius: 2.25,
    background: PdfColors.white,
    alignment: pw.Alignment.center,
    child: inner,
  );

  if (caption != null && caption.isNotEmpty) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [container, captionBox(caption)],
    );
  }

  return container;
}

/// Photo caption under a thumb: 10.5pt #4b5563, padding 3pt, line-height
/// 1.5, truncated with an ellipsis at 76.5pt.
pw.Widget captionBox(String caption, {double lineHeight = 1.5}) => pw.SizedBox(
      width: thumbBoxW,
      child: pw.Padding(
        padding: const pw.EdgeInsets.all(3.0),
        child: cssText(
          truncateCaption(caption),
          sizePt: 10.5,
          color: ReportPdfTheme.muted,
          lineHeight: lineHeight,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );

pw.Widget _unavailable(double w, double h) => pw.Container(
      width: w,
      height: h,
      alignment: pw.Alignment.center,
      color: ReportPdfTheme.surface,
      child: cssText('No photo',
          sizePx: 9.0,
          italic: true,
          color: ReportPdfTheme.faint,
          lineHeight: 1.2),
    );

/// A photo to lay out: image bytes (null = placeholder) and optional caption.
class PhotoTile {
  const PhotoTile(this.bytes, {this.caption});
  final Uint8List? bytes;
  final String? caption;
}

/// Lays [tiles] out in wrapped lines inside [width] (tile 82.5pt, [gap] 6pt
/// both ways, like a CSS flex-wrap) and returns, per line, a thumbnail row
/// followed by a caption row (when any tile of the line has a caption) as
/// separate widgets. Spread them into a `MultiPage` child list so a page
/// break may fall between a thumbnail and its caption, as in Chrome.
List<pw.Widget> photoGridLines(
  List<PhotoTile> tiles,
  double width, {
  double gap = 6.0,
  required double lineHeight,
}) {
  if (tiles.isEmpty) return const [];
  final perLine = math.max(1, ((width + gap) / (thumbBoxW + gap)).floor());
  final out = <pw.Widget>[];
  for (var start = 0; start < tiles.length; start += perLine) {
    final line = tiles.sublist(start, math.min(tiles.length, start + perLine));
    final hasCaption = line.any((t) => (t.caption ?? '').isNotEmpty);
    out.add(pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < line.length; i++) ...[
          if (i > 0) pw.SizedBox(width: gap),
          thumb(line[i].bytes),
        ],
      ],
    ));
    if (hasCaption) {
      out.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < line.length; i++) ...[
            if (i > 0) pw.SizedBox(width: gap),
            pw.SizedBox(
              width: thumbBoxW,
              child: (line[i].caption ?? '').isEmpty
                  ? null
                  : captionBox(line[i].caption!, lineHeight: lineHeight),
            ),
          ],
        ],
      ));
    }
    if (start + perLine < tiles.length) out.add(pw.SizedBox(height: gap));
  }
  return out;
}

/// Convenience: the [photoGridLines] in one (unbreakable) column.
pw.Widget photoGrid(
  List<PhotoTile> tiles,
  double width, {
  double gap = 6.0,
  required double lineHeight,
}) =>
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children:
          photoGridLines(tiles, width, gap: gap, lineHeight: lineHeight),
    );

/// Wrapped row of photos using [thumb].
pw.Widget photoRow(
  List<ReportPhoto> list,
  Map<String, Uint8List?> photos,
  String emptyLabel, {
  double width = 82.5,
  double height = 63.75,
  bool captions = false,
  double? lineHeight,
}) {
  if (list.isEmpty) {
    return cssText(emptyLabel,
        sizePx: 11.5,
        italic: true,
        lineHeight: lineHeight,
        color: ReportPdfTheme.faint);
  }
  return pw.Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final p in list)
        thumb(
          photos[p.key],
          caption: captions ? (p.caption.isNotEmpty ? p.caption : null) : null,
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// P5: report header
// ---------------------------------------------------------------------------

/// Report Header per `.header` and the per-kind overrides: padding-bottom 9,
/// 1.5pt #1f4e79 rule, margin-bottom 12; h2 15pt bold uppercase
/// letter-spacing 0.45 (lh 1.2, mb 2.4); two h3 12pt semibold #4b5563 (lh
/// 1.2, mb 1.8); meta row 10.2pt in two columns (gap 9, margin 6 collapsed
/// with its neighbours); title 13.2pt bold uppercase letter-spacing 0.66
/// #1f4e79 (lh 1.2, mb 3); subtitle 10.8pt semibold.
///
/// [lineHeight] is the report's inherited line-height (meta row, subtitle).
/// [forceBlack] renders railway, division, depot and title in black
/// (Checklist); otherwise the railway h2 is [ReportPdfTheme.headingInk] (the
/// web print's `#1e293b`) unless [railwayColor] says otherwise.
pw.Widget reportHeader({
  required ReportOrganization org,
  required String title,
  String? subtitle,
  List<(String, String)> metaLeft = const [],
  List<(String, String)> metaRight = const [],
  double? lineHeight,
  bool forceBlack = false,
  PdfColor? railwayColor,
}) {
  final root = lineHeight ?? ReportRoot.lineHeight;
  final h2Color = railwayColor ??
      (forceBlack ? ReportPdfTheme.inkPrint : ReportPdfTheme.headingInk);
  final hasMeta = metaLeft.isNotEmpty || metaRight.isNotEmpty;
  final h3Color = forceBlack ? ReportPdfTheme.inkPrint : ReportPdfTheme.muted;
  final titleColor = forceBlack ? ReportPdfTheme.inkPrint : ReportPdfTheme.accent;

  pw.Widget metaItem((String, String) m, pw.TextAlign align) => cssRich(
        [
          CssSpan('${m.$1}: ', weight: 700),
          CssSpan(m.$2),
        ],
        sizePt: 10.2,
        lineHeight: root,
        align: align,
      );

  pw.Widget metaColumn(List<(String, String)> items, pw.TextAlign align) =>
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [for (final m in items) metaItem(m, align)],
        ),
      );

  return CssBox(
    padding: const pw.EdgeInsets.only(bottom: 9.0),
    margin: const pw.EdgeInsets.only(bottom: 12.0),
    bottom: const CssSide(1.5, ReportPdfTheme.accent),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        cssText(
          org.railwayName,
          sizePt: 15.0,
          weight: 700,
          upper: true,
          lineHeight: 1.2,
          letterSpacingEm: 0.03,
          color: h2Color,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2.4),
        cssText(
          org.divisionName,
          sizePt: 12.0,
          weight: 600,
          lineHeight: 1.2,
          color: h3Color,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 1.8),
        cssText(
          org.depotName,
          sizePt: 12.0,
          weight: 600,
          lineHeight: 1.2,
          color: h3Color,
          align: pw.TextAlign.center,
        ),
        // depot mb 1.8 collapses with the meta row's margin 6 (and the title
        // has no top margin), so the gap is max(1.8, 6) = 6 with a meta row.
        pw.SizedBox(height: hasMeta ? 6.0 : 1.8),
        if (hasMeta) ...[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              metaColumn(metaLeft, pw.TextAlign.left),
              pw.SizedBox(width: 9.0),
              metaColumn(metaRight, pw.TextAlign.right),
            ],
          ),
          pw.SizedBox(height: 6.0),
        ],
        cssText(
          title,
          sizePt: 13.2,
          weight: 700,
          upper: true,
          lineHeight: 1.2,
          color: titleColor,
          letterSpacingEm: 0.05,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 3.0),
        if (subtitle != null && subtitle.isNotEmpty)
          cssText(
            subtitle,
            sizePt: 10.8,
            weight: 600,
            lineHeight: root,
            align: pw.TextAlign.center,
          ),
      ],
    ),
  );
}

pw.Widget letterhead(
  ReportOrganization org,
  String title, {
  List<(String, String)> meta = const [],
  String? subtitle,
  double? lineHeight,
  bool forceBlack = false,
  PdfColor? railwayColor,
}) {
  final List<(String, String)> left;
  final List<(String, String)> right;
  if (meta.length == 2) {
    left = [meta[0]];
    right = [meta[1]];
  } else {
    left = meta.take(2).toList();
    right = meta.skip(2).toList();
  }
  return reportHeader(
    org: org,
    title: title,
    subtitle: subtitle,
    metaLeft: left,
    metaRight: right,
    lineHeight: lineHeight,
    forceBlack: forceBlack,
    railwayColor: railwayColor,
  );
}

// ---------------------------------------------------------------------------
// P10: sign-off
// ---------------------------------------------------------------------------

/// Sign-off per `.signoffCard` and ReportSignOff: a card with margin-top 9pt
/// that collapses with the previous sibling's margin-bottom
/// ([collapseWith], 9pt for a card), a SIGN-OFF heading, a row of equal
/// columns (gap 12, 9.6pt; semibold muted "Label:" + 1.8pt + value), an
/// optional remarks row (pre-line), and a 9pt muted meta row.
///
/// [forceBlack] prints the heading, the labels and the meta row in black (the
/// Checklist's print rule overrides the muted and accent colours).
pw.Widget signOff({
  String? technician,
  String? maintenanceStaff,
  ReportVerification? verification,
  ReportSubmission? submission,
  required DateTime generatedAt,
  double? lineHeight,
  double collapseWith = 9.0,
  bool forceBlack = false,
}) {
  final root = lineHeight ?? ReportRoot.lineHeight;
  final muted = forceBlack ? ReportPdfTheme.inkPrint : ReportPdfTheme.muted;
  String tech = (technician ?? '').trim();
  if (tech.isEmpty) tech = '—';

  pw.Widget item(String label, String value) => cssRich(
        [
          // `.signoffLabel`: margin-right 0.15rem (1.8pt) + the JSX space.
          CssSpan('$label:', weight: 600, color: muted, trailingGapPt: 1.8),
          CssSpan(' $value'),
        ],
        sizePt: 9.6,
        lineHeight: root,
      );

  final supervisor = verification == null
      ? 'Pending verification'
      : verification.verifiedAtLabel.isNotEmpty
          ? '${verification.verifiedByName} · ${verification.verifiedAtLabel}'
          : verification.verifiedByName;
  final staff = (maintenanceStaff ?? '').trim();

  final items = <pw.Widget>[
    item('Technician', tech),
    if (staff.isNotEmpty) item('Maintenance Staff', staff),
    item('Supervisor', supervisor),
  ];

  final topGap = math.max(0.0, 9.0 - collapseWith);

  return reportCard(
    margin: pw.EdgeInsets.only(top: topGap, bottom: 9.0),
    [
      sectionHeading('SIGN-OFF',
          lineHeight: root,
          color: forceBlack ? ReportPdfTheme.inkPrint : ReportPdfTheme.accent),
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4.8),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) pw.SizedBox(width: 12),
              pw.Expanded(child: items[i]),
            ],
          ],
        ),
      ),
      if (verification != null && verification.remarks.trim().isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4.8),
          child: item('Supervisor Remarks', verification.remarks.trim()),
        ),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          if (submission != null)
            cssText(
              submission.timestampLabel.isNotEmpty
                  ? 'Submission #${submission.number} · ${submission.timestampLabel}'
                  : 'Submission #${submission.number}',
              sizePt: 9.0,
              color: muted,
              lineHeight: root,
            )
          else
            pw.SizedBox(),
          cssText(
            'Generated: ${formatGeneratedAt(generatedAt)}',
            sizePt: 9.0,
            color: muted,
            lineHeight: root,
          ),
        ],
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// P7: tables
// ---------------------------------------------------------------------------

/// Per-cell style override for [cssTable].
class CssCellStyle {
  const CssCellStyle({this.weight, this.color, this.align, this.italic = false});
  final int? weight;
  final PdfColor? color;
  final pw.TextAlign? align;
  final bool italic;
}

/// Auto-layout (CSS `table-layout: auto`, width 100%) column widths for a
/// table of total width [total] whose columns have max-content widths
/// [maxs] and min-content widths [mins] (both including padding + border).
/// If the sum of the max widths fits, every column gets
/// `max_i * total / sum(max)`; otherwise columns grow from their min width in
/// proportion to `max - min`.
List<double> autoColumnWidths(
    List<double> mins, List<double> maxs, double total) {
  final n = maxs.length;
  final sumMax = maxs.fold(0.0, (a, b) => a + b);
  final sumMin = mins.fold(0.0, (a, b) => a + b);
  if (sumMax <= 0) return List.filled(n, total / math.max(1, n));
  if (sumMax <= total) {
    return [for (final m in maxs) m * total / sumMax];
  }
  if (sumMin >= total) return List<double>.from(mins);
  final f = (total - sumMin) / (sumMax - sumMin);
  return [for (var i = 0; i < n; i++) mins[i] + (maxs[i] - mins[i]) * f];
}

/// Number of lines [text] wraps to in [widthPt] of text area (CSS
/// `white-space: normal`, greedy at spaces; a newline also breaks), measured
/// with the Segoe-compatible advances of [measureText].
int cssWrapLineCount(String text, double widthPt, double sizePt,
    {int weight = 400, bool italic = false}) {
  double w(String t) => measureText(t, sizePt, weight: weight, italic: italic);
  final space = w(' ');
  var n = 0;
  for (final line in pdfSafe(text).split('\n')) {
    var cur = 0.0;
    var lines = 1;
    for (final word in line.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final ww = w(word);
      if (cur == 0) {
        cur = ww;
      } else if (cur + space + ww <= widthPt) {
        cur += space + ww;
      } else {
        lines++;
        cur = ww;
      }
    }
    n += lines;
  }
  return math.max(1, n);
}

/// Height in css px of a table row of [lines] text lines as Chrome lays it
/// out: line-height (LayoutUnit-quantised) per line, 2 x padding (also
/// quantised to 1/64 px) and one collapsed 1px border. A 9.75pt / 1.5 body row
/// of one line is 19.5 + 12.1875 = 31.6875px.
double cssRowPx(int lines,
    {required double lineHeight, double sizePt = 9.75, double padVPt = 4.2}) {
  double q(double v) => (v * 64).floorToDouble() / 64;
  final lh = q(lineHeight * sizePt / _pxToPt);
  return lines * lh + 2 * q(padVPt / _pxToPt) + 1;
}

/// Chrome paints table row edges on whole px: the cumulative row edges of
/// rows [px] tall (css px, from the table top) are snapped, so equal rows
/// alternate 24 / 23.25pt. Returns the snapped row heights in pt.
List<double> cssSnapRowsPt(List<double> px) {
  final out = <double>[];
  var sum = 0.0;
  var prev = 0.0;
  for (final h in px) {
    sum += h;
    final edge = (sum - 0.01).roundToDouble();
    out.add((edge - prev) * _pxToPt);
    prev = edge;
  }
  return out;
}

/// One row of a [cssTable]: [cells] (already laid out text blocks) between the
/// vertical grid lines [xs] (centres of 0.75pt collapsed borders, `xs.first`
/// is 0), the row being at least [minPitch] tall measured between the centres
/// of its top and bottom grid lines. Borders are painted the way Chrome does:
/// every grid line exactly once, as a filled 0.75pt rect (horizontal lines
/// span the full table width including the outer half borders, vertical ones
/// run between the horizontals), so nothing is stroked twice and no
/// anti-aliased overlap darkens a joint. The th fill is a per-cell rect inset
/// inside the borders and cells are vertically centred.
///
/// The widget is [xs].last + 0.75 wide (the outer half borders) and, for the
/// first / last row, 0.375 taller at the top / bottom.
class _CssTableRow extends pw.Widget {
  _CssTableRow({
    required this.xs,
    required this.cells,
    required this.minPitch,
    required this.first,
    required this.last,
    required this.borderColor,
    this.fill,
  });

  final List<double> xs;
  final List<pw.Widget> cells;
  final double minPitch;
  final bool first;
  final bool last;
  final PdfColor borderColor;
  final PdfColor? fill;

  /// Cell padding (0.5rem x 0.35rem) and half a collapsed border.
  static const double padH = 6.0;
  static const double padV = 4.2;
  static const double _half = 0.375;
  double _pitch = 0;
  final List<double> _childH = [];

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    var contentH = 0.0;
    _childH.clear();
    for (var j = 0; j < cells.length; j++) {
      final w = math.max(0.0, xs[j + 1] - xs[j] - 2 * _half - 2 * padH);
      cells[j].layout(
        context,
        pw.BoxConstraints(minWidth: w, maxWidth: w),
        parentUsesSize: true,
      );
      _childH.add(cells[j].box!.height);
      contentH = math.max(contentH, cells[j].box!.height);
    }
    _pitch = math.max(minPitch, contentH + 2 * padV + 2 * _half);
    box = PdfRect(
      0,
      0,
      xs.last + 2 * _half,
      _pitch + (first ? _half : 0) + (last ? _half : 0),
    );
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final canvas = context.canvas;
    final b = box!;
    // Local origin: the left grid line centre sits at b.x + _half; the
    // bottom grid line centre at b.y + (last ? _half : 0).
    final ox = b.x + _half;
    final yBottom = b.y + (last ? _half : 0);
    final yTop = yBottom + _pitch;

    final snap = PxSnap.of(context);
    void fillRect(double x, double y, double w, double h) {
      final r = snap.rect(x, y, w, h);
      canvas.drawRect(r.x, r.y, r.width, r.height);
    }

    if (fill != null) {
      canvas.setFillColor(fill!);
      for (var j = 0; j < cells.length; j++) {
        fillRect(ox + xs[j] + _half, yBottom + _half, xs[j + 1] - xs[j] - 2 * _half,
            _pitch - 2 * _half);
      }
      canvas.fillPath();
    }

    canvas.setFillColor(borderColor);
    // Horizontal grid lines: bottom always, top for the first row only.
    fillRect(b.x, yBottom - _half, b.width, 2 * _half);
    if (first) fillRect(b.x, yTop - _half, b.width, 2 * _half);
    // Vertical grid lines between the horizontals.
    for (final x in xs) {
      fillRect(ox + x - _half, yBottom + _half, 2 * _half, _pitch - 2 * _half);
    }
    canvas.fillPath();

    for (var j = 0; j < cells.length; j++) {
      final contentH = _pitch - 2 * _half - 2 * padV;
      final dy = (contentH - _childH[j]) / 2;
      final mat = Matrix4.identity()
        ..translate(
          ox + xs[j] + _half + padH,
          yTop - _half - padV - dy - _childH[j],
        );
      canvas
        ..saveContext()
        ..setTransform(mat);
      cells[j].paint(context);
      canvas.restoreContext();
    }
  }
}

/// The rows of a CSS data table `.table` (9.75pt, cell padding 4.2 x 6pt,
/// collapsed 0.75pt `#4b5563` borders, th bold on `#e8eef5`, text vertically
/// centred) laid out in a table [width] wide, as separate widgets so a
/// `MultiPage` can break between any two rows.
///
/// Column widths follow CSS auto layout unless [percentWidths] (fractions of
/// the table width) is given; the first and last column also carry the outer
/// half border (0.375pt) in their min / max content width. A row with a
/// single cell in a table of more columns is a full-width (colspan) row. With
/// [snapRows] (default) row heights follow Chrome's whole-px row edges (see
/// [cssSnapRowsPt]).
List<pw.Widget> cssTableRows(
  List<String> headers,
  List<List<String>> rows, {
  required double width,
  required double lineHeight,
  List<double>? percentWidths,
  double sizePt = 9.75,
  int bodyWeight = 400,
  PdfColor bodyColor = ReportPdfTheme.inkPrint,
  CssCellStyle? Function(int row, int col)? cellStyles,
  PdfColor borderColor = ReportPdfTheme.borderPrint,
  bool snapRows = true,
}) {
  final n = headers.length;
  const padH = _CssTableRow.padH;
  const half = 0.375;
  bool isSpan(int r) => rows[r].length == 1 && n > 1;

  // Column widths.
  final List<double> colW;
  if (percentWidths != null) {
    colW = [for (final f in percentWidths) f * width];
  } else {
    final mins = List<double>.filled(n, 0);
    final maxs = List<double>.filled(n, 0);
    void measure(String text, int col, int weight) {
      final safe = pdfSafe(text);
      maxs[col] =
          math.max(maxs[col], measureText(safe, sizePt, weight: weight));
      for (final word in safe.split(RegExp(r'\s+'))) {
        mins[col] =
            math.max(mins[col], measureText(word, sizePt, weight: weight));
      }
    }

    for (var c = 0; c < n; c++) {
      measure(headers[c], c, 700);
    }
    for (var r = 0; r < rows.length; r++) {
      if (isSpan(r)) continue;
      for (var c = 0; c < n && c < rows[r].length; c++) {
        measure(rows[r][c], c, cellStyles?.call(r, c)?.weight ?? bodyWeight);
      }
    }
    for (var c = 0; c < n; c++) {
      final extra = 2 * padH + 0.75 + (c == 0 || c == n - 1 ? half : 0);
      mins[c] += extra;
      maxs[c] += extra;
    }
    colW = autoColumnWidths(mins, maxs, width);
  }
  // Grid line centres: the outer lines sit half a border inside the box.
  final xs = <double>[0];
  for (var c = 0; c < n; c++) {
    final pitch = colW[c] - (c == 0 || c == n - 1 ? half : 0);
    xs.add(xs.last + pitch);
  }

  // Row heights: lines per cell from the wrap model, snapped like Chrome.
  int linesOf(List<String> texts, List<int> weights, List<double> cellW) {
    var lines = 1;
    for (var c = 0; c < texts.length; c++) {
      lines = math.max(
          lines,
          cssWrapLineCount(texts[c], cellW[c], sizePt, weight: weights[c]));
    }
    return lines;
  }

  final textW = [
    for (var c = 0; c < n; c++) xs[c + 1] - xs[c] - 2 * half - 2 * padH,
  ];
  final spanW = [xs.last - 2 * half - 2 * padH];
  final linesPerRow = <int>[
    linesOf(headers, List.filled(n, 700), textW),
    for (var r = 0; r < rows.length; r++)
      isSpan(r)
          ? linesOf([rows[r][0]], [cellStyles?.call(r, 0)?.weight ?? bodyWeight],
              spanW)
          : linesOf(
              [for (var c = 0; c < n; c++) c < rows[r].length ? rows[r][c] : ''],
              [for (var c = 0; c < n; c++) cellStyles?.call(r, c)?.weight ?? bodyWeight],
              textW),
  ];
  final minPitch = snapRows
      ? cssSnapRowsPt([
          for (final l in linesPerRow)
            cssRowPx(l, lineHeight: lineHeight, sizePt: sizePt),
        ])
      : List<double>.filled(linesPerRow.length, 0);

  pw.Widget cell(String text, int weight, PdfColor color,
          {pw.TextAlign? align, bool italic = false}) =>
      cssText(text,
          sizePt: sizePt,
          weight: weight,
          color: color,
          lineHeight: lineHeight,
          align: align,
          italic: italic);

  final total = rows.length + 1;
  final out = <pw.Widget>[
    _CssTableRow(
      xs: xs,
      cells: [for (final h in headers) cell(h, 700, ReportPdfTheme.inkPrint)],
      minPitch: minPitch[0],
      first: true,
      last: rows.isEmpty,
      borderColor: borderColor,
      fill: ReportPdfTheme.accentTint,
    ),
  ];
  for (var r = 0; r < rows.length; r++) {
    final s0 = cellStyles?.call(r, 0);
    out.add(_CssTableRow(
      xs: isSpan(r) ? [0, xs.last] : xs,
      cells: isSpan(r)
          ? [
              cell(rows[r][0], s0?.weight ?? bodyWeight, s0?.color ?? bodyColor,
                  align: s0?.align ?? pw.TextAlign.center,
                  italic: s0?.italic ?? false),
            ]
          : [
              for (var c = 0; c < n; c++)
                () {
                  final s = cellStyles?.call(r, c);
                  return cell(c < rows[r].length ? rows[r][c] : '',
                      s?.weight ?? bodyWeight, s?.color ?? bodyColor,
                      align: s?.align, italic: s?.italic ?? false);
                }(),
            ],
      minPitch: minPitch[r + 1],
      first: false,
      last: r + 1 == total - 1,
      borderColor: borderColor,
    ));
  }
  return out;
}

/// A report data table (see [cssTableRows]) filling the available width, as
/// one column of rows. The header row is not repeated across pages.
pw.Widget cssTable(
  List<String> headers,
  List<List<String>> rows, {
  required double lineHeight,
  List<double>? percentWidths,
  double sizePt = 9.75,
  int bodyWeight = 400,
  PdfColor bodyColor = ReportPdfTheme.inkPrint,
  CssCellStyle? Function(int row, int col)? cellStyles,
  PdfColor borderColor = ReportPdfTheme.borderPrint,
  bool snapRows = true,
}) =>
    pw.LayoutBuilder(
      builder: (context, constraints) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: cssTableRows(
          headers,
          rows,
          width: constraints != null && constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 540.0,
          lineHeight: lineHeight,
          percentWidths: percentWidths,
          sizePt: sizePt,
          bodyWeight: bodyWeight,
          bodyColor: bodyColor,
          cellStyles: cellStyles,
          borderColor: borderColor,
          snapRows: snapRows,
        ),
      ),
    );

pw.Widget paramTable(List<ReportParameter> params, {double? lineHeight}) =>
    cssTable(
      const ['Parameter', 'Value', 'Unit'],
      [
        for (final p in params)
          [p.parameter, p.value, p.unit.isEmpty ? '-' : p.unit],
      ],
      lineHeight: lineHeight ?? ReportRoot.lineHeight,
    );

/// Bordered text block (`border-box`, 0.75pt #d1d5db, radius 4.5pt) with an
/// italic muted placeholder when [text] is empty.
pw.Widget textBox(String text,
    {String empty = 'None recorded', double? lineHeight}) {
  final has = text.trim().isNotEmpty;
  return CssBox.bordered(
    padding: const pw.EdgeInsets.all(6.0),
    side: const CssSide(0.75, ReportPdfTheme.border),
    radius: 4.5,
    child: cssText(
      has ? text : empty,
      sizePt: 12.0,
      italic: !has,
      lineHeight: lineHeight,
      color: has ? ReportPdfTheme.inkPrint : ReportPdfTheme.faint,
    ),
  );
}
