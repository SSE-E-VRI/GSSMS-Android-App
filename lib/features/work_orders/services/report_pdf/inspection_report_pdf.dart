import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

List<pw.Widget> buildInspectionReportPdf(
    InspectionJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  // Split points: all but last render freely; last is kept together with signOff.
  final allPoints = r.points;
  final leadingPoints =
      allPoints.length > 1 ? allPoints.sublist(0, allPoints.length - 1) : <InspectionReportPoint>[];
  final lastPoint = allPoints.isNotEmpty ? allPoints.last : null;

  return [
    letterhead(r.org, r.title, meta: [
      ('Location', r.station),
      ('Date', r.dateLabel),
    ], subtitle: 'Ticket #${r.ticket}'),

    // Inspection Title (only when present)
    if (r.inspectionTitle.isNotEmpty) ...[
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            cssText('Inspection Title',
                sizePx: 11.5, weight: 600, color: ReportPdfTheme.muted),
            pw.SizedBox(height: 1),
            cssText(r.inspectionTitle, sizePx: 12.0, weight: 700),
          ],
        ),
      ),
    ],

    // Inspection No. / Inspector 2-cell header grid (stacked label+value per cell)
    pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: ReportPdfTheme.border, width: 0.75),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                cssText('Inspection No.',
                    sizePx: 14.0, color: ReportPdfTheme.muted),
                pw.SizedBox(height: 1),
                cssText(r.inspectionNumber.isEmpty ? 'N/A' : r.inspectionNumber,
                    sizePx: 16.0, weight: 600),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                cssText('Inspector',
                    sizePx: 14.0, color: ReportPdfTheme.muted),
                pw.SizedBox(height: 1),
                cssText(r.inspector.isEmpty ? 'N/A' : r.inspector,
                    sizePx: 16.0, weight: 600),
              ],
            ),
          ),
        ],
      ),
    ),

    // Inspection Remarks (only when present)
    if (r.inspectionRemarks.isNotEmpty) ...[
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            cssText('Inspection Remarks',
                sizePx: 14.0, weight: 700, color: ReportPdfTheme.muted),
            pw.SizedBox(height: 2),
            cssText(r.inspectionRemarks, sizePx: 16.0),
          ],
        ),
      ),
    ],

    // General Evidence Photos (only when present)
    if (r.generalEvidencePhotos.isNotEmpty) ...[
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 18),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            cssText('General Evidence Photos',
                sizePx: 14.0, weight: 700, color: ReportPdfTheme.muted),
            pw.SizedBox(height: 3),
            photoRow(r.generalEvidencePhotos, photos, 'None', captions: true),
          ],
        ),
      ),
    ],

    // Leading points (all but last) — no keep-together with signOff
    for (final p in leadingPoints) ...[
      ..._inspectionPoint(r, p, photos),
      pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 18),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: ReportPdfTheme.border, width: 0.75),
          ),
        ),
      ),
    ],

    // Last point + signOff kept together to avoid orphan signoff
    if (lastPoint != null)
      keepTogether([
        ..._inspectionPoint(r, lastPoint, photos),
        pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(bottom: 18),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: ReportPdfTheme.border, width: 0.75),
            ),
          ),
        ),
        signOff(
          technician: r.submission?.submittedByName.isNotEmpty == true
              ? r.submission!.submittedByName
              : r.technician,
          verification: r.verification,
          submission: r.submission,
          generatedAt: at,
        ),
      ])
    else
      signOff(
        technician: r.technician,
        verification: r.verification,
        submission: r.submission,
        generatedAt: at,
      ),
  ];
}

List<pw.Widget> _inspectionPoint(InspectionJobWorkReport r,
    InspectionReportPoint p, Map<String, Uint8List?> photos) {
  final observationOnly = p.correctiveActionPerformed == false;
  final tag =
      '${p.assetName.isEmpty ? 'N/A' : p.assetName} \u00B7 ${p.priority.isEmpty ? 'N/A' : p.priority}';

  return [
    // Point header
    if (!p.isLegacy)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: cssText(
                  'Point #${p.pointNumber}: ${p.observation}'.trim(),
                  sizePx: 16.0,
                  weight: 700),
            ),
            pw.SizedBox(width: 6),
            statusBadge('neutral', tag),
          ],
        ),
      )
    else ...[
      sectionHeading('TECHNICIAN EXECUTION'),
      if (r.coveredPoints.isNotEmpty) ...[
        subHeading('Inspection Points Covered'),
        for (final c in r.coveredPoints)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 1),
            child: cssText(
                '#${c.number}: ${c.text}'
                '${c.priority.isEmpty ? '' : ' (${c.priority})'}',
                sizePx: 14.0),
          ),
        pw.SizedBox(height: 4),
      ],
    ],

    // 3-column fields grid: Initial Findings / Action Taken / Final Remarks
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _fieldColumn('Initial Findings', p.initialFindings)),
          pw.SizedBox(width: 12),
          pw.Expanded(child: _fieldColumn('Action Taken', p.actionTaken)),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _fieldColumn(
              'Final Remarks',
              p.finalRemarks,
            ),
          ),
        ],
      ),
    ),

    // Technical Parameters
    if (p.technicalParameters.isNotEmpty) ...[
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            cssText('Technical Parameters',
                sizePx: 14.0, weight: 700, color: ReportPdfTheme.muted),
            pw.SizedBox(height: 3),
            paramTable(p.technicalParameters),
          ],
        ),
      ),
    ],

    // Photo grid: 3-column (pointwise) or 2-column (legacy)
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // "Before Photos (From Inspection)" column — pointwise only
          if (!p.isLegacy) ...[
            pw.Expanded(
              child: _photoColumn(
                  'Before Photos (From Inspection)',
                  p.inspectionEvidencePhotos,
                  photos,
                  'None'),
            ),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: _photoColumn(
                'Before Photos', p.beforePhotos, photos, 'None uploaded'),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _photoColumn(
              'After Photos',
              p.afterPhotos,
              photos,
              observationOnly ? 'Not applicable' : 'None uploaded',
              observationOnlyNote: observationOnly,
            ),
          ),
        ],
      ),
    ),
  ];
}

/// Small muted bold label above content — matches web `<Field>` component.
pw.Widget _fieldColumn(
  String label,
  String value, {
  bool observationOnlyNote = false,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      cssText(label, sizePx: 14.0, weight: 700, color: ReportPdfTheme.muted),
      pw.SizedBox(height: 2),
      if (observationOnlyNote)
        cssText('Observation only \u2014 no corrective action required',
            sizePx: 14.0, italic: true, color: ReportPdfTheme.muted),
      if (value.trim().isNotEmpty)
        cssText(value, sizePx: 16.0)
      else
        cssText('None recorded',
            sizePx: 16.0, italic: true, color: ReportPdfTheme.faint),
    ],
  );
}

/// Small muted bold label above a PhotoGrid — matches web photo sub-headers.
pw.Widget _photoColumn(
  String label,
  List<ReportPhoto> list,
  Map<String, Uint8List?> photos,
  String emptyLabel, {
  bool observationOnlyNote = false,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      cssText(label, sizePx: 14.0, weight: 700, color: ReportPdfTheme.muted),
      pw.SizedBox(height: 3),
      if (observationOnlyNote) ...[
        cssText('Observation only \u2014 no corrective action required',
            sizePx: 14.0, italic: true, color: ReportPdfTheme.muted),
        pw.SizedBox(height: 3),
      ],
      photoRow(list, photos, emptyLabel, captions: true),
    ],
  );
}
