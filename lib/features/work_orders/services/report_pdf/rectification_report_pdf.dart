import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

List<pw.Widget> buildRectificationReportPdf(
    RectificationJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  return [
    letterhead(r.org, r.title, meta: [
      ('Location', r.station),
      ('Date', r.dateLabel),
    ], subtitle: 'Job Work ${r.ticket}'),
    pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 12.0),
      alignment: pw.Alignment.center,
      child: cssText(
        r.summaryLine,
        sizePx: 13.2,
        color: ReportPdfTheme.muted,
        align: pw.TextAlign.center,
      ),
    ),
    for (var i = 0; i < r.items.length; i++)
      _buildItemCard(r.items[i], i, photos),
    keepTogether([
      reportCard(
        [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.only(bottom: 4.2),
            margin: const pw.EdgeInsets.only(bottom: 4.8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom:
                    pw.BorderSide(color: ReportPdfTheme.accentTint, width: 0.75),
              ),
            ),
            child: cssText(
              'Final Outcome',
              sizePx: 13.6,
              weight: 700,
              upper: true,
              color: ReportPdfTheme.accent,
            ),
          ),
          cssText(
            r.finalRemarks.trim().isNotEmpty
                ? r.finalRemarks
                : 'No final remarks recorded',
            sizePx: 13.6,
            italic: r.finalRemarks.trim().isEmpty,
            color: r.finalRemarks.trim().isNotEmpty
                ? ReportPdfTheme.inkPrint
                : ReportPdfTheme.faint,
          ),
        ],
        margin: const pw.EdgeInsets.only(bottom: 6.0),
      ),
      signOff(
        technician: r.technician,
        maintenanceStaff: r.otherStaff,
        verification: r.verification,
        generatedAt: at,
      ),
    ]),
  ];
}

pw.Widget _buildItemCard(
  RectificationReportItem item,
  int index,
  Map<String, Uint8List?> photos,
) {
  final (tone, label) = switch (item.outcome) {
    RectificationOutcome.rectified => ('ok', 'Rectified'),
    RectificationOutcome.notRectified => ('bad', 'Not rectified'),
    RectificationOutcome.pending => ('neutral', 'Pending'),
  };

  return reportCard(
    [
      // Item Header
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 4.8),
        margin: const pw.EdgeInsets.only(bottom: 6.0),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: ReportPdfTheme.border, width: 0.75),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: cssText('Item ${index + 1}: ${item.asset}',
                  sizePx: 15.2, weight: 700),
            ),
            pw.SizedBox(width: 6),
            statusBadge(tone, label),
          ],
        ),
      ),

      // Metadata Bar
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 4.8, horizontal: 7.2),
        margin: const pw.EdgeInsets.only(bottom: 6.0),
        decoration: pw.BoxDecoration(
          color: ReportPdfTheme.surface,
          border: pw.Border.all(color: ReportPdfTheme.border, width: 0.75),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2.25)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: 'Source: ',
                      style: pw.TextStyle(
                        font: ReportFonts.semibold,
                        fontSize: ReportPdfTheme.px(12.8),
                        color: ReportPdfTheme.muted,
                      ),
                    ),
                    pw.TextSpan(
                      text: pdfSafe(item.sourceLabel),
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
            pw.SizedBox(width: 9.0),
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: 'Checkpoint: ',
                      style: pw.TextStyle(
                        font: ReportFonts.semibold,
                        fontSize: ReportPdfTheme.px(12.8),
                        color: ReportPdfTheme.muted,
                      ),
                    ),
                    pw.TextSpan(
                      text: pdfSafe(
                          item.checkpoint.isEmpty ? 'N/A' : item.checkpoint),
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
            pw.SizedBox(width: 9.0),
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: 'Severity: ',
                      style: pw.TextStyle(
                        font: ReportFonts.semibold,
                        fontSize: ReportPdfTheme.px(12.8),
                        color: ReportPdfTheme.muted,
                      ),
                    ),
                    pw.TextSpan(
                      text: pdfSafe(item.severity.isEmpty ? 'N/A' : item.severity),
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
      ),

      // Finding
      _contentBlock('Finding', item.finding, empty: 'No finding recorded'),

      // Action Taken
      _contentBlock('Action Taken', item.actionTaken,
          empty: 'No action recorded'),

      // Reason it could not be rectified
      if (item.outcome == RectificationOutcome.notRectified)
        _contentBlock(
          'Reason it could not be rectified',
          item.reason,
          empty: 'No reason recorded',
          isReason: true,
        ),

      // Evidence Grid
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 4.8),
        padding: const pw.EdgeInsets.symmetric(vertical: 6.0, horizontal: 9.0),
        decoration: pw.BoxDecoration(
          color: ReportPdfTheme.surface,
          border: pw.Border.all(color: ReportPdfTheme.border, width: 0.75),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3.0)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _evidenceCol('Before Evidence', item.beforePhotos, photos,
                'No before photo'),
            pw.SizedBox(width: 9.0),
            _evidenceCol(
                'After Evidence', item.afterPhotos, photos, 'No after photo'),
          ],
        ),
      ),
    ],
    margin: const pw.EdgeInsets.only(bottom: 10.2),
  );
}

pw.Widget _contentBlock(
  String label,
  String value, {
  String empty = 'None recorded',
  bool isReason = false,
}) {
  final has = value.trim().isNotEmpty;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6.0),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(bottom: 1.8),
          margin: const pw.EdgeInsets.only(bottom: 3.0),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: ReportPdfTheme.border, width: 0.75),
            ),
          ),
          child: cssText(
            label,
            sizePx: 12.4,
            weight: 700,
            upper: true,
            letterSpacingEm: 0.03,
            color: ReportPdfTheme.muted,
          ),
        ),
        if (isReason)
          pw.Container(
            width: double.infinity,
            padding:
                const pw.EdgeInsets.symmetric(vertical: 3.0, horizontal: 6.0),
            decoration: const pw.BoxDecoration(
              color: ReportPdfTheme.badBg,
              border: pw.Border(
                left: pw.BorderSide(color: ReportPdfTheme.badBorder, width: 3.0),
              ),
            ),
            child: cssText(
              has ? value : empty,
              sizePx: 13.6,
              italic: !has,
              color: has ? ReportPdfTheme.badFg : ReportPdfTheme.faint,
            ),
          )
        else
          cssText(
            has ? value : empty,
            sizePx: 13.6,
            italic: !has,
            color: has ? ReportPdfTheme.inkPrint : ReportPdfTheme.faint,
          ),
      ],
    ),
  );
}

pw.Widget _evidenceCol(
  String heading,
  List<ReportPhoto> list,
  Map<String, Uint8List?> photos,
  String emptyLabel,
) {
  return pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        cssText(
          heading,
          sizePx: 12.0,
          weight: 700,
          upper: true,
          letterSpacingEm: 0.04,
          color: ReportPdfTheme.muted,
        ),
        pw.SizedBox(height: 4.2),
        if (list.isEmpty)
          cssText(
            emptyLabel,
            sizePx: 12.4,
            italic: true,
            color: ReportPdfTheme.faint,
          )
        else
          pw.Wrap(
            spacing: 6.0,
            runSpacing: 6.0,
            children: [
              for (final p in list) thumb(photos[p.key]),
            ],
          ),
      ],
    ),
  );
}
