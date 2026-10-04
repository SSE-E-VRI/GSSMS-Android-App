import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

List<pw.Widget> buildRectificationReportPdf(
    RectificationJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  String outcomeLabel(RectificationOutcome o) => switch (o) {
        RectificationOutcome.rectified => 'Rectified',
        RectificationOutcome.notRectified => 'Not rectified',
        RectificationOutcome.pending => 'Pending',
      };
  return [
    letterhead(r.org, r.title, meta: [
      ('Location', r.station),
      ('Date', r.dateLabel),
    ], subtitle: 'Job Work ${r.ticket}'),
    pw.Container(
      width: double.infinity,
      color: PdfColors.grey200,
      padding: const pw.EdgeInsets.all(5),
      child: pdfText(r.summaryLine, size: 9.5, bold: true),
    ),
    for (var i = 0; i < r.items.length; i++) ...[
      pw.SizedBox(height: 10),
      pw.Container(
        width: double.infinity,
        color: PdfColors.grey300,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pdfText('Item ${i + 1}: ${r.items[i].asset}',
                  size: 9.5, bold: true),
            ),
            pdfText(outcomeLabel(r.items[i].outcome), size: 9, bold: true),
          ],
        ),
      ),
      pw.SizedBox(height: 4),
      kvGrid([
        ('Source', r.items[i].sourceLabel),
        ('Checkpoint',
            r.items[i].checkpoint.isEmpty ? 'N/A' : r.items[i].checkpoint),
        ('Severity', r.items[i].severity),
      ]),
      subHeading('FINDING'),
      textBox(r.items[i].finding, empty: 'No finding recorded'),
      subHeading('ACTION TAKEN'),
      textBox(r.items[i].actionTaken, empty: 'No action recorded'),
      if (r.items[i].outcome == RectificationOutcome.notRectified) ...[
        subHeading('REASON IT COULD NOT BE RECTIFIED'),
        textBox(r.items[i].reason, empty: 'No reason recorded'),
      ],
      subHeading('BEFORE EVIDENCE'),
      photoRow(r.items[i].beforePhotos, photos, 'No before photo'),
      subHeading('AFTER EVIDENCE'),
      photoRow(r.items[i].afterPhotos, photos, 'No after photo'),
    ],
    sectionHeading('Final Outcome'),
    textBox(r.finalRemarks, empty: 'No final remarks recorded'),
    signOff(
      technician: r.technician,
      maintenanceStaff: r.otherStaff,
      verification: r.verification,
      generatedAt: at,
    ),
  ];
}
