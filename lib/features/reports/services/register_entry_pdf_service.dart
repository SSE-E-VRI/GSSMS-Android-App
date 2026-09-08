import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/reports/domain/models/maintenance_register_entry.dart';

/// Builds the printable checklist certificate for one register entry.
///
/// Mirrors the web register's own print layout (FormPreview.jsx / the
/// browser-printed "Job Work ... Verification" report) rather than inventing
/// a third: the same railway/division/depot letterhead on page 1 only, the
/// same Location/Schedule/Job Work/Date meta row, one table per
/// Asset/Equipment with columns Asset/Equipment | Checkpoint/Parameter |
/// Status | Action Taken — the Asset/Equipment cell merged and centred down
/// the whole group, same as the web table's `rowSpan` cell — and a recorded
/// reading (e.g. Voltage/Current) folded into the Status column instead of a
/// mostly-empty separate "Recorded Value" column.
class RegisterEntryPdfService {
  const RegisterEntryPdfService._();

  static Future<pw.Document> build(MaintenanceRegisterEntry entry) async {
    final doc = pw.Document();
    final dateStr = entry.date != null
        ? DateFormat('dd MMM yyyy').format(entry.date!)
        : 'N/A';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        // Letterhead only belongs on page 1 (matches the web print layout) —
        // MultiPage's `header` repeats on every page, so it is rendered as
        // the first content block below instead of via that callback.
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
          _buildLetterhead(entry, dateStr),
          for (final group in entry.groupedByAsset) ...[
            _buildAssetGroupTable(group),
            pw.SizedBox(height: 14),
          ],
          if (entry.items.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 12),
              child: pw.Text('No recorded line items found for this entry.'),
            ),
          pw.SizedBox(height: 8),
          _buildAdditionalDetails(entry),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Technician: ${entry.technician ?? 'N/A'}'),
              pw.Text('Supervisor: ${entry.supervisor ?? 'N/A'}'),
            ],
          ),
        ],
      ),
    );

    return doc;
  }

  /// A recorded reading (value present, no action against it —
  /// [RegisterLineItem.isRecordedParameter]) puts the reading itself in the
  /// Status column, the way FormPreview folds Voltage/Current readings into
  /// a single cell instead of a separate value column; a checkpoint keeps its
  /// pass/fail status instead.
  static String _statusCellFor(RegisterLineItem item) {
    return item.isRecordedParameter
        ? item.value!
        : (item.statusLabel ?? item.status ?? '-');
  }

  /// Action Taken cell. Any observation-action remark that survives on the
  /// row rides along here rather than a column of its own, since it is
  /// almost always empty.
  static String _actionCellFor(RegisterLineItem item) {
    if (item.isRecordedParameter) return '';

    final action = item.action?.trim();
    final hasAction = action != null && action.isNotEmpty && action != '-';
    var actionCell = hasAction ? action : '-';

    final remarks = item.remarks?.trim();
    final hasRemarks = remarks != null && remarks.isNotEmpty && remarks != '-';
    if (hasRemarks && remarks != actionCell) {
      actionCell = actionCell == '-' ? remarks : '$actionCell ($remarks)';
    }
    return actionCell;
  }

  static const _borderColor = PdfColors.grey400;
  static const _borderSide = pw.BorderSide(color: _borderColor, width: 0.5);
  static const _columnWidths = <int, pw.TableColumnWidth>{
    0: pw.FixedColumnWidth(108),
    1: pw.FlexColumnWidth(3.4), // Checkpoint/Parameter
    2: pw.FlexColumnWidth(2.4), // Status
    3: pw.FlexColumnWidth(2.8), // Action Taken
  };

  static pw.Border _cellBorder({bool top = true, bool bottom = true}) =>
      pw.Border(
        top: top ? _borderSide : pw.BorderSide.none,
        bottom: bottom ? _borderSide : pw.BorderSide.none,
        left: _borderSide,
        right: _borderSide,
      );

  /// One asset group's table, with the Asset/Equipment column merged and
  /// centred across every row in the group — matching the web table's
  /// `rowSpan` cell — rather than repeating the asset name on every row.
  /// `pw.Table` has no native rowSpan, so this is a plain table (the only
  /// widget shape that can genuinely split across pages inside `MultiPage`)
  /// where the asset column's own top/bottom borders are only drawn on the
  /// group's first/last row, and the name is placed once on the middle row —
  /// giving the same unbroken, centred box without a nested Row/Expanded
  /// layout that MultiPage can't paginate.
  static pw.Widget _buildAssetGroupTable(AssetChecklistGroup group) {
    final items = group.items;
    final labelRowIndex = items.isEmpty ? 0 : (items.length - 1) ~/ 2;

    pw.Widget headerCell(String text) => pw.Container(
          decoration: pw.BoxDecoration(
              color: PdfColors.blueGrey800, border: _cellBorder()),
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: pw.Text(
            text,
            style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
                color: PdfColors.white),
          ),
        );

    pw.Widget bodyCell(String text) => pw.Container(
          decoration: pw.BoxDecoration(border: _cellBorder()),
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(text, style: const pw.TextStyle(fontSize: 8.5)),
        );

    pw.Widget assetCell(int index) => pw.Container(
          decoration: pw.BoxDecoration(
            border:
                _cellBorder(top: index == 0, bottom: index == items.length - 1),
          ),
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: index == labelRowIndex
              ? pw.Text(
                  group.assetName,
                  textAlign: pw.TextAlign.center,
                  style:
                      pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                )
              : pw.SizedBox(),
        );

    return pw.Table(
      columnWidths: _columnWidths,
      children: [
        pw.TableRow(children: [
          headerCell('Asset/Equipment'),
          headerCell('Checkpoint/Parameter'),
          headerCell('Status'),
          headerCell('Action Taken'),
        ]),
        for (var i = 0; i < items.length; i++)
          pw.TableRow(children: [
            assetCell(i),
            bodyCell(items[i].inspection),
            bodyCell(_statusCellFor(items[i])),
            bodyCell(_actionCellFor(items[i])),
          ]),
      ],
    );
  }

  static pw.Widget _buildLetterhead(
      MaintenanceRegisterEntry entry, String dateStr) {
    final letterheadLines = [
      entry.railwayName,
      entry.divisionName,
      entry.depotName
    ].where((s) => s != null && s.trim().isNotEmpty).cast<String>().toList();

    pw.Widget metaRow(String label, String? value) {
      if (value == null || value.trim().isEmpty) return pw.SizedBox.shrink();
      return pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.black),
          children: [
            pw.TextSpan(
                text: '$label: ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: value),
          ],
        ),
      );
    }

    // MultiPage lays its top-level `build()` items out with
    // CrossAxisAlignment.start, so an inner Column's own "center" only
    // centres its children within its own shrink-wrapped width — not the
    // page. Wrapping in a full-width Container (alignment: center) is what
    // actually centres the block against the page margins.
    return pw.Container(
      width: double.infinity,
      alignment: pw.Alignment.center,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (letterheadLines.isNotEmpty) ...[
            for (var i = 0; i < letterheadLines.length; i++)
              pw.Text(
                i == 0 ? letterheadLines[i].toUpperCase() : letterheadLines[i],
                style: pw.TextStyle(
                  fontSize: i == 0 ? 15 : 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            pw.SizedBox(height: 6),
          ] else ...[
            pw.Text(entry.masterName,
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (entry.registerTitle != null) pw.Text(entry.registerTitle!),
            pw.SizedBox(height: 6),
          ],
          pw.Wrap(
            alignment: pw.WrapAlignment.center,
            runAlignment: pw.WrapAlignment.center,
            crossAxisAlignment: pw.WrapCrossAlignment.center,
            spacing: 18,
            runSpacing: 4,
            children: [
              metaRow('Location', entry.stationName ?? entry.depotName),
              metaRow('Schedule', entry.registerTitle ?? entry.masterName),
              metaRow('Job Work', entry.masterName),
              metaRow('Date', dateStr),
            ],
          ),
          pw.SizedBox(height: 12),
        ],
      ),
    );
  }

  static pw.Widget _buildAdditionalDetails(MaintenanceRegisterEntry entry) {
    final remarks = entry.remarks?.trim();
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Technician Remarks',
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 3),
          pw.Text(
            remarks != null && remarks.isNotEmpty
                ? remarks
                : 'No remarks recorded.',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}
