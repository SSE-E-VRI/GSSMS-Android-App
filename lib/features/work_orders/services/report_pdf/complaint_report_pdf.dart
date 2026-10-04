import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

const _borderPrintColor = PdfColor(0.2941, 0.3333, 0.3882);
const _borderPrintSide = pw.BorderSide(color: _borderPrintColor, width: 0.75);

/// Builds the printable Breakdown Job Work report (ComplaintExecutionPrintPreview).
List<pw.Widget> buildComplaintReportPdf(
    ComplaintJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  final pw.Widget section1Card;
  switch (r.section1Kind) {
    case ComplaintSection1Kind.deficiency:
      final d = r.deficiencyDetails!;
      section1Card = reportCard([
        sectionHeading('1. Deficiency Details'),
        _buildMetaRow3([
          ('Found in:', d.sourceTicket),
          ('Severity:', d.severity),
          ('Target date:', d.targetDate),
        ]),
        pw.SizedBox(height: 3.5),
        _buildMetaRow3([
          ('Asset / Equipment:', d.equipment),
          ('Checkpoint:', d.checkpoint),
          ('', ''),
        ]),
        pw.SizedBox(height: 5.0),
        cssText('Finding:', sizePx: 12.0, weight: 600, color: ReportPdfTheme.muted),
        pw.SizedBox(height: 2.0),
        _buildSectionBody(d.finding, empty: 'No finding recorded'),
      ]);
    case ComplaintSection1Kind.complaint:
      final c = r.complaintDetails!;
      section1Card = reportCard([
        sectionHeading('1. Breakdown Information'),
        _buildMetaRow3([
          ('Breakdown No:', c.complaintNumber),
          ('Failure Date & Time:', c.failureDateTime),
          ('Complainant:', c.complainant),
        ]),
        pw.SizedBox(height: 3.5),
        _buildMetaRow3([
          ('Reported Asset:', c.reportedAsset),
          ('', ''),
          ('', ''),
        ]),
        pw.SizedBox(height: 5.0),
        cssText('Original Description:', sizePx: 12.0, weight: 600, color: ReportPdfTheme.muted),
        pw.SizedBox(height: 2.0),
        _buildSectionBody(c.description, empty: 'None recorded'),
      ]);
    case ComplaintSection1Kind.jobWork:
      section1Card = reportCard([
        sectionHeading('1. Job Work Details'),
        _buildMetaRow2([
          ('Location:', r.station),
          ('Asset / Equipment:', r.assetName),
        ]),
        pw.SizedBox(height: 5.0),
        cssText('Work to be done:', sizePx: 12.0, weight: 600, color: ReportPdfTheme.muted),
        pw.SizedBox(height: 2.0),
        _buildSectionBody(r.workToBeDone, empty: 'None recorded'),
      ]);
  }

  return [
    letterhead(
      r.org,
      r.title,
      meta: [
        ('Location', r.station),
        ('Date', r.dateLabel),
      ],
      subtitle: 'Ticket #${r.ticket}',
    ),
    section1Card,
    reportCard([
      sectionHeading('Initial Assessment & Findings'),
      _buildSectionBody(r.initialFindings, empty: 'None recorded'),
    ]),
    reportCard([
      sectionHeading('Rectification / Action Taken'),
      _buildSectionBody(r.actionTaken, empty: 'None recorded'),
    ]),
    if (r.parameters.isNotEmpty)
      reportCard([
        sectionHeading('Technical Parameters'),
        _buildParametersTable(r.parameters),
      ]),
    reportCard([
      sectionHeading('Photo Evidence'),
      _buildEvidenceGrid(r.beforePhotos, r.afterPhotos, photos),
    ]),
    keepTogether([
      reportCard([
        sectionHeading('Final Remarks'),
        _buildSectionBody(r.finalRemarks, empty: 'None recorded'),
      ]),
      signOff(
        technician: r.submitter,
        verification: r.verification,
        submission: r.submission,
        generatedAt: at,
      ),
    ]),
  ];
}

pw.Widget _buildSectionBody(String text, {required String empty}) {
  final hasText = text.trim().isNotEmpty;
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 1.2),
    child: cssText(
      hasText ? text : empty,
      sizePx: 13.6, // 0.85rem = 10.2pt = 13.6px
      lineHeight: 1.35,
      weight: 400,
      italic: !hasText,
      color: hasText ? ReportPdfTheme.inkPrint : ReportPdfTheme.faint,
    ),
  );
}

pw.Widget _buildMetaItem(String label, String value) {
  if (label.isEmpty) return pw.SizedBox();
  return pw.RichText(
    text: pw.TextSpan(
      children: [
        pw.TextSpan(
          text: '$label ',
          style: pw.TextStyle(
            font: ReportFonts.semibold,
            fontSize: ReportPdfTheme.px(13.2), // 0.825rem = 9.9pt = 13.2px
            color: ReportPdfTheme.muted,
          ),
        ),
        pw.TextSpan(
          text: pdfSafe(value),
          style: pw.TextStyle(
            font: ReportFonts.regular,
            fontSize: ReportPdfTheme.px(13.2),
            color: ReportPdfTheme.inkPrint,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildMetaRow3(List<(String, String)> items) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _buildMetaItem(items[0].$1, items[0].$2),
      ),
      pw.SizedBox(width: 8),
      pw.Expanded(
        child: _buildMetaItem(items[1].$1, items[1].$2),
      ),
      pw.SizedBox(width: 8),
      pw.Expanded(
        child: _buildMetaItem(items[2].$1, items[2].$2),
      ),
    ],
  );
}

pw.Widget _buildMetaRow2(List<(String, String)> items) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _buildMetaItem(items[0].$1, items[0].$2),
      ),
      pw.SizedBox(width: 12),
      pw.Expanded(
        child: _buildMetaItem(items[1].$1, items[1].$2),
      ),
    ],
  );
}

pw.Widget _buildParametersTable(List<ReportParameter> params) {
  return pw.Table(
    border: const pw.TableBorder(
      top: _borderPrintSide,
      bottom: _borderPrintSide,
      left: _borderPrintSide,
      right: _borderPrintSide,
      horizontalInside: _borderPrintSide,
      verticalInside: _borderPrintSide,
    ),
    columnWidths: const {
      0: pw.FlexColumnWidth(238.5),
      1: pw.FlexColumnWidth(150.0),
      2: pw.FlexColumnWidth(128.25),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: ReportPdfTheme.accentTint),
        children: [
          _paramCell('Parameter', isHeader: true),
          _paramCell('Value', isHeader: true),
          _paramCell('Unit', isHeader: true),
        ],
      ),
      for (final p in params)
        pw.TableRow(
          children: [
            _paramCell(p.parameter),
            _paramCell(p.value),
            _paramCell(p.unit.isEmpty ? '-' : p.unit),
          ],
        ),
    ],
  );
}

pw.Widget _paramCell(String text, {bool isHeader = false}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.2),
    child: cssText(
      text,
      sizePx: 13.0,
      weight: isHeader ? 700 : 400,
      color: ReportPdfTheme.inkPrint,
    ),
  );
}

pw.Widget _buildEvidenceGrid(
  List<ReportPhoto> beforeList,
  List<ReportPhoto> afterList,
  Map<String, Uint8List?> photos,
) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 4.2),
    padding: const pw.EdgeInsets.symmetric(horizontal: 9.0, vertical: 6.0),
    decoration: pw.BoxDecoration(
      color: ReportPdfTheme.surface,
      border: pw.Border.all(color: _borderPrintColor, width: 0.75),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3.0)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              cssText(
                'Before / Initial Condition',
                sizePx: 12.4, // 0.775rem = 9.3pt = 12.4px
                weight: 700,
                letterSpacingEm: 0.02,
                color: ReportPdfTheme.muted,
              ),
              pw.SizedBox(height: 4.2),
              _buildEvidencePhotos(beforeList, photos),
            ],
          ),
        ),
        pw.SizedBox(width: 9.0),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              cssText(
                'After / Rectification Result',
                sizePx: 12.4,
                weight: 700,
                letterSpacingEm: 0.02,
                color: ReportPdfTheme.muted,
              ),
              pw.SizedBox(height: 4.2),
              _buildEvidencePhotos(afterList, photos),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildEvidencePhotos(
  List<ReportPhoto> list,
  Map<String, Uint8List?> photos,
) {
  if (list.isEmpty) {
    return cssText(
      'No photo uploaded',
      sizePx: 12.4,
      italic: true,
      color: ReportPdfTheme.faint,
      lineHeight: 1.8,
    );
  }
  return pw.Wrap(
    spacing: 6.75,
    runSpacing: 6.75,
    children: [
      for (final p in list)
        thumb(photos[p.key]),
    ],
  );
}
