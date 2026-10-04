import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

List<pw.Widget> buildInspectionReportPdf(
    InspectionJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  return [
    letterhead(r.org, r.title, meta: [
      ('Location', r.station),
      ('Date', r.dateLabel),
    ], subtitle: 'Ticket #${r.ticket}'),
    if (r.inspectionTitle.isNotEmpty) ...[
      sectionHeading('Inspection Title'),
      pdfText(r.inspectionTitle, size: 10),
    ],
    pw.SizedBox(height: 4),
    kvGrid([
      ('Inspection No.', r.inspectionNumber),
      ('Inspector', r.inspector),
    ]),
    if (r.inspectionRemarks.isNotEmpty) ...[
      sectionHeading('Inspection Remarks'),
      textBox(r.inspectionRemarks),
    ],
    if (r.generalEvidencePhotos.isNotEmpty) ...[
      subHeading('General Evidence Photos'),
      photoRow(r.generalEvidencePhotos, photos, '', captions: true),
    ],
    for (final p in r.points) ..._inspectionPoint(r, p, photos),
    signOff(
      technician: r.submission?.submittedByName.isNotEmpty == true
          ? r.submission!.submittedByName
          : r.technician,
      verification: r.verification,
      submission: r.submission,
      generatedAt: at,
    ),
  ];
}

List<pw.Widget> _inspectionPoint(InspectionJobWorkReport r,
    InspectionReportPoint p, Map<String, Uint8List?> photos) {
  final observationOnly = p.correctiveActionPerformed == false;
  final tag = [
    p.assetName.isEmpty ? 'N/A' : p.assetName,
    p.priority.isEmpty ? 'N/A' : p.priority,
  ].join(' · ');
  return [
    pw.SizedBox(height: 8),
    if (!p.isLegacy)
      pw.Container(
        width: double.infinity,
        color: PdfColors.grey300,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pdfText(
                  'Point #${p.pointNumber}: ${p.observation}'.trim(),
                  size: 9.5,
                  bold: true),
            ),
            if (tag.isNotEmpty) pdfText(tag, size: 8.5),
          ],
        ),
      )
    else ...[
      sectionHeading('TECHNICIAN EXECUTION'),
      if (r.coveredPoints.isNotEmpty) ...[
        subHeading('Inspection Points Covered'),
        for (final c in r.coveredPoints)
          pdfText(
              '#${c.number}: ${c.text}'
              '${c.priority.isEmpty ? '' : ' (${c.priority})'}',
              size: 8.5),
      ],
    ],
    subHeading('Initial Findings'),
    textBox(p.initialFindings),
    subHeading('Action Taken'),
    textBox(p.actionTaken),
    subHeading('Final Remarks'),
    textBox(p.finalRemarks),
    if (p.technicalParameters.isNotEmpty) ...[
      subHeading('Technical Parameters'),
      paramTable(p.technicalParameters),
    ],
    if (!p.isLegacy) ...[
      subHeading('Before Photos (From Inspection)'),
      photoRow(p.inspectionEvidencePhotos, photos, 'None', captions: true),
    ],
    subHeading('Before Photos'),
    photoRow(p.beforePhotos, photos, 'None uploaded', captions: true),
    subHeading('After Photos'),
    if (observationOnly)
      pdfText('Observation only — no corrective action required',
          size: 8.5, color: PdfColors.grey700),
    photoRow(p.afterPhotos, photos,
        observationOnly ? 'Not applicable' : 'None uploaded',
        captions: true),
  ];
}
