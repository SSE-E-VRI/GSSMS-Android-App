import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

/// Inspection Job Work report (web `InspectionReportPreview`). Root
/// line-height is Bootstrap's body 1.5; the root font is 12pt.
const double _lh = 1.5;

/// `.text-secondary` = rgba(33, 37, 41, .75): the colour here, the 75% in
/// [_secondary].
const _secondaryRgb = PdfColor.fromInt(0xFF212529);

List<pw.Widget> buildInspectionReportPdf(
    InspectionJobWorkReport r, Map<String, Uint8List?> photos, DateTime at) {
  final children = <pw.Widget>[
    reportHeader(
      org: r.org,
      title: r.title,
      subtitle: 'Ticket #${r.ticket}',
      metaLeft: [('Location', r.station)],
      metaRight: [('Date', r.dateLabel)],
      lineHeight: _lh,
    ),
  ];

  // Inspection Title: `div.mb-3` with an inline small label above a 12pt
  // bold value.
  if (r.inspectionTitle.isNotEmpty) {
    children.add(pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          _strutLabel('Inspection Title'),
          cssText(r.inspectionTitle,
              sizePt: 12, weight: 700, lineHeight: _lh),
        ],
      ),
    ));
  }

  // headerGrid: two 264pt columns, column gap 12, pb 12 + rule, mb 12.
  pw.Widget headerCell(String label, String value) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            _strutLabel(label),
            cssText(value.isEmpty ? 'N/A' : value,
                sizePt: 12, weight: 600, lineHeight: _lh),
          ],
        ),
      );
  children.add(CssBox(
    margin: const pw.EdgeInsets.only(bottom: 12),
    padding: const pw.EdgeInsets.only(bottom: 12),
    bottom: const CssSide(0.75, ReportPdfTheme.border),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        headerCell('Inspection No.', r.inspectionNumber),
        pw.SizedBox(width: 12),
        headerCell('Inspector', r.inspector),
      ],
    ),
  ));

  // Inspection Remarks: `div.mb-3` > Field.
  if (r.inspectionRemarks.isNotEmpty) {
    children.add(pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: _field('Inspection Remarks', r.inspectionRemarks),
    ));
  }

  // General evidence: `div.mb-4`, label mb 3, wrapped flex of photos.
  if (r.generalEvidencePhotos.isNotEmpty) {
    children
      ..addAll(_bands([
        [
          _labelPiece('General Evidence Photos'),
          ..._photoPieces(r.generalEvidencePhotos, photos, 540),
        ],
      ], const [540]))
      ..add(pw.SizedBox(height: 18));
  }

  final points = r.points;
  final leading = points.length > 1
      ? points.sublist(0, points.length - 1)
      : <InspectionReportPoint>[];
  final last = points.isNotEmpty ? points.last : null;

  for (final p in leading) {
    children.addAll(_point(r, p, photos));
  }

  // The last point stays together with the sign-off (`.keepTogether`); the
  // point's mb-4 (18) collapses with the sign-off card's mt (9).
  final tail = <pw.Widget>[
    if (last != null) ..._point(r, last, photos),
    signOff(
      technician: r.submission?.submittedByName.isNotEmpty == true
          ? r.submission!.submittedByName
          : r.technician,
      verification: r.verification,
      submission: r.submission,
      generatedAt: at,
      lineHeight: _lh,
      collapseWith: last != null ? 18.0 : 0.0,
    ),
  ];
  children.add(keepTogether(tail));
  return children;
}

// ---------------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------------

/// A `.small` label that is an inline `<span>` inside a 12pt block: the line
/// box is the 12pt strut (18pt tall) and the smaller text shares its baseline.
pw.Widget _strutLabel(String text) => cssText(text,
    sizePt: 10.5,
    strutSizePt: 12.0,
    color: ReportPdfTheme.muted,
    lineHeight: _lh);

/// `div.text-muted.small.fw-bold` label (10.5pt Bold, line box 15.75).
pw.Widget _smallLabel(String text) => cssText(text,
    sizePt: 10.5, weight: 700, color: ReportPdfTheme.muted, lineHeight: _lh);

/// The pdf package ignores the last glyph's right side bearing when it fits a
/// word on a line, Chrome does not (and the column is also 0.07pt narrower
/// on Android's A4): wrapped values lose this much width so their line breaks
/// match Chrome's.
const double _wrapSlack = 1.1;

/// `Field`: bold small label, then a pre-wrap 12pt value or an italic muted
/// "None recorded".
pw.Widget _field(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        _smallLabel(label),
        value.trim().isNotEmpty
            ? pw.Padding(
                padding: const pw.EdgeInsets.only(right: _wrapSlack),
                child: cssText(value, sizePt: 12, lineHeight: _lh))
            : cssText('None recorded',
                sizePt: 12,
                italic: true,
                color: ReportPdfTheme.muted,
                lineHeight: _lh),
      ],
    );

pw.Widget _secondary(pw.Widget child) =>
    pw.Opacity(opacity: 0.75, child: child);

// ---------------------------------------------------------------------------
// Point
// ---------------------------------------------------------------------------

/// One `renderPoint` block as separate MultiPage children (header, fields,
/// parameters, photo-grid bands, footer) so a page break can fall wherever
/// Chrome's fragmentation would put it.
List<pw.Widget> _point(InspectionJobWorkReport r, InspectionReportPoint p,
    Map<String, Uint8List?> photos) {
  final observationOnly = p.correctiveActionPerformed == false;
  final out = <pw.Widget>[];

  if (!p.isLegacy) {
    final tag =
        '${p.assetName.isEmpty ? 'N/A' : p.assetName} · ${p.priority.isEmpty ? 'N/A' : p.priority}';
    out.add(pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: cssText('Point #${p.pointNumber}: ${p.observation}'.trim(),
                sizePt: 12, weight: 700, lineHeight: _lh),
          ),
          pw.SizedBox(width: 6),
          statusBadge('neutral', tag),
        ],
      ),
    ));
  } else {
    // h6.fw-bold.text-secondary.text-uppercase.small.mb-2 (line-height 1.2).
    out.add(pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: _secondary(cssText('Technician Execution',
          sizePt: 10.5,
          weight: 700,
          upper: true,
          color: _secondaryRgb,
          lineHeight: 1.2)),
    ));
    if (r.coveredPoints.isNotEmpty) {
      out.add(_smallLabel('Inspection Points Covered'));
      for (final c in r.coveredPoints) {
        out.add(_listItem('#${c.number}: ${c.text}'
            '${c.priority.isEmpty ? '' : ' (${c.priority})'}'));
      }
      out.add(pw.SizedBox(height: 6));
    }
  }

  // fieldsGrid mb-2: three 172pt columns, gap 12.
  out.add(pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _field('Initial Findings', p.initialFindings)),
        pw.SizedBox(width: 12),
        pw.Expanded(child: _field('Action Taken', p.actionTaken)),
        pw.SizedBox(width: 12),
        pw.Expanded(child: _field('Final Remarks', p.finalRemarks)),
      ],
    ),
  ));

  if (p.technicalParameters.isNotEmpty) {
    out
      ..add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: _smallLabel('Technical Parameters')))
      ..addAll(cssTableRows(
        const ['Parameter', 'Value', 'Unit'],
        [
          for (final q in p.technicalParameters)
            [q.parameter, q.value, q.unit.isEmpty ? '-' : q.unit],
        ],
        width: reportContentWidth,
        lineHeight: _lh,
      ))
      ..add(pw.SizedBox(height: 6));
  }

  // photoGrid: 3 x 172 (pointwise) or 2 x 264 (legacy), gap 12.
  final colW = p.isLegacy ? 264.0 : 172.0;
  final cols = <List<_Piece>>[
    if (!p.isLegacy)
      [
        _labelPiece('Before Photos (From Inspection)'),
        ..._photoPieces(p.inspectionEvidencePhotos, photos, colW,
            emptyLabel: 'None'),
      ],
    [
      _labelPiece('Before Photos'),
      ..._photoPieces(p.beforePhotos, photos, colW,
          emptyLabel: 'None uploaded'),
    ],
    [
      _labelPiece('After Photos'),
      if (observationOnly) _notePiece(colW),
      ..._photoPieces(p.afterPhotos, photos, colW,
          emptyLabel: observationOnly ? 'Not applicable' : 'None uploaded'),
    ],
  ];
  out.addAll(_bands(cols, List.filled(cols.length, colW)));

  // pb-3 + border-bottom + mb-4.
  out.add(CssBox(
    margin: const pw.EdgeInsets.only(bottom: 18),
    padding: const pw.EdgeInsets.only(top: 12),
    bottom: const CssSide(0.75, ReportPdfTheme.border),
  ));
  return out;
}

/// `li` in `ul.ps-3` (12pt indent) with a disc marker: 4.5pt circle whose top
/// sits 6pt above the first baseline, centred 1.5pt left of the list box.
pw.Widget _listItem(String text) {
  final baseline = cssBaselinePt(_lh, 12.0);
  return pw.Stack(
    overflow: pw.Overflow.visible,
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12),
        child: cssText(text, sizePt: 12, lineHeight: _lh),
      ),
      pw.Positioned(
        left: -1.5,
        top: baseline - 6.0,
        child: pw.Container(
          width: 4.5,
          height: 4.5,
          decoration: const pw.BoxDecoration(
            color: ReportPdfTheme.inkPrint,
            shape: pw.BoxShape.circle,
          ),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Technical parameters table
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Photo grids
// ---------------------------------------------------------------------------

/// One vertical piece of a photo column: [h] tall, laid out from its top.
class _Piece {
  const _Piece(this.h, this.widget);
  final double h;
  final pw.Widget widget;
}

/// Label above a PhotoGrid: 15.75pt line + mb 3.
_Piece _labelPiece(String text) => _Piece(18.75, _smallLabel(text));

/// "Observation only" note (`small text-secondary fst-italic mb-1`); wraps
/// inside the [width] column.
_Piece _notePiece(double width) {
  const text = 'Observation only — no corrective action required';
  final lines = cssWrapLineCount(text, width, 10.5, italic: true);
  return _Piece(
    lines * 15.75 + 3,
    _secondary(cssText(text,
        sizePt: 10.5,
        italic: true,
        color: _secondaryRgb,
        lineHeight: _lh)),
  );
}

/// Extra line-box height below a thumbnail (pt). The `.thumb` is an
/// `inline-flex` on a 12pt line, so it sits on the strut baseline: its image
/// bottom is the baseline and the 24px strut leaves 6px below it, while the
/// thumb's own border + padding + centring leaves less for tall images.
double _thumbExtension(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return 0;
  try {
    final image = pw.MemoryImage(bytes);
    final nw = (image.width ?? 1).toDouble();
    final nh = (image.height ?? 1).toDouble();
    final scale = math.min(1.0, math.min(106.0 / nw, 81.0 / nh));
    final ih = (nh * scale).floorToDouble();
    final belowPx = 3.0 + (79.0 - ih) / 2;
    return math.max(0.0, 6.0 - belowPx) * 0.75;
  } catch (_) {
    return 0;
  }
}

/// A PhotoGrid (`d-flex flex-wrap gap-2`) inside [width]: per line one piece
/// for the thumbnails and one for the captions, so a break can fall between
/// them. Empty -> italic muted [emptyLabel].
List<_Piece> _photoPieces(
  List<ReportPhoto> list,
  Map<String, Uint8List?> photos,
  double width, {
  String emptyLabel = 'None',
}) {
  if (list.isEmpty) {
    return [
      _Piece(
          15.75,
          cssText(emptyLabel,
              sizePt: 10.5,
              italic: true,
              color: ReportPdfTheme.muted,
              lineHeight: _lh)),
    ];
  }
  const tileW = thumbBoxW;
  const gap = 6.0;
  final perLine = math.max(1, ((width + gap) / (tileW + gap)).floor());
  final out = <_Piece>[];
  for (var start = 0; start < list.length; start += perLine) {
    final line = list.sublist(start, math.min(list.length, start + perLine));
    final ext = [for (final p in line) _thumbExtension(photos[p.key])];
    final minExt = ext.reduce(math.min);
    final maxExt = ext.reduce(math.max);
    final hasCaption = line.any((p) => p.caption.isNotEmpty);
    final more = start + perLine < list.length;

    out.add(_Piece(
      thumbBoxH + (hasCaption ? minExt : maxExt) + (more && !hasCaption ? gap : 0),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < line.length; i++) ...[
            if (i > 0) pw.SizedBox(width: gap),
            thumb(photos[line[i].key]),
          ],
        ],
      ),
    ));
    if (hasCaption) {
      out.add(_Piece(
        (maxExt - minExt) + 21.75 + (more ? gap : 0),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < line.length; i++) ...[
              if (i > 0) pw.SizedBox(width: gap),
              pw.SizedBox(
                width: tileW,
                child: line[i].caption.isEmpty
                    ? null
                    : pw.Padding(
                        padding: pw.EdgeInsets.only(top: ext[i] - minExt),
                        child: pw.SizedBox(
                          width: tileW,
                          child: pw.Padding(
                            padding: const pw.EdgeInsets.all(3.0),
                            child: cssText(truncateCaption(line[i].caption),
                                sizePt: 10.5,
                                color: ReportPdfTheme.muted,
                                lineHeight: _lh,
                                maxLines: 1,
                                softWrap: false),
                          ),
                        ),
                      ),
              ),
            ],
          ],
        ),
      ));
    }
  }
  return out;
}

/// Merges grid columns (lists of vertical pieces) into aligned full-width
/// bands, one MultiPage child each. A band starts wherever any column starts
/// a piece, so columns that differ (e.g. an extra note) keep Chrome's
/// positions and a page break may fall between any two bands.
List<pw.Widget> _bands(List<List<_Piece>> cols, List<double> widths,
    {double gap = 12}) {
  double r(double v) => (v * 1000).roundToDouble() / 1000;
  final starts = <double>{};
  var end = 0.0;
  final colStarts = <List<double>>[];
  for (final col in cols) {
    var y = 0.0;
    final s = <double>[];
    for (final p in col) {
      s.add(r(y));
      starts.add(r(y));
      y += p.h;
    }
    end = math.max(end, y);
    colStarts.add(s);
  }
  final sorted = starts.toList()..sort();
  final out = <pw.Widget>[];
  for (var k = 0; k < sorted.length; k++) {
    final top = sorted[k];
    final bottom = k + 1 < sorted.length ? sorted[k + 1] : r(end);
    final cells = <pw.Widget>[];
    for (var c = 0; c < cols.length; c++) {
      if (c > 0) cells.add(pw.SizedBox(width: gap));
      final idx = colStarts[c].indexOf(top);
      cells.add(pw.SizedBox(
        width: widths[c],
        child: idx < 0
            ? null
            : pw.Align(
                alignment: pw.Alignment.topLeft, child: cols[c][idx].widget),
      ));
    }
    out.add(pw.SizedBox(
      height: bottom - top,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: cells,
      ),
    ));
  }
  return out;
}
