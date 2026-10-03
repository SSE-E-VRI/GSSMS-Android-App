import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

List<pw.Widget> buildComplaintReportPdf(
    ComplaintJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  final List<pw.Widget> section1;
  switch (r.section1Kind) {
    case ComplaintSection1Kind.deficiency:
      final d = r.deficiencyDetails!;
      section1 = [
        sectionHeading('1. Deficiency Details'),
        kvGrid([
          ('Found in', d.sourceTicket),
          ('Severity', d.severity),
          ('Target date', d.targetDate),
          ('Asset / Equipment', d.equipment),
          ('Checkpoint', d.checkpoint),
        ]),
        subHeading('Finding'),
        textBox(d.finding, empty: 'No finding recorded'),
      ];
    case ComplaintSection1Kind.complaint:
      final c = r.complaintDetails!;
      section1 = [
        sectionHeading('1. Breakdown Information'),
        kvGrid([
          ('Breakdown No', c.complaintNumber),
          ('Failure Date & Time', c.failureDateTime),
          ('Complainant', c.complainant),
          ('Reported Asset', c.reportedAsset),
        ]),
        subHeading('Original Description'),
        textBox(c.description, empty: 'None recorded'),
      ];
    case ComplaintSection1Kind.jobWork:
      section1 = [
        sectionHeading('1. Job Work Details'),
        kvGrid([
          ('Location', r.station),
          ('Asset / Equipment', r.assetName),
        ]),
        subHeading('Work to be done'),
        textBox(r.workToBeDone, empty: 'None recorded'),
      ];
  }
  return [
    letterhead(r.org, r.title, meta: [
      ('Location', r.station),
      ('Date', r.dateLabel),
    ], subtitle: 'Ticket #${r.ticket}'),
    ...section1,
    sectionHeading('Initial Assessment & Findings'),
    textBox(r.initialFindings),
    sectionHeading('Rectification / Action Taken'),
    textBox(r.actionTaken),
    if (r.parameters.isNotEmpty) ...[
      sectionHeading('Technical Parameters'),
      paramTable(r.parameters),
    ],
    sectionHeading('Photo Evidence'),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              subHeading('Before / Initial Condition'),
              photoRow(r.beforePhotos, photos, 'No photo uploaded'),
            ],
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              subHeading('After / Rectification Result'),
              photoRow(r.afterPhotos, photos, 'No photo uploaded'),
            ],
          ),
        ),
      ],
    ),
    sectionHeading('Final Remarks'),
    textBox(r.finalRemarks),
    signOff(
      technician: r.submitter,
      verification: r.verification,
      submission: r.submission,
      generatedAt: at,
    ),
  ];
}
