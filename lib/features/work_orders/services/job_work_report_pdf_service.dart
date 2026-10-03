import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

/// Builds the printable Job Work report (technician "Report Preview") for the
/// four Job Work kinds. Mirrors the web FormPreview,
/// ComplaintExecutionPrintPreview, InspectionReportPreview and
/// RectificationReportPreview sections and labels.
class JobWorkReportPdfService {
  const JobWorkReportPdfService._();

  static Future<pw.Document> build(
    JobWorkReport r, {
    Map<String, Uint8List?> photos = const {},
    DateTime? generatedAt,
  }) async {
    final at = generatedAt ?? DateTime.now();
    final List<pw.Widget> body = switch (r) {
      ChecklistJobWorkReport() => _checklist(r, photos, at),
      ComplaintJobWorkReport() => _complaint(r, photos, at),
      InspectionJobWorkReport() => _inspection(r, photos, at),
      RectificationJobWorkReport() => _rectification(r, photos, at),
    };
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        // Letterhead is the first content block (page 1 only), not `header`.
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pdfText('Generated: ${formatReportDateTime(at)}',
                size: 8, color: PdfColors.grey700),
            pdfText('Page ${context.pageNumber} of ${context.pagesCount}',
                size: 8, color: PdfColors.grey700),
          ],
        ),
        build: (context) => body,
      ),
    );
    return doc;
  }

  // -------------------------------------------------------------------------
  // Checklist
  // -------------------------------------------------------------------------

  static const _checklistWidths = <int, pw.TableColumnWidth>{
    0: pw.FlexColumnWidth(22),
    1: pw.FlexColumnWidth(38),
    2: pw.FlexColumnWidth(16),
    3: pw.FlexColumnWidth(24),
  };

  static List<pw.Widget> _checklist(
      ChecklistJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
    return [
      letterhead(r.org, r.title, meta: [
        ('Location', r.station),
        ('Schedule', r.schedule),
        ('Job Work', r.ticket),
        ('Date', r.dateLabel),
      ]),
      if (r.isEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 12),
          child: pdfText('No details available.'),
        ),
      for (final g in r.groups) ...[
        pw.Container(
          width: double.infinity,
          color: PdfColors.grey300,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pdfText(g.name, size: 9.5, bold: true),
        ),
        _groupTable(g, photos),
        pw.SizedBox(height: 12),
      ],
      sectionHeading('Deficiency Summary (${r.deficiencies.length})'),
      simpleTable(
        const [
          'Asset/Equipment',
          'Checkpoint',
          'Deficiency Finding',
          'Action Taken',
          'Severity'
        ],
        r.deficiencies.isEmpty
            ? [
                ['No deficiencies selected.', '', '', '', '']
              ]
            : [
                for (final d in r.deficiencies)
                  [d.asset, d.checkpoint, d.finding, d.action, d.severity],
              ],
      ),
      pw.SizedBox(height: 10),
      pw.Column(children: [
        sectionHeading('Additional Details'),
        textBox(
          r.remarks.isEmpty ? '' : 'Technician Remarks: ${r.remarks}',
          empty: 'Technician Remarks: No remarks recorded.',
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

  static pw.Widget _groupTable(
      ChecklistReportGroup g, Map<String, Uint8List?> photos) {
    final rows = g.rows;
    var itemStart = 0;
    var itemLen = 1;
    var paramStart = 0;
    var paramLen = 0;
    final out = <pw.TableRow>[
      pw.TableRow(children: [
        tableHeaderCell('Asset/Equipment'),
        tableHeaderCell('Checkpoint/Parameter'),
        tableHeaderCell('Status'),
        tableHeaderCell('Action Taken'),
      ]),
    ];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.itemSpanStart) {
        itemStart = i;
        itemLen = row.itemSpanLen;
      }
      if (row.paramSpanStart) {
        paramStart = i;
        paramLen = row.paramSpanLen;
      }
      final String name = row.itemName.isEmpty ? g.name : row.itemName;

      final pw.Widget checkpoint;
      final pw.Widget status;
      final pw.Widget action;
      if (row.isRecordParameter) {
        checkpoint = spanCell(
            indexInSpan: i - paramStart,
            spanLen: paramLen,
            label: 'Record Parameters');
        status = tableBodyCell(row.checkpoint);
        action = tableBodyCell(
          row.hasValue
              ? '${row.formattedValue}${row.unit.isEmpty ? '' : ' (${row.unit})'}'
              : '--',
        );
      } else {
        checkpoint = pw.Container(
          decoration: pw.BoxDecoration(border: cellBorder()),
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pdfText(row.checkpoint, size: 8.5),
              if (row.attachments.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                photoRow(row.attachments, photos, '',
                    width: 60, height: 45, captions: true),
              ],
            ],
          ),
        );
        status = tableBodyCell(row.statusLabel);
        action = tableBodyCell(row.actionDisplay);
      }
      out.add(pw.TableRow(children: [
        spanCell(indexInSpan: i - itemStart, spanLen: itemLen, label: name),
        checkpoint,
        status,
        action,
      ]));
    }
    return pw.Table(columnWidths: _checklistWidths, children: out);
  }

  // -------------------------------------------------------------------------
  // Breakdown (complaint)
  // -------------------------------------------------------------------------

  static List<pw.Widget> _complaint(
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

  // -------------------------------------------------------------------------
  // Inspection
  // -------------------------------------------------------------------------

  static List<pw.Widget> _inspection(
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
        sectionHeading('General Evidence Photos'),
        photoRow(r.generalEvidencePhotos, photos, ''),
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

  static List<pw.Widget> _inspectionPoint(InspectionJobWorkReport r,
      InspectionReportPoint p, Map<String, Uint8List?> photos) {
    final observationOnly = p.correctiveActionPerformed == false;
    final tag = [p.assetName, p.priority].where((s) => s.isNotEmpty).join(' | ');
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
                '${c.number}. ${c.text}'
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
        photoRow(p.inspectionEvidencePhotos, photos, 'None'),
      ],
      subHeading('Before Photos'),
      photoRow(p.beforePhotos, photos, 'None uploaded'),
      subHeading('After Photos'),
      if (observationOnly)
        pdfText('Observation only - no corrective action required',
            size: 8.5, color: PdfColors.grey700),
      photoRow(p.afterPhotos, photos,
          observationOnly ? 'Not applicable' : 'None uploaded'),
    ];
  }

  // -------------------------------------------------------------------------
  // Rectification
  // -------------------------------------------------------------------------

  static List<pw.Widget> _rectification(RectificationJobWorkReport r,
      Map<String, Uint8List?> photos, DateTime at) {
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
          ('Checkpoint', r.items[i].checkpoint.isEmpty
              ? 'N/A'
              : r.items[i].checkpoint),
          ('Severity', r.items[i].severity),
        ]),
        subHeading('Finding'),
        textBox(r.items[i].finding, empty: 'No finding recorded'),
        subHeading('Action Taken'),
        textBox(r.items[i].actionTaken, empty: 'No action recorded'),
        if (r.items[i].outcome == RectificationOutcome.notRectified) ...[
          subHeading('Reason it could not be rectified'),
          textBox(r.items[i].reason, empty: 'No reason recorded'),
        ],
        subHeading('Before Evidence'),
        photoRow(r.items[i].beforePhotos, photos, 'No before photo'),
        subHeading('After Evidence'),
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
}
