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

/// Distance from the top of a CSS line box (line-height [lineHeight]) to its
/// baseline for Segoe UI (content area 1.3301 em, ascent 1.079 em), in em.
double cssBaselineEm(double lineHeight) => lineHeight / 2 + 0.41405;

/// `TextStyle.lineSpacing` that turns pdf's 1.2002 em natural line pitch into
/// a CSS pitch of [lineHeight] * [sizePt].
double cssLineSpacing(double lineHeight, double sizePt) =>
    (lineHeight - _selawikLineHeight) * sizePt;

/// Space above the first line so its baseline matches CSS (0.98975 em is the
/// pdf baseline offset).
double cssInsetTop(double lineHeight, double sizePt) =>
    (lineHeight / 2 - 0.5757) * sizePt;

/// Space below the last line so a block of n lines is exactly
/// n * lineHeight * size tall. Negative for line-height 1.2 (-0.0245 em); the
/// negative padding is honoured by [pw.Padding] (box shrinks, child paints
/// below its box by the same amount).
double cssInsetBottom(double lineHeight, double sizePt) =>
    (lineHeight / 2 - 0.6245) * sizePt;

/// One run of a [cssRich] paragraph. Unset fields inherit from the paragraph.
class CssSpan {
  const CssSpan(
    this.text, {
    this.weight,
    this.color,
    this.sizePx,
    this.sizePt,
    this.trailingGapPt = 0,
  });

  final String text;
  final int? weight;
  final PdfColor? color;
  final double? sizePx;
  final double? sizePt;

  /// CSS `margin-right` on an inline label: extra space after the last glyph.
  final double trailingGapPt;
}

/// A paragraph of mixed-weight runs with CSS line-height semantics: every
/// line box is [lineHeight] * size tall and the first baseline sits exactly
/// where Chrome puts it. Replaces `pw.RichText`.
pw.Widget cssRich(
  List<CssSpan> spans, {
  double sizePx = 13.0,
  double? sizePt,
  int weight = 400,
  PdfColor color = ReportPdfTheme.inkPrint,
  required double lineHeight,
  bool upper = false,
  double? letterSpacingEm,
  bool italic = false,
  pw.TextAlign? align,
  int? maxLines,
  bool softWrap = true,
}) {
  final basePt = sizePt ?? ReportPdfTheme.px(sizePx);
  final lineSpacing = cssLineSpacing(lineHeight, basePt);
  final lsPt = letterSpacingEm != null ? letterSpacingEm * basePt : null;

  pw.TextSpan make(String text, CssSpan s, {double? extraLs}) {
    final pt = s.sizePt ??
        (s.sizePx != null ? ReportPdfTheme.px(s.sizePx!) : basePt);
    final safe = pdfSafe(text);
    return pw.TextSpan(
      text: upper ? safe.toUpperCase() : safe,
      style: pw.TextStyle(
        font: ReportFonts.fontForWeight(s.weight ?? weight),
        fontSize: pt,
        color: s.color ?? color,
        letterSpacing: extraLs ?? lsPt,
        lineSpacing: lineSpacing,
      ),
    );
  }

  final children = <pw.TextSpan>[];
  for (final s in spans) {
    if (s.text.isEmpty) continue;
    if (s.trailingGapPt > 0 && s.text.length > 1) {
      children.add(make(s.text.substring(0, s.text.length - 1), s));
      children.add(make(s.text.substring(s.text.length - 1), s,
          extraLs: s.trailingGapPt));
    } else {
      children.add(make(s.text, s,
          extraLs: s.trailingGapPt > 0 ? s.trailingGapPt : null));
    }
  }

  pw.Widget widget = pw.RichText(
    text: pw.TextSpan(
      style: pw.TextStyle(font: ReportFonts.regular),
      children: children,
    ),
    textAlign: align,
    maxLines: maxLines,
    softWrap: softWrap,
  );

  if (italic) {
    widget = pw.Transform(transform: Matrix4.skewX(-0.2), child: widget);
  }

  return pw.Padding(
    padding: pw.EdgeInsets.only(
      top: cssInsetTop(lineHeight, basePt),
      bottom: cssInsetBottom(lineHeight, basePt),
    ),
    child: widget,
  );
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
      upper: upper,
      letterSpacingEm: letterSpacingEm,
      italic: italic,
      align: align,
      maxLines: maxLines,
      softWrap: softWrap,
    );

/// Width in pt of [text] (single line) at [sizePt] in the face for [weight].
double measureText(String text, double sizePt,
    {int weight = 400, double letterSpacingPt = 0}) {
  var w = 0.0;
  for (final line in pdfSafe(text).split('\n')) {
    w = math.max(
        w,
        ReportFonts.advance(line, sizePt,
            weight: weight, letterSpacingPt: letterSpacingPt));
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
            .paint(context, PdfRect(x0, y0, w, h));
      } else {
        canvas.drawRect(x0, y0, w, h);
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
          .paint(context, PdfRect(x0 + bw / 2, y0 + bw / 2, w - bw, h - bw));
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

      edge(top, x0, y0 + h - _bt, w, _bt, horizontal: true);
      edge(bottom, x0, y0, w, _bb, horizontal: true);
      edge(left, x0, y0 + _bb, _bl, h - _bt - _bb, horizontal: false);
      edge(right, x0 + w - _br, y0 + _bb, _br, h - _bt - _bb,
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

/// Single-child container that avoids page break inside when possible.
/// Modeled on pdf's Inseparable widget.
class AvoidBreakInside extends pw.SingleChildWidget {
  AvoidBreakInside({required pw.Widget child}) : super(child: child);

  bool _tooTall = false;

  @override
  bool get canSpan => _tooTall && super.canSpan;

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    super.layout(context, constraints, parentUsesSize: parentUsesSize);
    if (box != null) {
      if (box!.height > context.page.pageFormat.availableHeight) {
        _tooTall = true;
      }
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
pw.Widget sectionHeading(String text, {double? lineHeight}) => CssBox(
      margin: const pw.EdgeInsets.only(bottom: 4.8),
      padding: const pw.EdgeInsets.only(bottom: 3.0),
      bottom: const CssSide(0.75, ReportPdfTheme.accentTint),
      child: cssText(
        text,
        sizePt: 10.2,
        weight: 700,
        upper: true,
        lineHeight: lineHeight,
        color: ReportPdfTheme.accent,
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
/// matching Bootstrap `.text-truncate`, using the real Selawik advances.
String truncateCaption(String text,
    {double maxWidthPt = 76.5, double fontSizePt = 10.5}) {
  final safe = pdfSafe(text).trim();
  if (safe.isEmpty) return safe;
  if (measureText(safe, fontSizePt) <= maxWidthPt) return safe;
  const ellipsis = '…';
  for (var i = safe.length - 1; i >= 1; i--) {
    final candidate = '${safe.substring(0, i).trimRight()}$ellipsis';
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
      inner = pw.Image(image,
          width: nw * scale, height: nh * scale, fit: pw.BoxFit.fill);
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
/// [forceBlack] renders division, depot and title in black (Checklist).
pw.Widget reportHeader({
  required ReportOrganization org,
  required String title,
  String? subtitle,
  List<(String, String)> metaLeft = const [],
  List<(String, String)> metaRight = const [],
  double? lineHeight,
  bool forceBlack = false,
}) {
  final root = lineHeight ?? ReportRoot.lineHeight;
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
pw.Widget signOff({
  String? technician,
  String? maintenanceStaff,
  ReportVerification? verification,
  ReportSubmission? submission,
  required DateTime generatedAt,
  double? lineHeight,
  double collapseWith = 9.0,
}) {
  final root = lineHeight ?? ReportRoot.lineHeight;
  String tech = (technician ?? '').trim();
  if (tech.isEmpty) tech = '—';

  pw.Widget item(String label, String value) => cssRich(
        [
          CssSpan('$label:',
              weight: 600, color: ReportPdfTheme.muted, trailingGapPt: 1.8),
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
      sectionHeading('SIGN-OFF', lineHeight: root),
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
              color: ReportPdfTheme.muted,
              lineHeight: root,
            )
          else
            pw.SizedBox(),
          cssText(
            'Generated: ${formatGeneratedAt(generatedAt)}',
            sizePt: 9.0,
            color: ReportPdfTheme.muted,
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

class _TablePlan {
  _TablePlan(this.mins, this.maxs, this.fractions);
  final List<double> mins;
  final List<double> maxs;
  final List<double>? fractions;

  /// Column widths in the pw.Table frame (table box = Chrome's border box
  /// minus 0.375 on each side, because collapsed outer borders are centred
  /// 0.375 inside the border box).
  List<double> widths(double boxWidth) {
    final total = boxWidth + 0.75;
    final w = fractions != null
        ? [for (final f in fractions!) f * total]
        : autoColumnWidths(mins, maxs, total);
    final out = List<double>.from(w);
    out[0] -= 0.375;
    out[out.length - 1] -= 0.375;
    return out;
  }
}

class _PlannedColumn extends pw.TableColumnWidth {
  const _PlannedColumn(this.plan, this.index);
  final _TablePlan plan;
  final int index;

  @override
  pw.ColumnLayout layout(
      pw.Widget child, pw.Context context, pw.BoxConstraints? constraints) {
    final bounded = constraints != null && constraints.hasBoundedWidth;
    final double w;
    if (bounded) {
      w = plan.widths(constraints.maxWidth)[index];
    } else {
      w = plan.maxs[index];
    }
    return pw.ColumnLayout(w, 0);
  }
}

/// A report data table per `.table`: 9.75pt, cell padding 4.2 x 6pt,
/// collapsed 0.75pt #4b5563 borders (each row is content + padding + one
/// border width tall), th bold on #e8eef5, header row repeated on every
/// page. Widths follow CSS auto layout unless [percentWidths] (fractions of
/// the table width) is given. A row with a single cell in a table of more
/// columns is a full-width (colspan) row; such tables are returned as a
/// non-breaking stack of segments.
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
}) {
  final n = headers.length;
  const padH = 6.0;
  const padV = 4.2;
  const hv = padH * 2 + 0.75; // horizontal extra per column
  final useFractions = percentWidths != null;

  final mins = List<double>.filled(n, 0);
  final maxs = List<double>.filled(n, 0);
  void measure(String text, int col, int weight) {
    final safe = pdfSafe(text);
    maxs[col] = math.max(maxs[col], measureText(safe, sizePt, weight: weight));
    for (final word in safe.split(RegExp(r'\s+'))) {
      mins[col] =
          math.max(mins[col], measureText(word, sizePt, weight: weight));
    }
  }

  for (var c = 0; c < n; c++) {
    measure(headers[c], c, 700);
  }
  for (var r = 0; r < rows.length; r++) {
    if (rows[r].length == 1 && n > 1) continue;
    for (var c = 0; c < n && c < rows[r].length; c++) {
      measure(rows[r][c], c, cellStyles?.call(r, c)?.weight ?? bodyWeight);
    }
  }
  for (var c = 0; c < n; c++) {
    mins[c] += hv;
    maxs[c] += hv;
  }

  final plan = _TablePlan(mins, maxs, useFractions ? percentWidths : null);
  final columns = {
    for (var c = 0; c < n; c++) c: _PlannedColumn(plan, c),
  };
  final border = pw.TableBorder.all(color: borderColor, width: 0.75);

  pw.Widget cell(String text, int weight, PdfColor color,
          {pw.TextAlign? align, bool italic = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(
            horizontal: padH + 0.375, vertical: padV + 0.375),
        child: cssText(text,
            sizePt: sizePt,
            weight: weight,
            color: color,
            lineHeight: lineHeight,
            align: align,
            italic: italic),
      );

  final headerRow = pw.TableRow(
    repeat: true,
    decoration: const pw.BoxDecoration(color: ReportPdfTheme.accentTint),
    children: [
      for (final h in headers) cell(h, 700, ReportPdfTheme.inkPrint),
    ],
  );

  pw.TableRow bodyRow(int r) => pw.TableRow(
        children: [
          for (var c = 0; c < n; c++)
            () {
              final s = cellStyles?.call(r, c);
              final text = c < rows[r].length ? rows[r][c] : '';
              return cell(text, s?.weight ?? bodyWeight,
                  s?.color ?? bodyColor,
                  align: s?.align, italic: s?.italic ?? false);
            }(),
        ],
      );

  final hasSpan = [
    for (final r in rows)
      if (r.length == 1 && n > 1) true
  ].isNotEmpty;

  if (!hasSpan) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(0.375),
      child: pw.Table(
        border: border,
        columnWidths: columns,
        children: [headerRow, for (var r = 0; r < rows.length; r++) bodyRow(r)],
      ),
    );
  }

  // Segments: consecutive normal rows share a table; each colspan row is a
  // single-column table of full width.
  final segments = <pw.Widget>[];
  var pending = <pw.TableRow>[headerRow];
  void flush() {
    if (pending.isEmpty) return;
    segments.add(pw.Table(
        border: border, columnWidths: columns, children: pending));
    pending = [];
  }

  for (var r = 0; r < rows.length; r++) {
    if (rows[r].length == 1 && n > 1) {
      flush();
      final s = cellStyles?.call(r, 0);
      segments.add(pw.Table(
        border: border,
        children: [
          pw.TableRow(children: [
            cell(rows[r][0], s?.weight ?? bodyWeight, s?.color ?? bodyColor,
                align: s?.align ?? pw.TextAlign.center,
                italic: s?.italic ?? false),
          ]),
        ],
      ));
    } else {
      pending.add(bodyRow(r));
    }
  }
  flush();
  return pw.Padding(
    padding: const pw.EdgeInsets.all(0.375),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: segments,
    ),
  );
}

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
