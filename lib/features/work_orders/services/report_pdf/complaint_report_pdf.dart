import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

// Layout constants (pt) from ComplaintExecutionPrintPreview.module.css.
// Card content width: 540 (page) - 2 * (0.75 border + 10.2 padding).
const double _cardContentW = 518.1;
const double _gridColGap = 10.2; // 0.85rem
const double _gridRowGap = 4.8; // 0.4rem
const double _metaSizePt = 9.9; // 0.825rem
const double _bodySizePt = 10.2; // 0.85rem
const double _bodyLineHeight = 1.35;
/// Selawik Semibold is ~1.5% wider than Segoe UI Semibold on average; a small
/// negative tracking brings run widths back in line.
const double _semiboldTrack = -0.0088;
const double _evidenceGap = 9.0; // 0.75rem
// Evidence grid content: card content - border 1.5 - padding 2 * 9.
const double _evidenceContentW = _cardContentW - 1.5 - 18.0;
const double _evidenceColW = (_evidenceContentW - _evidenceGap) / 2;

/// Builds the printable Breakdown Job Work report (ComplaintExecutionPrintPreview).
///
/// Root line-height is [ReportRoot.lineHeight] (1.4 for this report; the
/// service sets it before calling).
List<pw.Widget> buildComplaintReportPdf(
    ComplaintJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  final root = ReportRoot.lineHeight;

  final pw.Widget section1Card;
  switch (r.section1Kind) {
    case ComplaintSection1Kind.deficiency:
      final d = r.deficiencyDetails!;
      section1Card = reportCard([
        sectionHeading('1. Deficiency Details', lineHeight: root),
        _metaGrid([
          ('Found in:', d.sourceTicket),
          ('Severity:', d.severity),
          ('Target date:', d.targetDate),
          ('Asset / Equipment:', d.equipment),
          ('Checkpoint:', d.checkpoint),
        ], columns: 3, lineHeight: root),
        _labelledBody('Finding:', d.finding,
            empty: 'No finding recorded', root: root),
      ]);
    case ComplaintSection1Kind.complaint:
      final c = r.complaintDetails!;
      section1Card = reportCard([
        sectionHeading('1. Breakdown Information', lineHeight: root),
        _metaGrid([
          ('Breakdown No:', c.complaintNumber),
          ('Failure Date & Time:', c.failureDateTime),
          ('Complainant:', c.complainant),
          ('Reported Asset:', c.reportedAsset),
        ], columns: 3, lineHeight: root),
        _labelledBody('Original Description:', c.description,
            empty: 'None recorded', root: root),
      ]);
    case ComplaintSection1Kind.jobWork:
      section1Card = reportCard([
        sectionHeading('1. Job Work Details', lineHeight: root),
        _metaGrid([
          ('Location:', r.station),
          ('Asset / Equipment:', r.assetName),
        ], columns: 2, lineHeight: root),
        _labelledBody('Work to be done:', r.workToBeDone,
            empty: 'None recorded', root: root),
      ]);
  }

  return [
    _header(r, root),
    section1Card,
    reportCard([
      sectionHeading('Initial Assessment & Findings', lineHeight: root),
      _sectionBody(r.initialFindings, empty: 'None recorded'),
    ]),
    reportCard([
      sectionHeading('Rectification / Action Taken', lineHeight: root),
      _sectionBody(r.actionTaken, empty: 'None recorded'),
    ]),
    if (r.parameters.isNotEmpty)
      reportCard([
        sectionHeading('Technical Parameters', lineHeight: root),
        cssTable(
          const ['Parameter', 'Value', 'Unit'],
          [
            for (final p in r.parameters)
              [p.parameter, p.value, p.unit.isEmpty ? '-' : p.unit],
          ],
          lineHeight: root,
        ),
      ]),
    reportCard([
      sectionHeading('Photo Evidence', lineHeight: root),
      _evidenceGrid(r.beforePhotos, r.afterPhotos, photos, root),
    ]),
    keepTogether([
      reportCard([
        sectionHeading('Final Remarks', lineHeight: root),
        _sectionBody(r.finalRemarks, empty: 'None recorded'),
      ]),
      signOff(
        technician: r.submitter,
        verification: r.verification,
        submission: r.submission,
        generatedAt: at,
        lineHeight: root,
      ),
    ]),
  ];
}

/// `.sectionBody`: 10.2pt, line-height 1.35, pre-wrap, padding 0 1.2pt. The
/// empty state is a 9.9pt italic span inside the same 10.2pt strut, so the
/// line box (13.77pt) and baseline stay those of the 10.2pt strut.
pw.Widget _sectionBody(String text, {required String empty}) {
  final hasText = text.trim().isNotEmpty;
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 1.2),
    child: hasText
        ? cssText(
            text,
            sizePt: _bodySizePt,
            lineHeight: _bodyLineHeight,
            color: ReportPdfTheme.inkPrint,
          )
        : pw.Padding(
            // Strut baseline (0.675 + 0.41405) * 10.2 vs the span's * 9.9.
            padding: const pw.EdgeInsets.only(top: 0.33, bottom: 0.075),
            child: cssText(
              empty,
              sizePt: _metaSizePt,
              lineHeight: _bodyLineHeight,
              italic: true,
              color: ReportPdfTheme.faint,
            ),
          ),
  );
}

/// A label span followed by a `.sectionBody` block: the label sits in a 12pt
/// (article font) strut line of the root line-height.
pw.Widget _labelledBody(String label, String text,
    {required String empty, required double root}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      cssText(
        label,
        sizePt: 12.0,
        weight: 600,
        color: ReportPdfTheme.muted,
        lineHeight: root,
      ),
      _sectionBody(text, empty: empty),
    ],
  );
}

/// `.itemMetaGrid` with transparent background / no border / no padding:
/// [columns] equal tracks, gap 4.8 x 10.2, margin-bottom 4.8.
pw.Widget _metaGrid(List<(String, String)> items,
    {required int columns, required double lineHeight}) {
  final colW = (_cardContentW - _gridColGap * (columns - 1)) / columns;

  pw.Widget item((String, String) m) => pw.SizedBox(
        width: colW,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            cssText(
              m.$1,
              sizePt: _metaSizePt,
              weight: 600,
              letterSpacingEm: _semiboldTrack,
              color: ReportPdfTheme.muted,
              lineHeight: lineHeight,
              softWrap: false,
            ),
            pw.SizedBox(width: 4.2), // margin-right 0.35rem
            pw.Expanded(
              child: cssText(
                m.$2,
                sizePt: _metaSizePt,
                weight: 600,
                letterSpacingEm: _semiboldTrack,
                lineHeight: lineHeight,
              ),
            ),
          ],
        ),
      );

  final rows = <pw.Widget>[];
  for (var start = 0; start < items.length; start += columns) {
    final cells = <pw.Widget>[];
    for (var i = 0; i < columns; i++) {
      if (i > 0) cells.add(pw.SizedBox(width: _gridColGap));
      cells.add(start + i < items.length
          ? item(items[start + i])
          : pw.SizedBox(width: colW));
    }
    if (rows.isNotEmpty) rows.add(pw.SizedBox(height: _gridRowGap));
    rows.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start, children: cells));
  }
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: _gridRowGap),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: rows,
    ),
  );
}

/// `.evidenceGrid`: two columns (gap 9), fill #f9fafb, 0.75pt
/// #4b5563 border, radius 3, padding 6 x 9.
pw.Widget _evidenceGrid(
  List<ReportPhoto> beforeList,
  List<ReportPhoto> afterList,
  Map<String, Uint8List?> photos,
  double root,
) {
  pw.Widget column(String heading, List<ReportPhoto> list) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            cssText(
              heading,
              sizePt: 9.3, // 0.775rem
              weight: 700,
              letterSpacingEm: 0.02,
              color: ReportPdfTheme.muted,
              lineHeight: root,
            ),
            pw.SizedBox(height: 4.2), // margin-bottom 0.35rem
            _evidencePhotos(list, photos, root),
          ],
        ),
      );

  return CssBox.bordered(
    // margin-top 0.35rem (4.2) collapses with the heading's margin-bottom 4.8.
    padding: const pw.EdgeInsets.symmetric(vertical: 6.0, horizontal: 9.0),
    side: const CssSide(0.75, ReportPdfTheme.borderPrint),
    radius: 3.0,
    background: ReportPdfTheme.surface,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        column('Before / Initial Condition', beforeList),
        pw.SizedBox(width: _evidenceGap),
        column('After / Rectification Result', afterList),
      ],
    ),
  );
}

pw.Widget _evidencePhotos(
  List<ReportPhoto> list,
  Map<String, Uint8List?> photos,
  double root,
) {
  if (list.isEmpty) {
    return cssText(
      'No photo uploaded',
      sizePt: 9.3,
      italic: true,
      color: ReportPdfTheme.faint,
      lineHeight: 1.8,
    );
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: photoGridLines(
      [for (final p in list) PhotoTile(photos[p.key])],
      _evidenceColW,
      gap: 6.0, // 0.5rem
      lineHeight: root,
    ),
  );
}

/// `ReportHeader` as printed for this report. Same metrics as the shared
/// `reportHeader` (pb 9, 1.5pt #1f4e79 rule, mb 12; h2 15pt, h3 12pt, meta 10.2pt,
/// title 13.2pt, subtitle 10.8pt) except the railway h2 is `#1e293b` in the
/// web print; the shared primitive has no colour parameter for it.
// TODO(primitives): drop this once reportHeader takes a railway colour.
pw.Widget _header(ComplaintJobWorkReport r, double root) {
  pw.Widget metaItem(String label, String value, pw.TextAlign align) =>
      cssRich(
        [CssSpan('$label: ', weight: 700), CssSpan(value)],
        sizePt: 10.2,
        lineHeight: root,
        align: align,
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
          r.org.railwayName,
          sizePt: 15.0,
          weight: 700,
          upper: true,
          lineHeight: 1.2,
          letterSpacingEm: 0.03,
          color: ReportPdfTheme.headingInk,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2.4),
        cssText(
          r.org.divisionName,
          sizePt: 12.0,
          weight: 600,
          lineHeight: 1.2,
          color: ReportPdfTheme.muted,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 1.8),
        cssText(
          r.org.depotName,
          sizePt: 12.0,
          weight: 600,
          lineHeight: 1.2,
          color: ReportPdfTheme.muted,
          align: pw.TextAlign.center,
        ),
        // depot mb 1.8 collapses with the meta row's margin 6.
        pw.SizedBox(height: 6.0),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
                child: metaItem('Location', r.station, pw.TextAlign.left)),
            pw.SizedBox(width: 9.0),
            pw.Expanded(
                child: metaItem('Date', r.dateLabel, pw.TextAlign.right)),
          ],
        ),
        pw.SizedBox(height: 6.0),
        cssText(
          r.title,
          sizePt: 13.2,
          weight: 700,
          upper: true,
          lineHeight: 1.2,
          color: ReportPdfTheme.accent,
          letterSpacingEm: 0.05,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 3.0),
        cssText(
          'Ticket #${r.ticket}',
          sizePt: 10.8,
          weight: 600,
          lineHeight: root,
          align: pw.TextAlign.center,
        ),
      ],
    ),
  );
}
