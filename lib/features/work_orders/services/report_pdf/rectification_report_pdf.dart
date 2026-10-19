import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

/// `.reportContainer` line-height of RectificationReportPreview.
const double _root = 1.4;

/// `.contentBody` / `.reasonBody` / `.outcomeBody` line-height.
const double _bodyLh = 1.35;

/// Builds the printable Deficiency Rectification report
/// (RectificationReportPreview.jsx + .module.css, print rules applied).
List<pw.Widget> buildRectificationReportPdf(
    RectificationJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  final hasRemarks = r.finalRemarks.trim().isNotEmpty;
  return [
    letterhead(
      r.org,
      r.title,
      meta: [
        ('Location', r.station),
        ('Date', r.dateLabel),
      ],
      subtitle: 'Job Work ${r.ticket}',
      lineHeight: _root,
    ),
    // .reportSummaryBar: 0.825rem muted, centred, margin-bottom 1rem.
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12.0),
      child: pw.SizedBox(
        width: double.infinity,
        child: cssText(
          r.summaryLine,
          sizePt: 9.9,
          color: ReportPdfTheme.muted,
          lineHeight: _root,
          align: pw.TextAlign.center,
        ),
      ),
    ),
    for (var i = 0; i < r.items.length; i++)
      _buildItemCard(r.items[i], i, photos),
    keepTogether([
      // .outcomeSection: margin-top 0.5rem collapses with the last item
      // card's 0.85rem margin-bottom, so only the bottom margin is laid out.
      reportCard(
        [
          // .outcomeHeader
          CssBox(
            padding: const pw.EdgeInsets.only(bottom: 4.2),
            margin: const pw.EdgeInsets.only(bottom: 4.8),
            bottom: const CssSide(0.75, ReportPdfTheme.accentTint),
            child: cssText(
              'Final Outcome',
              sizePt: 10.2,
              weight: 700,
              upper: true,
              color: ReportPdfTheme.accent,
              lineHeight: _root,
            ),
          ),
          // .outcomeBody
          _body(hasRemarks ? r.finalRemarks : 'No final remarks recorded',
              has: hasRemarks, padH: 0),
        ],
        margin: const pw.EdgeInsets.only(bottom: 6.0),
      ),
      // signoffCard margin-top 9 collapses with the outcome card's 6.
      signOff(
        technician: r.technician,
        maintenanceStaff: r.otherStaff,
        verification: r.verification,
        generatedAt: at,
        lineHeight: _root,
        collapseWith: 6.0,
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
      // .itemHeader: flex, space-between, centred; rule 0.75 #4b5563 (print),
      // padding-bottom 0.4rem, margin-bottom 0.5rem. h5 keeps Bootstrap's 1.2.
      CssBox(
        padding: const pw.EdgeInsets.only(bottom: 4.8),
        margin: const pw.EdgeInsets.only(bottom: 6.0),
        bottom: const CssSide(0.75, ReportPdfTheme.borderPrint),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: cssText(
                'Item ${index + 1}: ${item.asset}',
                sizePt: 11.4,
                weight: 700,
                color: ReportPdfTheme.headingInk,
                lineHeight: 1.2,
              ),
            ),
            statusBadge(tone, label),
          ],
        ),
      ),

      // .itemMetaGrid: 3 auto-fit columns, gap 0.35rem 0.75rem.
      CssBox.bordered(
        margin: const pw.EdgeInsets.only(bottom: 6.0),
        padding: const pw.EdgeInsets.symmetric(vertical: 4.8, horizontal: 7.2),
        side: const CssSide(0.75, ReportPdfTheme.borderPrint),
        radius: 2.25,
        background: ReportPdfTheme.surface,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _meta('Source:', item.sourceLabel)),
            pw.SizedBox(width: 9.0),
            pw.Expanded(child: _meta('Checkpoint:', item.checkpoint)),
            pw.SizedBox(width: 9.0),
            pw.Expanded(
                child: _meta('Severity:',
                    item.severity.isEmpty ? 'N/A' : item.severity)),
          ],
        ),
      ),

      _contentBlock('Finding', item.finding, empty: 'No finding recorded'),
      _contentBlock('Action Taken', item.actionTaken,
          empty: 'No action recorded'),
      if (item.outcome == RectificationOutcome.notRectified)
        _contentBlock(
          'Reason it could not be rectified',
          item.reason,
          empty: 'No reason recorded',
          isReason: true,
        ),

      // .evidenceGrid: margin-top 0.4rem collapses with the preceding
      // contentBlock's 0.5rem margin-bottom (no extra gap).
      CssBox.bordered(
        padding: const pw.EdgeInsets.symmetric(vertical: 6.0, horizontal: 9.0),
        side: const CssSide(0.75, ReportPdfTheme.borderPrint),
        radius: 3.0,
        background: ReportPdfTheme.surface,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
                child: _evidenceCol('Before Evidence', item.beforePhotos,
                    photos, 'No before photo')),
            pw.SizedBox(width: 9.0),
            pw.Expanded(
                child: _evidenceCol('After Evidence', item.afterPhotos, photos,
                    'No after photo')),
          ],
        ),
      ),
    ],
    margin: const pw.EdgeInsets.only(bottom: 10.2),
  );
}

/// `.metaLabel` (semibold muted, margin-right 0.25rem = 3pt) + `.metaVal` (weight
/// 500, which Chrome/Windows renders as Segoe UI Semibold).
pw.Widget _meta(String label, String value) => cssRich(
      [
        CssSpan(label,
            weight: 600, color: ReportPdfTheme.muted, trailingGapPt: 3.0),
        CssSpan(value, weight: 600),
      ],
      sizePt: 9.6,
      lineHeight: _root,
    );

/// Body text: 0.85rem, line-height 1.35, pre-wrap. Empty states are
/// `text-muted fst-italic`.
pw.Widget _body(String text, {required bool has, double padH = 1.2}) {
  final t = cssText(
    text,
    sizePt: 10.2,
    italic: !has,
    color: has ? ReportPdfTheme.inkPrint : ReportPdfTheme.muted,
    lineHeight: _bodyLh,
  );
  return padH == 0
      ? t
      : pw.Padding(padding: pw.EdgeInsets.symmetric(horizontal: padH), child: t);
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
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        // .contentLabel: dashed 0.75 #d1d5db rule, padding-bottom 0.15rem,
        // margin-bottom 0.25rem.
        CssBox(
          padding: const pw.EdgeInsets.only(bottom: 1.8),
          margin: const pw.EdgeInsets.only(bottom: 3.0),
          bottom: const CssSide(0.75, ReportPdfTheme.border, dashed: true),
          child: cssText(
            label,
            sizePt: 9.3,
            weight: 700,
            upper: true,
            letterSpacingEm: 0.03,
            color: ReportPdfTheme.muted,
            lineHeight: _root,
          ),
        ),
        if (isReason)
          // .reasonBody: left border only (the pink fill is not printed).
          CssBox(
            left: const CssSide(2.25, ReportPdfTheme.badBorder),
            padding:
                const pw.EdgeInsets.symmetric(vertical: 3.0, horizontal: 6.0),
            child: cssText(
              has ? value : empty,
              sizePt: 10.2,
              italic: !has,
              color: has ? ReportPdfTheme.badFg : ReportPdfTheme.muted,
              lineHeight: _bodyLh,
            ),
          )
        else
          _body(has ? value : empty, has: has),
      ],
    ),
  );
}

/// Column width inside the evidence grid: (517.5 - 2 * 0.75 - 2 * 9 - 9) / 2.
const double _evidenceColW = 244.5;

pw.Widget _evidenceCol(
  String heading,
  List<ReportPhoto> list,
  Map<String, Uint8List?> photos,
  String emptyLabel,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      // .evidenceHeading: 0.75rem bold uppercase, letter-spacing 0.04em,
      // margin-bottom 0.35rem.
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4.2),
        child: cssText(
          heading,
          sizePt: 9.0,
          weight: 700,
          upper: true,
          letterSpacingEm: 0.04,
          color: ReportPdfTheme.muted,
          lineHeight: _root,
        ),
      ),
      if (list.isEmpty)
        // .emptyPhotoText: 0.775rem italic, line-height 1.8.
        cssText(
          emptyLabel,
          sizePt: 9.3,
          italic: true,
          color: ReportPdfTheme.faint,
          lineHeight: 1.8,
        )
      else
        ...photoGridLines(
          [for (final p in list) PhotoTile(photos[p.key])],
          _evidenceColW,
          lineHeight: _root,
        ),
    ],
  );
}
