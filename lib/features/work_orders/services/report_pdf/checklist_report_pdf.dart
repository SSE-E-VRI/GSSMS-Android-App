import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

// Border color matching web table: #4b5563 (0.294, 0.333, 0.388)
const _tableBorderColor = PdfColor(0.2941, 0.3333, 0.3882);
const _tableBorderSide = pw.BorderSide(color: _tableBorderColor, width: 0.75);

// Card border color: #d1d5db (0.820, 0.835, 0.859)
const _cardBorderColor = PdfColor(0.8196, 0.8353, 0.8588);

// Header background tint: #e8eef5 (0.910, 0.933, 0.961)
const _headerTint = PdfColor(0.9098, 0.9333, 0.9608);

// Deficiency colors
const _deficiencyDarkRed = PdfColor(0.4980, 0.1137, 0.1137); // #7f1d1d
const _deficiencyYellowBar = PdfColor(1.0, 0.7569, 0.0275); // #ffc107

pw.Widget _pad(pw.Widget child) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14.4),
      child: child,
    );

List<pw.Widget> buildChecklistReportPdf(
    ChecklistJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  return [
    _pad(_buildChecklistHeader(r)),
    _pad(_buildChecklistMeta(r)),
    if (r.isEmpty)
      _pad(pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        child: cssText('No details available.', sizePx: 13.0),
      )),
    for (final g in r.groups) ...[
      ..._buildAssetGroup(g),
    ],
    _pad(_buildDeficiencySummary(r.deficiencies)),
    _pad(_buildAdditionalDetailsAndSignOff(r, at)),
  ];
}

pw.Widget _buildChecklistHeader(ChecklistJobWorkReport r) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.only(bottom: 9.0),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: ReportPdfTheme.accent, width: 1.5),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        cssText(
          r.org.railwayName,
          sizePx: 20.0,
          weight: 700,
          upper: true,
          letterSpacingEm: 0.03,
          color: ReportPdfTheme.inkPrint,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2.4),
        cssText(
          r.org.divisionName,
          sizePx: 16.0,
          weight: 600,
          color: ReportPdfTheme.inkPrint,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 1.8),
        cssText(
          r.org.depotName,
          sizePx: 16.0,
          weight: 600,
          color: ReportPdfTheme.inkPrint,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 3.0),
        cssText(
          r.title,
          sizePx: 17.6,
          weight: 700,
          upper: true,
          color: ReportPdfTheme.inkPrint,
          letterSpacingEm: 0.05,
          align: pw.TextAlign.center,
        ),
      ],
    ),
  );
}

pw.Widget _buildChecklistMeta(ChecklistJobWorkReport r) {
  final hasJobWork = r.showJobWork;
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 14.0, bottom: 20.0),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          flex: 1,
          child: pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(
                  text: 'Location: ',
                  style: pw.TextStyle(
                    font: ReportFonts.bold,
                    fontSize: 12.0,
                    color: ReportPdfTheme.inkPrint,
                  ),
                ),
                pw.TextSpan(
                  text: pdfSafe(r.station),
                  style: pw.TextStyle(
                    font: ReportFonts.regular,
                    fontSize: 12.0,
                    color: ReportPdfTheme.inkPrint,
                  ),
                ),
              ]),
            ),
          ),
        ),
        pw.Expanded(
          flex: 1,
          child: pw.Align(
            alignment: pw.Alignment.center,
            child: pw.RichText(
              textAlign: pw.TextAlign.center,
              text: pw.TextSpan(children: [
                pw.TextSpan(
                  text: 'Schedule: ',
                  style: pw.TextStyle(
                    font: ReportFonts.bold,
                    fontSize: 12.0,
                    color: ReportPdfTheme.inkPrint,
                  ),
                ),
                pw.TextSpan(
                  text: pdfSafe(r.schedule),
                  style: pw.TextStyle(
                    font: ReportFonts.regular,
                    fontSize: 12.0,
                    color: ReportPdfTheme.inkPrint,
                  ),
                ),
              ]),
            ),
          ),
        ),
        if (hasJobWork)
          pw.Expanded(
            flex: 1,
            child: pw.Align(
              alignment: pw.Alignment.center,
              child: pw.RichText(
                textAlign: pw.TextAlign.center,
                text: pw.TextSpan(children: [
                  pw.TextSpan(
                    text: 'Job Work: ',
                    style: pw.TextStyle(
                      font: ReportFonts.bold,
                      fontSize: 12.0,
                      color: ReportPdfTheme.inkPrint,
                    ),
                  ),
                  pw.TextSpan(
                    text: pdfSafe(r.ticket),
                    style: pw.TextStyle(
                      font: ReportFonts.regular,
                      fontSize: 12.0,
                      color: ReportPdfTheme.inkPrint,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        pw.Expanded(
          flex: 1,
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.RichText(
              textAlign: pw.TextAlign.right,
              text: pw.TextSpan(children: [
                pw.TextSpan(
                  text: 'Date: ',
                  style: pw.TextStyle(
                    font: ReportFonts.bold,
                    fontSize: 12.0,
                    color: ReportPdfTheme.inkPrint,
                  ),
                ),
                pw.TextSpan(
                  text: pdfSafe(r.dateLabel),
                  style: pw.TextStyle(
                    font: ReportFonts.regular,
                    fontSize: 12.0,
                    color: ReportPdfTheme.inkPrint,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ],
    ),
  );
}

List<pw.Widget> _buildAssetGroup(ChecklistReportGroup g) {
  final headerBox = pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(bottom: 7.0),
    padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.5),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      border: pw.Border.all(color: _cardBorderColor, width: 0.75),
    ),
    child: cssText(
      g.name,
      sizePx: 20.0,
      weight: 700,
      color: ReportPdfTheme.inkPrint,
    ),
  );

  if (g.rows.length > 20) {
    return [
      pw.NewPage(),
      _pad(headerBox),
      ..._buildGroupNestedTable(g),
      pw.SizedBox(height: 22.0),
    ];
  }

  return [
    AvoidBreakInside(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _pad(headerBox),
          ..._buildGroupNestedTable(g),
          pw.SizedBox(height: 22.0),
        ],
      ),
    ),
  ];
}

List<pw.Widget> _buildGroupNestedTable(ChecklistReportGroup g) {
  final rows = g.rows;
  final itemSpans = <(int, int)>[];
  int i = 0;
  while (i < rows.length) {
    int start = i;
    int len = rows[i].itemSpanLen > 0 ? rows[i].itemSpanLen : 1;
    itemSpans.add((start, len));
    i += len;
  }

  return [
    // Table Header Row
    _pad(
      pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(22),
          1: pw.FlexColumnWidth(38),
          2: pw.FlexColumnWidth(16),
          3: pw.FlexColumnWidth(24),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _headerTint),
            children: [
              _cell(
                cssText('Asset/Equipment', sizePx: 13.0, weight: 700),
                border: const pw.Border(
                  top: _tableBorderSide,
                  bottom: _tableBorderSide,
                  left: _tableBorderSide,
                  right: _tableBorderSide,
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
              ),
              _cell(
                cssText('Checkpoint/Parameter', sizePx: 13.0, weight: 700),
                border: const pw.Border(
                  top: _tableBorderSide,
                  bottom: _tableBorderSide,
                  right: _tableBorderSide,
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
              ),
              _cell(
                cssText('Status', sizePx: 13.0, weight: 700),
                border: const pw.Border(
                  top: _tableBorderSide,
                  bottom: _tableBorderSide,
                  right: _tableBorderSide,
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
              ),
              _cell(
                cssText('Action Taken', sizePx: 13.0, weight: 700),
                border: const pw.Border(
                  top: _tableBorderSide,
                  bottom: _tableBorderSide,
                  right: _tableBorderSide,
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
              ),
            ],
          ),
        ],
      ),
    ),
    // Item Span Rows
    for (final span in itemSpans)
      _pad(_buildItemSpanRow(g, rows.sublist(span.$1, span.$1 + span.$2))),
  ];
}

pw.Widget _buildItemSpanRow(ChecklistReportGroup g, List<ChecklistReportRow> spanRows) {
  final itemName = spanRows.first.itemName.isEmpty ? g.name : spanRows.first.itemName;

  // Left cell: 22% width, vertically centered, bg white, borders
  final leftCell = pw.Container(
    color: PdfColors.white,
    alignment: pw.Alignment.centerLeft,
    padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
    child: cssText(
      itemName,
      sizePx: 13.0,
      weight: 600,
      color: ReportPdfTheme.inkPrint,
    ),
  );

  // Right cell: 78% width inner table with 3 columns (38:16:24)
  final innerTable = pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(38),
      1: pw.FlexColumnWidth(16),
      2: pw.FlexColumnWidth(24),
    },
    children: [
      for (int i = 0; i < spanRows.length; i++)
        _buildInnerTableRow(spanRows[i], isLast: i == spanRows.length - 1),
    ],
  );

  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(22),
      1: pw.FlexColumnWidth(78),
    },
    children: [
      pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.full,
        children: [
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                left: _tableBorderSide,
                right: _tableBorderSide,
                bottom: _tableBorderSide,
              ),
            ),
            child: leftCell,
          ),
          innerTable,
        ],
      ),
    ],
  );
}

pw.TableRow _buildInnerTableRow(ChecklistReportRow row, {required bool isLast}) {
  const bottomBorder = _tableBorderSide;

  pw.Widget col0;
  pw.Widget col1;
  pw.Widget col2;

  if (row.isRecordParameter) {
    col0 = cssText('Record Parameters', sizePx: 13.0, weight: 600);
    col1 = cssText(row.checkpoint, sizePx: 13.0, weight: 400);
    final val = row.hasValue
        ? '${row.formattedValue}${row.unit.isEmpty ? '' : ' (${row.unit})'}'
        : '——';
    col2 = cssText(val, sizePx: 13.0, weight: 600);
  } else {
    col0 = cssText(row.checkpoint, sizePx: 13.0, weight: 600);
    col1 = cssText(row.statusLabel, sizePx: 13.0, weight: 600);
    col2 = cssText(row.actionDisplay, sizePx: 13.0, weight: 600);
  }

  return pw.TableRow(
    children: [
      _cell(
        col0,
        border: const pw.Border(right: _tableBorderSide, bottom: bottomBorder),
        padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
      ),
      _cell(
        col1,
        border: const pw.Border(right: _tableBorderSide, bottom: bottomBorder),
        padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
      ),
      _cell(
        col2,
        border: const pw.Border(right: _tableBorderSide, bottom: bottomBorder),
        padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
      ),
    ],
  );
}

pw.Widget _buildDeficiencySummary(List<ChecklistDeficiencyRow> defs) {
  const colWidths = {
    0: pw.FlexColumnWidth(18),
    1: pw.FlexColumnWidth(34),
    2: pw.FlexColumnWidth(18),
    3: pw.FlexColumnWidth(16),
    4: pw.FlexColumnWidth(14),
  };

  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 24.0, bottom: 20.0),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Flex header: Deficiency Summary + status badge
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 6.0),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _deficiencyYellowBar, width: 2.25),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              cssText(
                'Deficiency Summary',
                sizePx: 16.92,
                weight: 700,
                color: _deficiencyDarkRed,
              ),
              statusBadge('warn', '${defs.length}'),
            ],
          ),
        ),
        pw.SizedBox(height: 6.0),
        // Deficiency Table
        pw.Table(
          columnWidths: colWidths,
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _headerTint),
              children: [
                _cell(
                  cssText('Asset/Equipment', sizePx: 13.0, weight: 700),
                  border: const pw.Border(
                    top: _tableBorderSide,
                    bottom: _tableBorderSide,
                    left: _tableBorderSide,
                    right: _tableBorderSide,
                  ),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
                ),
                _cell(
                  cssText('Checkpoint', sizePx: 13.0, weight: 700),
                  border: const pw.Border(
                    top: _tableBorderSide,
                    bottom: _tableBorderSide,
                    right: _tableBorderSide,
                  ),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
                ),
                _cell(
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      cssText('Deficiency', sizePx: 13.0, weight: 700),
                      cssText('Finding', sizePx: 13.0, weight: 700),
                    ],
                  ),
                  border: const pw.Border(
                    top: _tableBorderSide,
                    bottom: _tableBorderSide,
                    right: _tableBorderSide,
                  ),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
                ),
                _cell(
                  cssText('Action Taken', sizePx: 13.0, weight: 700),
                  border: const pw.Border(
                    top: _tableBorderSide,
                    bottom: _tableBorderSide,
                    right: _tableBorderSide,
                  ),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
                ),
                _cell(
                  cssText('Severity', sizePx: 13.0, weight: 700),
                  border: const pw.Border(
                    top: _tableBorderSide,
                    bottom: _tableBorderSide,
                    right: _tableBorderSide,
                  ),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
                ),
              ],
            ),
            if (defs.isEmpty)
              pw.TableRow(
                children: [
                  _cell(
                    cssText(
                      'No deficiencies selected.',
                      sizePx: 13.0,
                      weight: 400,
                      color: ReportPdfTheme.faint,
                      align: pw.TextAlign.center,
                    ),
                    border: const pw.Border(
                      bottom: _tableBorderSide,
                      left: _tableBorderSide,
                      right: _tableBorderSide,
                    ),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
                    alignment: pw.Alignment.center,
                  ),
                  _cell(pw.SizedBox(), border: const pw.Border(bottom: _tableBorderSide, right: _tableBorderSide)),
                  _cell(pw.SizedBox(), border: const pw.Border(bottom: _tableBorderSide, right: _tableBorderSide)),
                  _cell(pw.SizedBox(), border: const pw.Border(bottom: _tableBorderSide, right: _tableBorderSide)),
                  _cell(pw.SizedBox(), border: const pw.Border(bottom: _tableBorderSide, right: _tableBorderSide)),
                ],
              )
            else
              for (final d in defs)
                pw.TableRow(
                  children: [
                    _cell(
                      cssText(d.asset, sizePx: 13.0, weight: 600, color: _deficiencyDarkRed),
                      border: const pw.Border(
                        bottom: _tableBorderSide,
                        left: _tableBorderSide,
                        right: _tableBorderSide,
                      ),
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
                    ),
                    _cell(
                      cssText(d.checkpoint, sizePx: 13.0, weight: 600, color: ReportPdfTheme.inkPrint),
                      border: const pw.Border(
                        bottom: _tableBorderSide,
                        right: _tableBorderSide,
                      ),
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
                    ),
                    _cell(
                      cssText(d.finding, sizePx: 13.0, weight: 600, color: _deficiencyDarkRed),
                      border: const pw.Border(
                        bottom: _tableBorderSide,
                        right: _tableBorderSide,
                      ),
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
                    ),
                    _cell(
                      cssText(d.action, sizePx: 13.0, weight: 600, color: _deficiencyDarkRed),
                      border: const pw.Border(
                        bottom: _tableBorderSide,
                        right: _tableBorderSide,
                      ),
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
                    ),
                    _cell(
                      cssText(d.severity, sizePx: 13.0, weight: 600, color: _deficiencyDarkRed),
                      border: const pw.Border(
                        bottom: _tableBorderSide,
                        right: _tableBorderSide,
                      ),
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.5),
                    ),
                  ],
                ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _buildAdditionalDetailsAndSignOff(ChecklistJobWorkReport r, DateTime at) {
  final remarksText = r.remarks.trim().isEmpty ? 'No remarks recorded.' : r.remarks.trim();

  return keepTogether([
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 24.0, bottom: 14.0),
      padding: const pw.EdgeInsets.all(12.0),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _cardBorderColor, width: 0.75),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3.0)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 6.0),
            margin: const pw.EdgeInsets.only(bottom: 9.0),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: _cardBorderColor, width: 0.75),
              ),
            ),
            child: cssText(
              'Additional Details',
              sizePx: 20.0,
              weight: 700,
              color: ReportPdfTheme.inkPrint,
            ),
          ),
          cssText('Technician Remarks:', sizePx: 16.0, weight: 700, color: ReportPdfTheme.inkPrint),
          pw.SizedBox(height: 3.5),
          pw.Container(
            width: double.infinity,
            constraints: const pw.BoxConstraints(minHeight: 37.5),
            padding: const pw.EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: _cardBorderColor, width: 0.75),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3.0)),
            ),
            child: cssText(
              remarksText,
              sizePx: 16.0,
              weight: 400,
              color: ReportPdfTheme.inkPrint,
            ),
          ),
        ],
      ),
    ),
    _buildSignOffCard(r, at),
  ]);
}

pw.Widget _buildSignOffCard(ChecklistJobWorkReport r, DateTime at) {
  final tech = r.technician.trim().isEmpty ? '—' : r.technician.trim();
  final v = r.verification;
  final supervisorText = v == null
      ? 'Pending verification'
      : v.verifiedAtLabel.isNotEmpty
          ? '${v.verifiedByName} · ${v.verifiedAtLabel}'
          : v.verifiedByName;

  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 12.0),
    padding: const pw.EdgeInsets.symmetric(horizontal: 10.2, vertical: 7.8),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      border: pw.Border.all(color: _cardBorderColor, width: 0.75),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3.0)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 3.0),
          margin: const pw.EdgeInsets.only(bottom: 4.8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _headerTint, width: 0.75),
            ),
          ),
          child: cssText(
            'SIGN-OFF',
            sizePx: 13.6,
            weight: 700,
            upper: true,
            color: ReportPdfTheme.inkPrint,
          ),
        ),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(
                    text: 'Technician: ',
                    style: pw.TextStyle(
                      font: ReportFonts.semibold,
                      fontSize: 9.6,
                      color: ReportPdfTheme.inkPrint,
                    ),
                  ),
                  pw.TextSpan(
                    text: pdfSafe(tech),
                    style: pw.TextStyle(
                      font: ReportFonts.regular,
                      fontSize: 9.6,
                      color: ReportPdfTheme.inkPrint,
                    ),
                  ),
                ]),
              ),
            ),
            if (r.otherStaff.trim().isNotEmpty) ...[
              pw.SizedBox(width: 8.0),
              pw.Expanded(
                child: pw.RichText(
                  text: pw.TextSpan(children: [
                    pw.TextSpan(
                      text: 'Maintenance Staff: ',
                      style: pw.TextStyle(
                        font: ReportFonts.semibold,
                        fontSize: 9.6,
                        color: ReportPdfTheme.inkPrint,
                      ),
                    ),
                    pw.TextSpan(
                      text: pdfSafe(r.otherStaff.trim()),
                      style: pw.TextStyle(
                        font: ReportFonts.regular,
                        fontSize: 9.6,
                        color: ReportPdfTheme.inkPrint,
                      ),
                    ),
                  ]),
                ),
              ),
            ],
            pw.SizedBox(width: 8.0),
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(
                    text: 'Supervisor: ',
                    style: pw.TextStyle(
                      font: ReportFonts.semibold,
                      fontSize: 9.6,
                      color: ReportPdfTheme.inkPrint,
                    ),
                  ),
                  pw.TextSpan(
                    text: pdfSafe(supervisorText),
                    style: pw.TextStyle(
                      font: ReportFonts.regular,
                      fontSize: 9.6,
                      color: ReportPdfTheme.inkPrint,
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
        if (v != null && v.remarks.trim().isNotEmpty) ...[
          pw.SizedBox(height: 4.8),
          pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(
                text: 'Supervisor Remarks: ',
                style: pw.TextStyle(
                  font: ReportFonts.semibold,
                  fontSize: 9.6,
                  color: ReportPdfTheme.inkPrint,
                ),
              ),
              pw.TextSpan(
                text: pdfSafe(v.remarks.trim()),
                style: pw.TextStyle(
                  font: ReportFonts.regular,
                  fontSize: 9.6,
                  color: ReportPdfTheme.inkPrint,
                ),
              ),
            ]),
          ),
        ],
        pw.SizedBox(height: 6.0),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: cssText(
            'Generated: ${formatGeneratedAt(at)}',
            sizePx: 12.0,
            weight: 400,
            color: ReportPdfTheme.inkPrint,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _cell(
  pw.Widget child, {
  required pw.Border border,
  pw.EdgeInsets padding = const pw.EdgeInsets.all(3.0),
  pw.Alignment alignment = pw.Alignment.centerLeft,
}) {
  return pw.Container(
    alignment: alignment,
    decoration: pw.BoxDecoration(border: border),
    padding: padding,
    child: child,
  );
}
