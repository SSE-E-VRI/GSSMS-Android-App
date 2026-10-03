import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

const _checklistWidths = <int, pw.TableColumnWidth>{
  0: pw.FlexColumnWidth(22),
  1: pw.FlexColumnWidth(38),
  2: pw.FlexColumnWidth(16),
  3: pw.FlexColumnWidth(24),
};

List<pw.Widget> buildChecklistReportPdf(
    ChecklistJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  return [
    letterhead(r.org, r.title, meta: [
      ('Location', r.station),
      ('Schedule', r.schedule),
      if (r.showJobWork) ('Job Work', r.ticket),
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

pw.Widget _groupTable(
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
