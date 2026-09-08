import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';

/// Printable Job Work sheet for one work order — mirrors web's per-row PDF
/// action on Job Works (Manage/Audit/PDF): header meta + asset/location +
/// assignment + remarks + status history. Same letterhead/footer language as
/// [RegisterEntryPdfService] so all mobile PDFs read as one set.
class WorkOrderPdfService {
  const WorkOrderPdfService._();

  static Future<pw.Document> build(
    WorkOrder wo, {
    WorkOrderAudit? audit,
  }) async {
    final doc = pw.Document();
    final df = DateFormat('dd MMM yyyy, HH:mm');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
                'Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        ),
        build: (context) => [
          _header(wo),
          pw.SizedBox(height: 10),
          _metaTable(wo, df),
          pw.SizedBox(height: 12),
          if (wo.description != null && wo.description!.trim().isNotEmpty) ...[
            _sectionTitle('Remarks / Notes'),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(wo.description!,
                  style: const pw.TextStyle(fontSize: 9.5)),
            ),
            pw.SizedBox(height: 12),
          ],
          _sectionTitle(
              'History${audit != null && audit.returnCount > 0 ? '  (Returned ${audit.returnCount}x)' : ''}'),
          if (audit == null || audit.events.isEmpty)
            pw.Text(
              wo.latestEventSummary != null
                  ? '${wo.latestEventSummary!.eventType} — ${wo.latestEventSummary!.actor}'
                      '${wo.latestEventSummary!.remarks?.isNotEmpty ?? false ? ' (${wo.latestEventSummary!.remarks})' : ''}'
                  : 'No history events recorded.',
              style: const pw.TextStyle(fontSize: 9.5),
            )
          else
            _auditTable(audit, df),
        ],
      ),
    );
    return doc;
  }

  static pw.Widget _header(WorkOrder wo) {
    return pw.Container(
      width: double.infinity,
      alignment: pw.Alignment.center,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text('JOB WORK ${wo.displayReference}',
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(wo.displayTitle,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 4),
          pw.Text(
              'Status: ${wo.status.displayName}  |  Type: ${wo.type.displayName}  |  Priority: ${wo.priority.displayName}',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey700)),
          if (wo.isSlaAtRisk)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text('SLA ${wo.slaStatus ?? 'AT RISK'}',
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.red800)),
            ),
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 12, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _metaTable(WorkOrder wo, DateFormat df) {
    pw.TableRow row(String k, String v) => pw.TableRow(children: [
          pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: PdfColors.grey200,
              child: pw.Text(k,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold))),
          pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child:
                  pw.Text(v, style: const pw.TextStyle(fontSize: 9))),
        ]);
    String fmt(DateTime? d) => d == null ? '-' : df.format(d);
    return pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(130),
        1: pw.FlexColumnWidth(),
      },
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      children: [
        row('Ticket', wo.displayReference),
        row('Asset', wo.assetName ?? '-'),
        if (wo.assetCriticality != null)
          row('Criticality', wo.assetCriticality!),
        row('Station', wo.stationName ?? '-'),
        row('Depot', wo.depotName ?? '-'),
        if (wo.infrastructureName != null)
          row('Infrastructure',
              '${wo.infrastructureName} (${wo.infrastructureType ?? '-'})'),
        row('Assigned To', wo.assignedToName ?? 'Unassigned'),
        row('Reported By', wo.reportedByName ?? '-'),
        if (wo.verifiedByName != null)
          row('Verified By', wo.verifiedByName!),
        row('Due Date', fmt(wo.dueDate)),
        row('Created', fmt(wo.createdAt)),
        if (wo.reportCompletedAt != null)
          row('Tech Completed', fmt(wo.reportCompletedAt)),
      ],
    );
  }

  static pw.Widget _auditTable(WorkOrderAudit audit, DateFormat df) {
    pw.Widget h(String t) => pw.Container(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: pw.Text(t,
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                  color: PdfColors.white)),
        );
    pw.Widget c(String t) => pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(t, style: const pw.TextStyle(fontSize: 8.5)),
        );
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(2.2),
        1: pw.FlexColumnWidth(2.0),
        2: pw.FlexColumnWidth(2.6),
        3: pw.FlexColumnWidth(2.4),
      },
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      children: [
        pw.TableRow(children: [
          h('Date'),
          h('Event'),
          h('Actor'),
          h('Remarks'),
        ]),
        for (final e in audit.eventsNewestFirst)
          pw.TableRow(children: [
            c(e.timestamp == null ? '-' : df.format(e.timestamp!)),
            c([
              if ((e.fromState ?? '').isNotEmpty ||
                  (e.toState ?? '').isNotEmpty)
                '${e.fromState ?? '-'} -> ${e.toState ?? '-'}'
              else
                e.eventType,
              if (e.isReturn) ' (return)',
            ].join()),
            c([
              if ((e.actor ?? '').isNotEmpty) e.actor!,
              if ((e.actorRole ?? '').isNotEmpty) ' (${e.actorRole})',
            ].join()),
            c((e.reason ?? '').isEmpty ? '-' : e.reason!),
          ]),
      ],
    );
  }
}
