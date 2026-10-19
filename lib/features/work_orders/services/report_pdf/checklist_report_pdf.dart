import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

// Web: FormPreview.jsx + FormPreview.module.css (+ reportTheme / Bootstrap).
// All text is black except the Deficiency Summary (#7f1d1d), root line-height
// is Bootstrap's 1.5 ([ReportRoot.lineHeight]).

const _line = pw.BorderSide(color: ReportPdfTheme.borderPrint, width: 0.75);

/// Table borders are drawn once per grid line (like Chrome's collapsed
/// borders, see [CssTableBorder]): stacked tables share an edge, so only the
/// owner of an edge paints it.
pw.TableBorder _tb(
        {bool left = false,
        bool right = false,
        bool top = false,
        bool bottom = false,
        bool hIn = false,
        bool vIn = false}) =>
    CssTableBorder(
      left: left ? _line : pw.BorderSide.none,
      right: right ? _line : pw.BorderSide.none,
      top: top ? _line : pw.BorderSide.none,
      bottom: bottom ? _line : pw.BorderSide.none,
      horizontalInside: hIn ? _line : pw.BorderSide.none,
      verticalInside: vIn ? _line : pw.BorderSide.none,
    );

/// `.reportTable` column widths (22 / 38 / 16 / 24 %).
const _grid = [0.22, 0.38, 0.16, 0.24];

/// Table cell padding: 4.2 x 6pt plus half of the collapsed 0.75pt border.
const _cellPad = pw.EdgeInsets.symmetric(horizontal: 6.375, vertical: 4.575);

const _tdSizePt = 9.75;

/// Table cells are vertically centred (UA `tbody { vertical-align: middle }`).
const _middle = pw.TableCellVerticalAlignment.middle;

const _deficiencyInk = ReportPdfTheme.badFg;

/// A blank vertical gap that is cut short at the bottom of a page, like a CSS
/// margin truncated at a fragmentation break, so it never leads the next
/// page. It is a spanning widget so `MultiPage` lets it fill whatever space
/// is left instead of pushing it onto a new page.
class _Gap extends pw.Widget with pw.SpanningWidget {
  _Gap(this.height);

  final double height;

  @override
  bool get canSpan => true;

  @override
  bool get hasMoreWidgets => false;

  @override
  pw.WidgetContext saveContext() => _GapContext();

  @override
  void restoreContext(pw.WidgetContext context) {}

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    var h = height;
    if (constraints.hasBoundedHeight) {
      h = math.min(h, math.max(0.0, constraints.maxHeight));
    }
    box = PdfRect(
        0, 0, constraints.hasBoundedWidth ? constraints.maxWidth : 0.0, h);
  }
}

class _GapContext extends pw.WidgetContext {
  @override
  pw.WidgetContext clone() => this;

  @override
  void apply(pw.WidgetContext other) {}
}

/// Column width for tables whose borders must line up on the shared 22 / 38 /
/// 16 / 24 % grid. [groups] lists, per table column, the grid columns it
/// covers; every table reaches the right edge of the grid. Mirrors Chrome's
/// collapsed-border model: grid lines sit at `cumulative * 510pt`, the table
/// frame is inset 0.375pt on each outer side.
class _GridCols extends pw.TableColumnWidth {
  const _GridCols(this.groups, this.index);

  final List<List<int>> groups;
  final int index;

  @override
  pw.ColumnLayout layout(
      pw.Widget child, pw.Context context, pw.BoxConstraints? constraints) {
    final first = groups.first.first;
    var frac = 0.0;
    for (final g in groups) {
      for (final c in g) {
        frac += _grid[c];
      }
    }
    final frame = constraints != null && constraints.hasBoundedWidth
        ? constraints.maxWidth
        : 509.25;
    final box = (frame + (first == 0 ? 0.375 : 0.0) + 0.375) / frac;
    var w = 0.0;
    for (final c in groups[index]) {
      w += _grid[c] * box;
    }
    if (index == 0 && first == 0) w -= 0.375;
    if (index == groups.length - 1) w -= 0.375;
    return pw.ColumnLayout(w, 0);
  }
}

Map<int, pw.TableColumnWidth> _cols(List<List<int>> groups) => {
      for (var i = 0; i < groups.length; i++) i: _GridCols(groups, i),
    };

pw.Widget _pad(pw.Widget child) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 15.0),
      child: child,
    );

List<pw.Widget> buildChecklistReportPdf(
    ChecklistJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  final out = <pw.Widget>[
    pw.SizedBox(height: 15.0), // .printableRegister padding
    _pad(reportHeader(
      org: r.org,
      title: r.title,
      forceBlack: true,
    )),
    _pad(_buildMeta(r)),
  ];

  // Each group has margin-top 18 (mt-4); the Deficiency Summary has 36
  // (mt-5). Gaps are emitted after the previous block so they can be cut at
  // a page end instead of leading the next page.
  if (r.isEmpty) {
    out.add(_Gap(18.0));
    out.add(_pad(cssText('No details available.', sizePt: 12.0)));
    out.add(_Gap(36.0));
  } else if (r.groups.isEmpty) {
    out.add(_Gap(36.0));
  }
  for (var i = 0; i < r.groups.length; i++) {
    out.add(_Gap(18.0));
    out.addAll(_buildGroupWidgets(r.groups[i]));
    if (i == r.groups.length - 1) out.add(_Gap(36.0));
  }

  out.addAll(_buildDeficiencySummary(r.deficiencies));
  out.add(_Gap(36.0));
  out.add(_pad(_buildAdditionalDetailsAndSignOff(r, at)));
  return out;
}

// ---------------------------------------------------------------------------
// Meta row (.reportMeta): grid of 164pt columns, gap 9, centred vertically
// ---------------------------------------------------------------------------

pw.Widget _buildMeta(ChecklistJobWorkReport r) {
  final items = <(String, String)>[
    ('Location', r.station),
    ('Schedule', r.schedule),
    if (r.showJobWork) ('Job Work', r.ticket),
    ('Date', r.dateLabel),
  ];

  pw.Widget cell(int i) {
    final align = i == 0
        ? pw.TextAlign.left
        : (i == items.length - 1 ? pw.TextAlign.right : pw.TextAlign.center);
    return pw.SizedBox(
      width: 164.0,
      child: cssRich(
        [
          CssSpan('${items[i].$1}:', weight: 700),
          CssSpan(' ${items[i].$2}'),
        ],
        sizePt: 12.0,
        lineHeight: ReportRoot.lineHeight,
        align: align,
      ),
    );
  }

  final rows = <pw.Widget>[];
  for (var start = 0; start < items.length; start += 3) {
    final end = math.min(items.length, start + 3);
    if (start > 0) rows.add(pw.SizedBox(height: 9.0));
    rows.add(pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        for (var i = start; i < end; i++) ...[
          if (i > start) pw.SizedBox(width: 9.0),
          cell(i),
        ],
      ],
    ));
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: rows,
  );
}

// ---------------------------------------------------------------------------
// Asset group
// ---------------------------------------------------------------------------

pw.Widget _td(String text,
        {int weight = 600,
        PdfColor color = ReportPdfTheme.inkPrint,
        bool softWrap = true,
        pw.TextAlign? align,
        double extraV = 0}) =>
    pw.Padding(
      padding: extraV == 0
          ? _cellPad
          : pw.EdgeInsets.symmetric(
              horizontal: 6.375, vertical: 4.575 + extraV / 2),
      child: cssText(
        text,
        sizePt: _tdSizePt,
        weight: weight,
        color: color,
        softWrap: softWrap,
        align: align,
      ),
    );

pw.Widget _th(String text, {double extraV = 0}) =>
    _td(text, weight: 700, softWrap: false, extraV: extraV);

/// A group taller than this (css: cannot avoid a page break) is laid out as
/// one flat, paginating table instead of unbreakable nested rows.
const _maxKeptGroupHeight = 784.0;

pw.Widget _groupHeading(String name) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        CssBox.bordered(
          side: const CssSide(0.75, ReportPdfTheme.border),
          padding: const pw.EdgeInsets.all(6.0),
          background: PdfColors.white,
          child: cssText(name, sizePt: 15.0, weight: 700, lineHeight: 1.2),
        ),
        pw.SizedBox(height: 6.0), // h5 margin-bottom
      ],
    );

pw.Widget _headerTable(double extra) => pw.Table(
      border: _tb(left: true, right: true, top: true, bottom: true, vIn: true),
      columnWidths: _cols(const [
        [0],
        [1],
        [2],
        [3],
      ]),
      children: [
        pw.TableRow(
          verticalAlignment: _middle,
          decoration: const pw.BoxDecoration(color: ReportPdfTheme.accentTint),
          children: [
            _th('Asset/Equipment', extraV: extra),
            _th('Checkpoint/Parameter', extraV: extra),
            _th('Status', extraV: extra),
            _th('Action Taken', extraV: extra),
          ],
        ),
      ],
    );

/// The top-level `MultiPage` children for one asset group (`.assetGroup`:
/// `break-inside: avoid`).
List<pw.Widget> _buildGroupWidgets(ChecklistReportGroup g) {
  // Row heights follow Chrome: every row is `lines * 19.5 + 12.2` css px and
  // the cumulative row edges are snapped to whole px, so rows alternate
  // 24 / 23.25pt. The difference to each row's natural height is added as
  // cell padding so the table lines land where the web print puts them.
  final rows = g.rows;
  final spans = <(int, int)>[];
  for (var i = 0; i < rows.length;) {
    final len = rows[i].itemSpanLen > 0 ? rows[i].itemSpanLen : 1;
    spans.add((i, math.min(rows.length, i + len) - i));
    i += len;
  }
  String nameOf(int start) =>
      rows[start].itemName.isEmpty ? g.name : rows[start].itemName;
  final px = <double>[_rowPx(1)]; // header row
  final natural = <double>[_naturalPt(1)];
  for (final sp in spans) {
    final span = rows.sublist(sp.$1, sp.$1 + sp.$2);
    px.addAll(_spanRowPx(nameOf(sp.$1), span));
    natural.addAll([for (final row in span) _naturalPt(_rowLines(row))]);
  }
  if (rows.isEmpty) {
    px.add(_rowPx(1));
    natural.add(_naturalPt(1));
  }
  final extras = _snapExtras(px, natural);

  final estimated =
      31.5 + 6.0 + 0.75 + px.fold<double>(0, (a, b) => a + b) * 0.75;
  if (estimated > _maxKeptGroupHeight) {
    return [
      _pad(_groupHeading(g.name)),
      _pad(_buildFlatTable(g, spans, extras, nameOf)),
    ];
  }

  var rowCursor = 1;
  final blocks = <pw.Widget>[];
  if (rows.isEmpty) {
    blocks.add(pw.Table(
      border: _tb(left: true, right: true, bottom: true),
      columnWidths: _cols(const [
        [0, 1, 2, 3],
      ]),
      children: [
        pw.TableRow(children: [
          _td('No checks for this asset.', align: pw.TextAlign.center),
        ]),
      ],
    ));
  }
  for (final sp in spans) {
    final span = rows.sublist(sp.$1, sp.$1 + sp.$2);
    blocks.add(_buildItemBlock(nameOf(sp.$1), span,
        extras.sublist(rowCursor, rowCursor + span.length)));
    rowCursor += span.length;
  }

  // The table box is the grid inset by 0.375pt (collapsed outer borders); the
  // blocks are direct children of the column so an over-tall group still
  // paginates between them.
  pw.Widget inset(pw.Widget w, {bool top = false}) => pw.Padding(
      padding:
          pw.EdgeInsets.only(left: 0.375, right: 0.375, top: top ? 0.375 : 0),
      child: w);
  return [
    AvoidBreakInside(
      child: _pad(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          _groupHeading(g.name),
          inset(_headerTable(extras[0]), top: true),
          for (final b in blocks) inset(b),
          pw.SizedBox(height: 0.375),
        ],
      )),
    ),
  ];
}

/// Flat fallback for a group taller than a page: one table whose item-name
/// cell sits in the first row of its span (the cell border is merged down the
/// span), so it can paginate between rows and repeat its header row.
pw.Widget _buildFlatTable(ChecklistReportGroup g, List<(int, int)> spans,
    List<double> extras, String Function(int) nameOf) {
  pw.Widget bordered(pw.Widget child, {required bool bottom}) => CssBox(
      alignment: pw.Alignment.centerLeft,
      bottom: bottom ? const CssSide(0.75, ReportPdfTheme.borderPrint) : null,
      child: child);

  final trs = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      verticalAlignment: pw.TableCellVerticalAlignment.full,
      decoration: const pw.BoxDecoration(color: ReportPdfTheme.accentTint),
      children: [
        for (final h in const [
          'Asset/Equipment',
          'Checkpoint/Parameter',
          'Status',
          'Action Taken',
        ])
          bordered(_th(h, extraV: extras[0]), bottom: true),
      ],
    ),
  ];
  var k = 1;
  if (g.rows.isEmpty) {
    trs.add(pw.TableRow(children: [
      for (var c = 0; c < 4; c++)
        bordered(c == 0 ? _td('No checks for this asset.') : pw.SizedBox(),
            bottom: true),
    ]));
  }
  for (final sp in spans) {
    for (var r = 0; r < sp.$2; r++) {
      final row = g.rows[sp.$1 + r];
      final extra = extras[k++];
      trs.add(pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.full,
        children: [
          bordered(r == 0 ? _td(nameOf(sp.$1), extraV: extra) : pw.SizedBox(),
              bottom: r == sp.$2 - 1),
          for (final c in _rowTexts(row))
            bordered(_td(c.$1, weight: c.$2, extraV: extra), bottom: true),
        ],
      ));
    }
  }
  return pw.Padding(
    padding: const pw.EdgeInsets.all(0.375),
    child: pw.Table(
      border: _tb(left: true, right: true, top: true, vIn: true),
      columnWidths: _cols(const [
        [0],
        [1],
        [2],
        [3],
      ]),
      children: trs,
    ),
  );
}

/// Number of lines [text] wraps to in a column of [colFraction] of the table
/// (greedy word wrap, like the browser).
int _lines(String text, int weight, double colFraction) =>
    _wrapLines(text, weight, colFraction * 510.0 - 12.75);

/// Number of lines [text] wraps to in [width]pt of text area.
int _wrapLines(String text, int weight, double width) =>
    cssWrapLineCount(text, width, _tdSizePt, weight: weight);

/// Line count of the tallest cell of [row].
int _rowLines(ChecklistReportRow row) {
  final cells = _rowTexts(row);
  var lines = 1;
  for (var c = 0; c < 3; c++) {
    lines = math.max(lines, _lines(cells[c].$1, cells[c].$2, _grid[c + 1]));
  }
  return lines;
}

/// Height in css px of a table row of [lines] text lines (see [cssRowPx]).
double _rowPx(int lines) => cssRowPx(lines, lineHeight: ReportRoot.lineHeight);

/// The height pdf layout gives a row of [lines] lines (padding 4.575 x 2).
double _naturalPt(int lines) => lines * 14.625 + 9.15;

/// Row heights (css px) of an item's rows. When the item-name cell is taller
/// than the rows it spans Chrome spreads the excess over those rows.
List<double> _spanRowPx(String name, List<ChecklistReportRow> span) {
  final h = [for (final row in span) _rowPx(_rowLines(row))];
  final rowsH = h.fold(0.0, (a, b) => a + b);
  final nameH = _rowPx(_lines(name, 600, _grid[0]));
  if (nameH > rowsH) {
    final add = (nameH - rowsH) / h.length;
    return [for (final v in h) v + add];
  }
  return h;
}

/// Snaps the cumulative row edges (row heights [px], css px) to whole px, as
/// Chrome paints them ([cssSnapRowsPt]), and returns, per row, the extra
/// height in pt over the row's [natural] (content + padding) height in pt.
List<double> _snapExtras(List<double> px, List<double> natural) {
  final snapped = cssSnapRowsPt(px);
  return [for (var i = 0; i < px.length; i++) snapped[i] - natural[i]];
}

/// (text, weight) for the three right-hand columns of a regular row.
List<(String, int)> _rowTexts(ChecklistReportRow row) {
  if (row.isRecordParameter) {
    return [
      ('Record Parameters', 600),
      (row.checkpoint, 400),
      (_valueText(row), 600),
    ];
  }
  return [
    (row.checkpoint, 600),
    (row.statusLabel, 600),
    (row.actionDisplay, 600),
  ];
}

String _valueText(ChecklistReportRow row) => row.hasValue
    ? '${row.formattedValue}${row.unit.isEmpty ? '' : ' (${row.unit})'}'
    : '——';

/// The item-name cell (rowspan) is a cell of a one-row outer table next to a
/// nested table holding the item's rows; `TableCellVerticalAlignment.full`
/// stretches the name cell so its text can be centred vertically.
pw.Widget _spanTable({
  required List<List<int>> groups,
  required pw.Widget left,
  required pw.Widget right,
  required pw.TableBorder border,
}) =>
    pw.Table(
      border: border,
      columnWidths: _cols(groups),
      children: [
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.full,
          children: [left, right],
        ),
      ],
    );

/// A rowspan cell: no vertical padding of its own (the spanned rows are never
/// shorter than its padded text), so its text is simply centred in the span.
pw.Widget _centredCell(String text) => pw.Container(
      alignment: pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6.375),
      child: cssText(
        text,
        sizePt: _tdSizePt,
        weight: 600,
      ),
    );

pw.Widget _buildItemBlock(
    String name, List<ChecklistReportRow> span, List<double> extras) {
  // Each segment draws its bottom edge unless it is the last one (the item
  // block's own bottom edge is drawn by the outer table).
  final segments = <pw.Widget Function(bool last)>[];
  var normal = <int>[];

  void flushNormal() {
    if (normal.isEmpty) return;
    final rowsOfSegment = normal;
    segments.add((last) => pw.Table(
          border: _tb(vIn: true, hIn: true, bottom: !last),
          columnWidths: _cols(const [
            [1],
            [2],
            [3],
          ]),
          children: [
            for (final k in rowsOfSegment)
              pw.TableRow(verticalAlignment: _middle, children: [
                for (final c in _rowTexts(span[k]))
                  _td(c.$1, weight: c.$2, extraV: extras[k]),
              ]),
          ],
        ));
    normal = [];
  }

  var i = 0;
  while (i < span.length) {
    if (!span[i].isRecordParameter) {
      normal.add(i);
      i++;
      continue;
    }
    flushNormal();
    var j = i;
    while (j < span.length && span[j].isRecordParameter) {
      j++;
    }
    final runStart = i;
    final run = span.sublist(i, j);
    i = j;
    segments.add((last) => _spanTable(
          border: _tb(vIn: true, bottom: !last),
          groups: const [
            [1],
            [2, 3],
          ],
          left: _centredCell('Record Parameters'),
          right: pw.Table(
            border: _tb(vIn: true, hIn: true),
            columnWidths: _cols(const [
              [2],
              [3],
            ]),
            children: [
              for (var k = 0; k < run.length; k++)
                pw.TableRow(verticalAlignment: _middle, children: [
                  _td(run[k].checkpoint,
                      weight: 400, extraV: extras[runStart + k]),
                  _td(_valueText(run[k]), extraV: extras[runStart + k]),
                ]),
            ],
          ),
        ));
  }
  flushNormal();

  return _spanTable(
    border: _tb(left: true, right: true, bottom: true, vIn: true),
    groups: const [
      [0],
      [1, 2, 3],
    ],
    left: _centredCell(name),
    right: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        for (var k = 0; k < segments.length; k++)
          segments[k](k == segments.length - 1),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Deficiency Summary
// ---------------------------------------------------------------------------

List<pw.Widget> _buildDeficiencySummary(List<ChecklistDeficiencyRow> defs) {
  // Flex row: h4 (22.56px = 16.92pt, bold, lh 1.2) + warn badge, centred;
  // border-bottom 2.25 #ffc107, padding-bottom 6, margin-bottom 6.
  final heading = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      CssBox(
        padding: const pw.EdgeInsets.only(bottom: 6.0),
        bottom: const CssSide(2.25, ReportPdfTheme.borderWarning),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            cssText(
              'Deficiency Summary',
              sizePt: 16.92,
              weight: 700,
              lineHeight: 1.2,
              color: _deficiencyInk,
            ),
            statusBadge('warn', '${defs.length}'),
          ],
        ),
      ),
      pw.SizedBox(height: 6.0),
    ],
  );

  const headers = [
    'Asset/Equipment',
    'Checkpoint',
    'Deficiency Finding',
    'Action Taken',
    'Severity',
  ];
  final table = cssTable(
    headers,
    defs.isEmpty
        ? const [
            ['No deficiencies selected.'],
          ]
        : [
            for (final d in defs)
              [d.asset, d.checkpoint, d.finding, d.action, d.severity],
          ],
    lineHeight: ReportRoot.lineHeight,
    bodyWeight: 600,
    bodyColor: _deficiencyInk,
    // The checkpoint cell wraps its text in a div, which the print rule
    // forces back to black.
    cellStyles: (r, c) => c == 1 && defs.isNotEmpty
        ? const CssCellStyle(color: ReportPdfTheme.inkPrint)
        : null,
  );

  return [_pad(heading), _pad(table)];
}

// ---------------------------------------------------------------------------
// Additional Details + sign-off
// ---------------------------------------------------------------------------

pw.Widget _buildAdditionalDetailsAndSignOff(
    ChecklistJobWorkReport r, DateTime at) {
  final remarks =
      r.remarks.trim().isEmpty ? 'No remarks recorded.' : r.remarks.trim();
  final lh = ReportRoot.lineHeight;

  final details = CssBox.bordered(
    side: const CssSide(0.75, ReportPdfTheme.border),
    radius: 4.5,
    padding: const pw.EdgeInsets.all(12.0),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        CssBox(
          padding: const pw.EdgeInsets.only(bottom: 6.0),
          margin: const pw.EdgeInsets.only(bottom: 12.0),
          bottom: const CssSide(0.75, ReportPdfTheme.border),
          child: cssText(
            'Additional Details',
            sizePt: 15.0,
            weight: 700,
            lineHeight: 1.2,
          ),
        ),
        cssText('Technician Remarks:',
            sizePt: 12.0, weight: 700, lineHeight: lh),
        pw.SizedBox(height: 3.0),
        CssBox.bordered(
          side: const CssSide(0.75, ReportPdfTheme.border),
          radius: 4.5,
          padding: const pw.EdgeInsets.all(6.0),
          minHeight: 37.5,
          child: cssText(remarks, sizePt: 12.0, lineHeight: lh),
        ),
        pw.SizedBox(height: 6.0), // .mb-2 of the remarks wrapper
      ],
    ),
  );

  return keepTogether([
    details,
    pw.SizedBox(height: 18.0), // mb-4; collapses with the sign-off's mt 9
    signOff(
      technician: r.technician,
      maintenanceStaff: r.otherStaff,
      verification: r.verification,
      generatedAt: at,
      lineHeight: ReportRoot.lineHeight,
      forceBlack: true,
    ),
  ]);
}
