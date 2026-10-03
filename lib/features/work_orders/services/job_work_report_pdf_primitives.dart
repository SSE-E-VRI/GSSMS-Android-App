import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';

// Shared building blocks for [JobWorkReportPdfService]. Ports the web
// reportPrimitives.jsx layout language to the `pdf` package.

/// Helvetica only covers Latin-1: map common typographic characters to ASCII
/// so they never render as blanks. Apply to every `pw.Text`.
String pdfSafe(String? s) {
  if (s == null || s.isEmpty) return '';
  const map = <String, String>{
    '—': '-', // em dash
    '–': '-', // en dash
    '·': '|', // middle dot
    '•': '*', // bullet
    '‘': "'",
    '’': "'",
    '“': '"',
    '”': '"',
    '…': '...',
    '₹': 'Rs.',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final m = map[ch];
    if (m != null) {
      b.write(m);
    } else if (r > 0xFF) {
      b.write('?');
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

const pdfBorderColor = PdfColors.grey400;
const pdfBorderSide = pw.BorderSide(color: pdfBorderColor, width: 0.5);

pw.Text pdfText(String? text,
        {double size = 9,
        bool bold = false,
        PdfColor? color,
        pw.TextAlign? align}) =>
    pw.Text(
      pdfSafe(text),
      textAlign: align,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    );

pw.Border cellBorder({bool top = true, bool bottom = true}) => pw.Border(
      top: top ? pdfBorderSide : pw.BorderSide.none,
      bottom: bottom ? pdfBorderSide : pw.BorderSide.none,
      left: pdfBorderSide,
      right: pdfBorderSide,
    );

pw.Widget tableHeaderCell(String text) => pw.Container(
      decoration: pw.BoxDecoration(
          color: PdfColors.blueGrey800, border: cellBorder()),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pdfText(text, bold: true, color: PdfColors.white),
    );

pw.Widget tableBodyCell(String text, {bool bold = false}) => pw.Container(
      decoration: pw.BoxDecoration(border: cellBorder()),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pdfText(text, size: 8.5, bold: bold),
    );

/// A merged (row-span) cell faked with a plain table: top / bottom borders
/// only on the first / last row of the span, label once on the middle row.
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
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: indexInSpan == (spanLen - 1) ~/ 2
          ? pdfText(label, bold: true, align: pw.TextAlign.center)
          : pw.SizedBox(),
    );

/// Plain bordered table with a dark header row.
pw.Widget simpleTable(
  List<String> headers,
  List<List<String>> rows, {
  Map<int, pw.TableColumnWidth>? widths,
}) =>
    pw.Table(
      columnWidths: widths,
      children: [
        pw.TableRow(children: [for (final h in headers) tableHeaderCell(h)]),
        for (final r in rows)
          pw.TableRow(children: [for (final c in r) tableBodyCell(c)]),
      ],
    );

pw.Widget letterhead(
  ReportOrganization org,
  String title, {
  List<(String, String)> meta = const [],
  String? subtitle,
}) {
  pw.Widget metaItem((String, String) m) => pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.black),
          children: [
            pw.TextSpan(
                text: '${pdfSafe(m.$1)}: ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: pdfSafe(m.$2)),
          ],
        ),
      );

  return pw.Container(
    width: double.infinity,
    alignment: pw.Alignment.center,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pdfText(org.railwayName.toUpperCase(), size: 14, bold: true),
        pdfText(org.divisionName, size: 11, bold: true),
        pdfText(org.depotName, size: 11, bold: true),
        pw.SizedBox(height: 6),
        if (meta.isNotEmpty)
          pw.Wrap(
            alignment: pw.WrapAlignment.spaceBetween,
            runAlignment: pw.WrapAlignment.center,
            spacing: 18,
            runSpacing: 4,
            children: [for (final m in meta) metaItem(m)],
          ),
        pw.SizedBox(height: 8),
        pdfText(title, size: 13, bold: true, align: pw.TextAlign.center),
        if (subtitle != null && subtitle.isNotEmpty)
          pdfText(subtitle, size: 10, align: pw.TextAlign.center),
        pw.SizedBox(height: 10),
      ],
    ),
  );
}

pw.Widget sectionHeading(String text) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
      padding: const pw.EdgeInsets.only(bottom: 2),
      decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pdfBorderSide)),
      child: pdfText(text, size: 10.5, bold: true),
    );

pw.Widget subHeading(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
      child: pdfText(text, size: 9, bold: true, color: PdfColors.grey800),
    );

/// Two-column label/value grid.
pw.Widget kvGrid(List<(String, String)> items) {
  pw.Widget cell((String, String) kv) => pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(right: 8, bottom: 3),
          child: pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 9),
              children: [
                pw.TextSpan(
                    text: '${pdfSafe(kv.$1)}: ',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.TextSpan(text: pdfSafe(kv.$2)),
              ],
            ),
          ),
        ),
      );
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

pw.Widget textBox(String text, {String empty = 'None recorded'}) {
  final has = text.trim().isNotEmpty;
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(5),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: pdfBorderColor)),
    child: pdfText(has ? text : empty,
        size: 9, color: has ? PdfColors.black : PdfColors.grey600),
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

pw.Widget? _image(Uint8List? bytes, double w, double h) {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    return pw.Container(
      width: w,
      height: h,
      decoration:
          pw.BoxDecoration(border: pw.Border.all(color: pdfBorderColor)),
      child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
    );
  } catch (_) {
    return null;
  }
}

pw.Widget _unavailable(double w, double h) => pw.Container(
      width: w,
      height: h,
      alignment: pw.Alignment.center,
      color: PdfColors.grey200,
      child: pdfText('Photo unavailable', size: 7, color: PdfColors.grey700),
    );

/// Wrapped row of photo thumbnails; [emptyLabel] when [list] is empty.
pw.Widget photoRow(
  List<ReportPhoto> list,
  Map<String, Uint8List?> photos,
  String emptyLabel, {
  double width = 106,
  double height = 81,
  bool captions = false,
}) {
  if (list.isEmpty) {
    return pdfText(emptyLabel, size: 8.5, color: PdfColors.grey600);
  }
  return pw.Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final p in list)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            _image(photos[p.key], width, height) ??
                _unavailable(width, height),
            if (captions && (p.kind.isNotEmpty || p.caption.isNotEmpty))
              pw.SizedBox(
                width: width,
                child: pdfText(
                    [p.kind, p.caption].where((s) => s.isNotEmpty).join(' - '),
                    size: 6.5,
                    color: PdfColors.grey700),
              ),
          ],
        ),
    ],
  );
}

pw.Widget signOff({
  String? technician,
  String? maintenanceStaff,
  ReportVerification? verification,
  ReportSubmission? submission,
  required DateTime generatedAt,
}) {
  String tech = (technician ?? '').trim();
  if (tech.isEmpty) tech = '-';
  final rows = <(String, String)>[
    ('Technician', tech),
    if ((maintenanceStaff ?? '').trim().isNotEmpty)
      ('Maintenance Staff', maintenanceStaff!.trim()),
    (
      'Supervisor',
      verification == null
          ? 'Pending verification'
          : '${verification.verifiedByName} | '
              '${formatReportDateTime(verification.verifiedAt)}'
    ),
    if (verification != null && verification.remarks.isNotEmpty)
      ('Supervisor Remarks', verification.remarks),
  ];
  return pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(top: 10),
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: pdfBorderColor)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pdfText('Sign-off', size: 10, bold: true),
        pw.SizedBox(height: 4),
        for (final r in rows)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 9),
                children: [
                  pw.TextSpan(
                      text: '${pdfSafe(r.$1)}: ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.TextSpan(text: pdfSafe(r.$2)),
                ],
              ),
            ),
          ),
        if (submission != null && submission.number.isNotEmpty)
          pdfText(
              'Submission #${submission.number} | '
              '${formatReportDateTime(submission.timestamp)}',
              size: 8,
              color: PdfColors.grey700),
        pdfText('Generated: ${formatReportDateTime(generatedAt)}',
            size: 8, color: PdfColors.grey700),
      ],
    ),
  );
}
