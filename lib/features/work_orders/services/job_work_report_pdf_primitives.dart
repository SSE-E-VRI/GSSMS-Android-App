import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/report_date_format.dart';
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

/// Natural line-height of Selawik measured via fontTools:
/// unitsPerEm=2048, ascender=2027, descender=-431 -> (2027 - (-431)) / 2048 = 1.2002
const double _selawikNaturalLineHeight = 1.2002;

/// Styled text matching CSS font-size, line-height, letter-spacing, and weight.
pw.Widget cssText(
  String? text, {
  double sizePx = 13.0,
  int weight = 400,
  PdfColor color = ReportPdfTheme.inkPrint,
  double lineHeight = 1.5,
  bool upper = false,
  double? letterSpacingEm,
  bool italic = false,
  pw.TextAlign? align,
  int? maxLines,
}) {
  final raw = pdfSafe(text);
  final str = upper ? raw.toUpperCase() : raw;
  final sizePt = ReportPdfTheme.px(sizePx);
  final font = ReportFonts.fontForWeight(weight);

  // Line spacing adjustment
  final double halfLeading =
      math.max(0.0, (lineHeight - _selawikNaturalLineHeight) * sizePt / 2.0);

  final letterSpacingPt =
      letterSpacingEm != null ? letterSpacingEm * sizePt : null;

  pw.Widget widget = pw.Text(
    str,
    textAlign: align,
    maxLines: maxLines,
    style: pw.TextStyle(
      font: font,
      fontSize: sizePt,
      color: color,
      letterSpacing: letterSpacingPt,
    ),
  );

  if (italic) {
    widget = pw.Transform(
      transform: Matrix4.skewX(-0.2),
      child: widget,
    );
  }

  if (halfLeading > 0.1) {
    widget = pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: halfLeading),
      child: widget,
    );
  }

  return widget;
}

/// Backward compatibility helper for existing callers.
pw.Text pdfText(
  String? text, {
  double size = 9,
  bool bold = false,
  PdfColor? color,
  pw.TextAlign? align,
}) =>
    pw.Text(
      pdfSafe(text),
      textAlign: align,
      style: pw.TextStyle(
        font: bold ? ReportFonts.bold : ReportFonts.regular,
        fontSize: size,
        color: color ?? ReportPdfTheme.inkPrint,
      ),
    );

pw.Border cellBorder({bool top = true, bool bottom = true}) => pw.Border(
      top: top ? pdfBorderSide : pw.BorderSide.none,
      bottom: bottom ? pdfBorderSide : pw.BorderSide.none,
      left: pdfBorderSide,
      right: pdfBorderSide,
    );

pw.Widget tableHeaderCell(String text) => pw.Container(
      decoration: const pw.BoxDecoration(
          color: ReportPdfTheme.accentTint, border: pw.Border.fromBorderSide(pdfBorderSide)),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: cssText(text, sizePx: 13.0, weight: 700, color: ReportPdfTheme.inkPrint),
    );

pw.Widget tableBodyCell(String text, {bool bold = false}) => pw.Container(
      decoration: pw.BoxDecoration(border: cellBorder()),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: cssText(text, sizePx: 12.0, weight: bold ? 700 : 400),
    );

pw.Widget spanCell({
  required int indexInSpan,
  required int spanLen,
  required String label,
}) =>
    pw.Container(
      decoration: pw.BoxDecoration(
        border: cellBorder(
            top: indexInSpan == 0, bottom: indexInSpan == spanLen - 1),
      ),
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: (indexInSpan == spanLen ~/ 2)
          ? cssText(label, sizePx: 12.0, weight: 700, align: pw.TextAlign.center)
          : pw.SizedBox(),
    );

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

/// Card container per theme:105-112:
/// 0.75pt border, 3pt radius, padding 7.8 x 10.2pt, mb 9pt.
pw.Widget reportCard(
  List<pw.Widget> children, {
  pw.EdgeInsets? padding,
  pw.EdgeInsets? margin,
  PdfColor? background,
}) {
  return AvoidBreakInside(
    child: pw.Container(
      margin: margin ?? pw.EdgeInsets.only(bottom: ReportPdfTheme.px(12.0)),
      padding: padding ??
          pw.EdgeInsets.symmetric(
            vertical: ReportPdfTheme.px(10.4),
            horizontal: ReportPdfTheme.px(13.6),
          ),
      decoration: pw.BoxDecoration(
        color: background,
        border: pw.Border.all(
          color: ReportPdfTheme.border,
          width: 0.75,
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3.0)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: children,
      ),
    ),
  );
}

/// Section heading per theme:114-122:
/// 10.2pt bold UPPERCASE #1f4e79, 0.75pt bottom rule, pb 3pt, mb 4.8pt.
pw.Widget sectionHeading(String text) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 8.0),
      padding: const pw.EdgeInsets.only(bottom: 6.5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: ReportPdfTheme.accentTint, width: 0.75),
        ),
      ),
      child: cssText(
        text,
        sizePx: 13.6,
        weight: 700,
        upper: true,
        lineHeight: 1.2,
        color: ReportPdfTheme.accent,
      ),
    );

pw.Widget subHeading(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
      child: cssText(
        text,
        sizePx: 12.0,
        weight: 700,
        color: ReportPdfTheme.ink,
      ),
    );

/// Status badge per theme:237-270.
pw.Widget statusBadge(String tone, String label) {
  final (fg, bg, border) = switch (tone) {
    'ok' => (ReportPdfTheme.okFg, ReportPdfTheme.okBg, ReportPdfTheme.okBorder),
    'bad' => (ReportPdfTheme.badFg, ReportPdfTheme.badBg, ReportPdfTheme.badBorder),
    'warn' => (ReportPdfTheme.warnFg, ReportPdfTheme.warnBg, ReportPdfTheme.warnBorder),
    _ => (ReportPdfTheme.neutralFg, ReportPdfTheme.neutralBg, ReportPdfTheme.neutralBorder),
  };

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
    decoration: pw.BoxDecoration(
      color: bg,
      border: pw.Border.all(color: border, width: 0.75),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2.25)),
    ),
    child: cssText(label, sizePx: 11.0, weight: 600, color: fg),
  );
}

/// Thumbnail per theme:166-186:
/// Box 110x85px = 82.5x63.75pt, 0.75pt border, radius 2.25pt, padding 1.5pt.
/// Image is contained in 78x59.25pt.
pw.Widget thumb(Uint8List? bytes, {String? caption}) {
  const boxW = 82.5;
  const boxH = 63.75;
  const imgW = 78.0;
  const imgH = 59.25;

  pw.Widget inner;
  if (bytes != null && bytes.isNotEmpty) {
    try {
      inner = pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain);
    } catch (_) {
      inner = _unavailable(imgW, imgH);
    }
  } else {
    inner = _unavailable(imgW, imgH);
  }

  final container = pw.Container(
    width: boxW,
    height: boxH,
    padding: const pw.EdgeInsets.all(1.5),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      border: pw.Border.all(color: ReportPdfTheme.border, width: 0.75),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2.25)),
    ),
    alignment: pw.Alignment.center,
    child: inner,
  );

  if (caption != null && caption.isNotEmpty) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        container,
        pw.SizedBox(height: 2),
        pw.SizedBox(
          width: boxW,
          child: cssText(
            caption,
            sizePx: 9.5,
            color: ReportPdfTheme.muted,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  return container;
}

pw.Widget _unavailable(double w, double h) => pw.Container(
      width: w,
      height: h,
      alignment: pw.Alignment.center,
      color: ReportPdfTheme.surface,
      child: cssText('No photo', sizePx: 9.0, italic: true, color: ReportPdfTheme.faint),
    );

/// Wrapped row of photos using [thumb].
pw.Widget photoRow(
  List<ReportPhoto> list,
  Map<String, Uint8List?> photos,
  String emptyLabel, {
  double width = 82.5,
  double height = 63.75,
  bool captions = false,
}) {
  if (list.isEmpty) {
    return cssText(emptyLabel, sizePx: 11.5, italic: true, color: ReportPdfTheme.faint);
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

/// Report Header per theme:51-102.
pw.Widget reportHeader({
  required ReportOrganization org,
  required String title,
  String? subtitle,
  List<(String, String)> metaLeft = const [],
  List<(String, String)> metaRight = const [],
}) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.only(bottom: 10.65),
    margin: const pw.EdgeInsets.only(bottom: 13.0),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: ReportPdfTheme.accent, width: 1.5),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        cssText(
          org.railwayName,
          sizePx: 20.0,
          weight: 700,
          upper: true,
          lineHeight: 1.2,
          letterSpacingEm: 0.03,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 3.0),
        cssText(
          org.divisionName,
          sizePx: 16.0,
          weight: 600,
          lineHeight: 1.2,
          color: ReportPdfTheme.muted,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2.4),
        cssText(
          org.depotName,
          sizePx: 16.0,
          weight: 600,
          lineHeight: 1.2,
          color: ReportPdfTheme.muted,
          align: pw.TextAlign.center,
        ),
        if (metaLeft.isNotEmpty || metaRight.isNotEmpty) ...[
          pw.SizedBox(height: 6.6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final m in metaLeft)
                    pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: '${m.$1}: ',
                            style: pw.TextStyle(
                              font: ReportFonts.semibold,
                              fontSize: ReportPdfTheme.px(13.6),
                              color: ReportPdfTheme.inkPrint,
                            ),
                          ),
                          pw.TextSpan(
                            text: m.$2,
                            style: pw.TextStyle(
                              font: ReportFonts.regular,
                              fontSize: ReportPdfTheme.px(13.6),
                              color: ReportPdfTheme.inkPrint,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  for (final m in metaRight)
                    pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: '${m.$1}: ',
                            style: pw.TextStyle(
                              font: ReportFonts.semibold,
                              fontSize: ReportPdfTheme.px(13.6),
                              color: ReportPdfTheme.inkPrint,
                            ),
                          ),
                          pw.TextSpan(
                            text: m.$2,
                            style: pw.TextStyle(
                              font: ReportFonts.regular,
                              fontSize: ReportPdfTheme.px(13.6),
                              color: ReportPdfTheme.inkPrint,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 6.6),
        ],
        cssText(
          title,
          sizePx: 17.6,
          weight: 700,
          upper: true,
          lineHeight: 1.2,
          color: ReportPdfTheme.accent,
          letterSpacingEm: 0.05,
          align: pw.TextAlign.center,
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          pw.SizedBox(height: 2.9),
          cssText(
            subtitle,
            sizePx: 14.4,
            weight: 600,
            lineHeight: 1.2,
            align: pw.TextAlign.center,
          ),
        ],
      ],
    ),
  );
}

pw.Widget letterhead(
  ReportOrganization org,
  String title, {
  List<(String, String)> meta = const [],
  String? subtitle,
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
  );
}

/// Sign-off per theme:189-228 and reportPrimitives.jsx:46-83:
/// Technician, [Maintenance Staff], Supervisor side by side (gap 12pt),
/// labels muted 600, values with '·', remarks row, and meta row at bottom.
pw.Widget signOff({
  String? technician,
  String? maintenanceStaff,
  ReportVerification? verification,
  ReportSubmission? submission,
  required DateTime generatedAt,
}) {
  String tech = (technician ?? '').trim();
  if (tech.isEmpty) tech = '—';

  return reportCard(
    [
      sectionHeading('SIGN-OFF'),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: 'Technician: ',
                    style: pw.TextStyle(
                      font: ReportFonts.semibold,
                      fontSize: ReportPdfTheme.px(12.8),
                      color: ReportPdfTheme.muted,
                    ),
                  ),
                  pw.TextSpan(
                    text: pdfSafe(tech),
                    style: pw.TextStyle(
                      font: ReportFonts.regular,
                      fontSize: ReportPdfTheme.px(12.8),
                      color: ReportPdfTheme.inkPrint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (maintenanceStaff != null && maintenanceStaff.trim().isNotEmpty) ...[
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: 'Maintenance Staff: ',
                      style: pw.TextStyle(
                        font: ReportFonts.semibold,
                        fontSize: ReportPdfTheme.px(12.8),
                        color: ReportPdfTheme.muted,
                      ),
                    ),
                    pw.TextSpan(
                      text: pdfSafe(maintenanceStaff.trim()),
                      style: pw.TextStyle(
                        font: ReportFonts.regular,
                        fontSize: ReportPdfTheme.px(12.8),
                        color: ReportPdfTheme.inkPrint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: 'Supervisor: ',
                    style: pw.TextStyle(
                      font: ReportFonts.semibold,
                      fontSize: ReportPdfTheme.px(12.8),
                      color: ReportPdfTheme.muted,
                    ),
                  ),
                  pw.TextSpan(
                    text: pdfSafe(
                      verification == null
                          ? 'Pending verification'
                          : verification.verifiedAtLabel.isNotEmpty
                              ? '${verification.verifiedByName} · ${verification.verifiedAtLabel}'
                              : verification.verifiedByName,
                    ),
                    style: pw.TextStyle(
                      font: ReportFonts.regular,
                      fontSize: ReportPdfTheme.px(12.8),
                      color: ReportPdfTheme.inkPrint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      if (verification != null && verification.remarks.trim().isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: 'Supervisor Remarks: ',
                style: pw.TextStyle(
                  font: ReportFonts.semibold,
                  fontSize: ReportPdfTheme.px(12.8),
                  color: ReportPdfTheme.muted,
                ),
              ),
              pw.TextSpan(
                text: pdfSafe(verification.remarks.trim()),
                style: pw.TextStyle(
                  font: ReportFonts.regular,
                  fontSize: ReportPdfTheme.px(12.8),
                  color: ReportPdfTheme.inkPrint,
                ),
              ),
            ],
          ),
        ),
      ],
      pw.SizedBox(height: 8),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          if (submission != null)
            cssText(
              submission.timestampLabel.isNotEmpty
                  ? 'Submission #${submission.number} · ${submission.timestampLabel}'
                  : 'Submission #${submission.number}',
              sizePx: 11.0,
              color: ReportPdfTheme.faint,
            )
          else
            pw.SizedBox(),
          cssText(
            'Generated: ${formatGeneratedAt(generatedAt)}',
            sizePx: 11.0,
            color: ReportPdfTheme.faint,
          ),
        ],
      ),
    ],
  );
}

/// Simple table generator for general listings.
pw.Widget simpleTable(
  List<String> headers,
  List<List<String>> rows, {
  Map<int, pw.TableColumnWidth>? widths,
}) {
  return pw.TableHelper.fromTextArray(
    border: pw.TableBorder.all(color: ReportPdfTheme.border, width: 0.75),
    headerStyle: pw.TextStyle(
      font: ReportFonts.bold,
      fontSize: ReportPdfTheme.px(13.0),
      color: ReportPdfTheme.inkPrint,
    ),
    headerDecoration: const pw.BoxDecoration(color: ReportPdfTheme.accentTint),
    headerHeight: 20,
    cellHeight: 18,
    cellStyle: pw.TextStyle(
      font: ReportFonts.regular,
      fontSize: ReportPdfTheme.px(12.0),
      color: ReportPdfTheme.inkPrint,
    ),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4.5, vertical: 3.0),
    columnWidths: widths,
    headers: headers,
    data: rows,
  );
}

pw.Widget paramTable(List<ReportParameter> params) => simpleTable(
      const ['Parameter', 'Value', 'Unit'],
      [
        for (final p in params)
          [p.parameter, p.value, p.unit.isEmpty ? '-' : p.unit],
      ],
      widths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1.2),
      },
    );

pw.Widget textBox(String text, {String empty = 'None recorded'}) {
  final has = text.trim().isNotEmpty;
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(5),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: ReportPdfTheme.border, width: 0.75),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
    ),
    child: cssText(
      has ? text : empty,
      sizePx: 12.0,
      italic: !has,
      color: has ? ReportPdfTheme.inkPrint : ReportPdfTheme.faint,
    ),
  );
}

pw.Widget kvGrid(List<(String, String)> items) {
  pw.Widget cell((String, String) kv) {
    final label = kv.$1.trim();
    final hasColon = label.endsWith(':');
    final labelText = hasColon ? label : '$label:';
    return pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(right: 8, bottom: 3),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: '${pdfSafe(labelText)} ',
                  style: pw.TextStyle(
                    font: ReportFonts.semibold,
                    fontSize: ReportPdfTheme.px(12.0),
                    color: ReportPdfTheme.inkPrint,
                  ),
                ),
                pw.TextSpan(
                  text: pdfSafe(kv.$2),
                  style: pw.TextStyle(
                    font: ReportFonts.regular,
                    fontSize: ReportPdfTheme.px(12.0),
                    color: ReportPdfTheme.inkPrint,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  return pw.Column(children: [
    for (var i = 0; i < items.length; i += 2)
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          cell(items[i]),
          if (i + 1 < items.length)
            cell(items[i + 1])
          else
            pw.Expanded(child: pw.SizedBox()),
        ],
      ),
  ]);
}
