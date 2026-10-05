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
    _header(
      org: r.org,
      title: r.title,
      subtitle: 'Ticket #${r.ticket}',
      location: r.station,
      date: r.dateLabel,
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
// Header
// ---------------------------------------------------------------------------

/// [reportHeader] with the Inspection h2 in slate `#1e293b` (the shared
/// primitive hard-codes black). Same CSS metrics as the primitive.
pw.Widget _header({
  required ReportOrganization org,
  required String title,
  required String subtitle,
  required String location,
  required String date,
}) {
  pw.Widget meta(String label, String value, pw.TextAlign align) => cssRich(
        [CssSpan('$label: ', weight: 700), CssSpan(value)],
        sizePt: 10.2,
        lineHeight: _lh,
        align: align,
      );

  return CssBox(
    padding: const pw.EdgeInsets.only(bottom: 9.0),
    margin: const pw.EdgeInsets.only(bottom: 12.0),
    bottom: const CssSide(1.5, ReportPdfTheme.accent),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        cssText(
          org.railwayName,
          sizePt: 15.0,
          weight: 700,
          upper: true,
          lineHeight: 1.2,
          letterSpacingEm: 0.03,
          color: ReportPdfTheme.headingInk,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2.4),
        cssText(
          org.divisionName,
          sizePt: 12.0,
          weight: 600,
          lineHeight: 1.2,
          color: ReportPdfTheme.muted,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 1.8),
        cssText(
          org.depotName,
          sizePt: 12.0,
          weight: 600,
          lineHeight: 1.2,
          color: ReportPdfTheme.muted,
          align: pw.TextAlign.center,
        ),
        // depot mb 1.8 collapses with the meta row's margin 6.
        pw.SizedBox(height: 6.0),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: meta('Location', location, pw.TextAlign.left)),
            pw.SizedBox(width: 9.0),
            pw.Expanded(child: meta('Date', date, pw.TextAlign.right)),
          ],
        ),
        pw.SizedBox(height: 6.0),
        cssText(
          title,
          sizePt: 13.2,
          weight: 700,
          upper: true,
          lineHeight: 1.2,
          color: ReportPdfTheme.accent,
          letterSpacingEm: 0.05,
          align: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 3.0),
        cssText(
          subtitle,
          sizePt: 10.8,
          weight: 600,
          lineHeight: _lh,
          align: pw.TextAlign.center,
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------------

/// A `.small` label that is an inline `<span>` inside a 12pt block: the line
/// box is the 12pt strut (18pt tall) and the smaller text shares its baseline.
pw.Widget _strutLabel(String text) {
  const size = 10.5;
  final strutBase = cssBaselineEm(_lh) * 12.0;
  final top = strutBase - cssBaselineEm(_lh) * size;
  final bottom = 12.0 * _lh - top - size * _lh;
  return pw.Padding(
    padding: pw.EdgeInsets.only(top: top, bottom: bottom),
    child: cssText(text,
        sizePt: size, color: ReportPdfTheme.muted, lineHeight: _lh),
  );
}

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
      // Chrome floors the negative half-leading of this 1.2 line to whole
      // pixels, so its baseline sits 0.9pt above the unrounded CSS value.
      child: pw.Transform.translate(
        offset: const PdfPoint(0, 0.9),
        child: _secondary(cssText('Technician Execution',
            sizePt: 10.5,
            weight: 700,
            upper: true,
            color: _secondaryRgb,
            lineHeight: 1.2)),
      ),
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
      ..addAll(_paramTableRows(p.technicalParameters))
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
  final baseline = cssBaselineEm(_lh) * 12.0;
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

/// `.table` for Parameter / Value / Unit as one MultiPage child per row, with
/// Chrome's geometry: auto layout over the 540pt content width, collapsed
/// 0.75pt `#4b5563` borders painted as fills inside the cells (the shared
/// [cssTable] strokes them, which anti-aliases differently), th bold on
/// `#e8eef5`. Row heights follow the wrapped line counts.
List<pw.Widget> _paramTableRows(List<ReportParameter> params) {
  const total = 540.0;
  const sizePt = 9.75;
  const padH = 6.0;
  const padV = 4.2;
  const lineH = sizePt * _lh;
  const border = CssSide(0.75, ReportPdfTheme.borderPrint);
  const headers = ['Parameter', 'Value', 'Unit'];
  final rows = [
    for (final q in params) [q.parameter, q.value, q.unit.isEmpty ? '-' : q.unit],
  ];

  final mins = List<double>.filled(3, 0);
  final maxs = List<double>.filled(3, 0);
  void measure(String text, int col, int weight) {
    maxs[col] = math.max(maxs[col], measureText(text, sizePt, weight: weight));
    for (final word in pdfSafe(text).split(RegExp(r'\s+'))) {
      mins[col] =
          math.max(mins[col], measureText(word, sizePt, weight: weight));
    }
  }

  for (var c = 0; c < 3; c++) {
    measure(headers[c], c, 700);
    for (final r in rows) {
      measure(r[c], c, 400);
    }
    mins[c] += padH * 2 + 0.75;
    maxs[c] += padH * 2 + 0.75;
  }
  final widths = autoColumnWidths(mins, maxs, total);

  pw.Widget row(List<String> cells, {required bool header}) {
    var lines = 1;
    for (var c = 0; c < 3; c++) {
      lines = math.max(
          lines,
          _wrapLineCount(cells[c], sizePt,
              widths[c] - padH * 2 - (c == 0 ? 1.5 : 0.75),
              weight: header ? 700 : 400));
    }
    final h = lines * lineH + padV * 2 + (header ? 1.5 : 0.75);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < 3; c++)
          CssBox(
            width: widths[c],
            height: header ? math.max(h, 24.75) : h,
            padding: const pw.EdgeInsets.symmetric(horizontal: padH, vertical: padV),
            background: header ? ReportPdfTheme.accentTint : null,
            top: header ? border : null,
            left: c == 0 ? border : null,
            right: border,
            bottom: border,
            child: cssText(cells[c],
                sizePt: sizePt,
                weight: header ? 700 : 400,
                lineHeight: _lh),
          ),
      ],
    );
  }

  return [
    row(headers, header: true),
    for (final r in rows) row(r, header: false),
  ];
}

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
  final lines = _wrapLineCount(text, 10.5, width);
  return _Piece(
    lines * 15.75 + 3,
    _secondary(cssText(text,
        sizePt: 10.5,
        italic: true,
        color: _secondaryRgb,
        lineHeight: _lh)),
  );
}

/// Greedy word-wrap line count of [text] in [width] (white-space: normal).
int _wrapLineCount(String text, double sizePt, double width,
    {int weight = 400}) {
  var lines = 1;
  var cur = '';
  for (final word in text.split(' ')) {
    final next = cur.isEmpty ? word : '$cur $word';
    if (cur.isNotEmpty && measureText(next, sizePt, weight: weight) > width) {
      lines++;
      cur = word;
    } else {
      cur = next;
    }
  }
  return lines;
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

/// `.text-truncate` at the 76.5pt caption width: Chrome keeps the longest
/// prefix that fits with the ellipsis, including a trailing space (the shared
/// [truncateCaption] trims it).
String _truncate(String text) {
  final safe = pdfSafe(text).trim();
  if (_kernedWidth(safe) <= 76.5) return safe;
  for (var i = safe.length - 1; i >= 1; i--) {
    final candidate = '${safe.substring(0, i)}…';
    if (_kernedWidth(candidate) <= 76.5) return candidate;
  }
  return '…';
}

/// Width of [text] at 10.5pt as Chrome lays it out: the shared Selawik
/// advances (equal to Segoe UI's) minus Segoe UI's ASCII pair kerning, which
/// Chrome applies and the pdf package does not.
double _kernedWidth(String text) {
  var w = measureText(text, 10.5);
  for (var i = 0; i + 1 < text.length; i++) {
    w += (_segoeKern[text.substring(i, i + 2)] ?? 0) * 10.5 / 2048;
  }
  return w;
}

/// Segoe UI Regular GPOS pair kerning for printable ASCII, in 1/2048 em.
const Map<String, int> _segoeKern = {
  'AC': -40, 'AG': -40, 'AJ': 94, 'AO': -40, 'AT': -147, 'AU': -40,
  'AV': -140, 'AW': -140, 'AY': -140, 'AZ': 60, 'Av': -40, 'Aw': -40,
  'Ay': -40, 'BT': -92, 'BY': -66, 'CC': -55, 'CG': -55, 'CO': -55,
  'DA': -50, 'DT': -92, 'DV': -50, 'DW': -50, 'DX': -60, 'DZ': -50,
  'FA': -120, 'FJ': -66, 'Fa': -70, 'GT': -49, 'GV': -40, 'GW': -40,
  'GX': -40, 'Gy': -40, 'Gz': -40, 'JA': -50, 'JJ': -80, 'KC': -90,
  'KG': -90, 'KJ': 90, 'KO': -90, 'KV': 40, 'KW': 40, 'KX': 50, 'KY': 40,
  'KZ': 40, 'Kc': -27, 'Kd': -27, 'Ke': -27, 'Kg': -27, 'Ko': -50, 'Kq': -50,
  'Kt': -47, 'Kv': -70, 'Kw': -70, 'Kx': 30, 'Ky': -90, 'LA': 60, 'LC': -70,
  'LG': -66, 'LJ': 100, 'LO': -70, 'LT': -140, 'LU': -40, 'LV': -120,
  'LW': -120, 'LY': -120, 'LZ': 59, 'Lt': -27, 'Lv': -100, 'Lw': -100,
  'Ly': -100, 'OA': -50, 'OJ': -10, 'OT': -92, 'OV': -50, 'OW': -50,
  'OX': -50, 'OY': -50, 'OZ': -50, 'PA': -140, 'PJ': -129, 'PX': -50,
  'Pa': -70, 'Pc': -76, 'Pd': -76, 'Pe': -76, 'Pg': -76, 'Po': -76,
  'Pq': -76, 'QA': -50, 'QT': -92, 'QV': -50, 'QW': -50, 'QX': -50,
  'QY': -50, 'QZ': -50, 'RC': -29, 'RG': -29, 'RJ': 57, 'RO': -20, 'RT': -92,
  'RY': -39, 'Rc': -60, 'Rd': -60, 'Re': -60, 'Rg': -60, 'Ro': -60,
  'Rq': -53, 'St': -66, 'Sv': -50, 'Sw': -30, 'Sx': -30, 'Sy': -60,
  'Sz': -60, 'TA': -140, 'TC': -95, 'TG': -95, 'TJ': -113, 'TO': -95,
  'TS': -40, 'TT': 40, 'TV': 43, 'TW': 43, 'TY': 40, 'Ta': -230, 'Tc': -200,
  'Td': -200, 'Te': -200, 'Tf': -96, 'Tg': -200, 'Tm': -178, 'Tn': -178,
  'To': -200, 'Tp': -178, 'Tq': -200, 'Tr': -178, 'Ts': -154, 'Tv': -102,
  'Tw': -113, 'Tx': -180, 'Ty': -113, 'Tz': -113, 'UA': -50, 'VA': -120,
  'VC': -50, 'VG': -50, 'VJ': -70, 'VO': -50, 'VT': 39, 'Va': -150,
  'Vc': -130, 'Vd': -130, 'Ve': -130, 'Vg': -130, 'Vm': -80, 'Vn': -80,
  'Vo': -130, 'Vp': -76, 'Vq': -130, 'Vr': -76, 'Vs': -66, 'Vu': -50,
  'WA': -80, 'WT': 39, 'Wa': -80, 'Wc': -80, 'Wd': -80, 'We': -80, 'Wg': -80,
  'Wo': -80, 'Wq': -80, 'XC': -23, 'XG': -23, 'XJ': 96, 'XO': -23, 'XT': 33,
  'YA': -160, 'YC': -80, 'YG': -80, 'YJ': -66, 'YO': -80, 'YT': 39,
  'Ya': -180, 'Yc': -180, 'Yd': -180, 'Ye': -180, 'Yf': -27, 'Yg': -180,
  'Ym': -141, 'Yn': -141, 'Yo': -180, 'Yp': -140, 'Yq': -180, 'Yr': -141,
  'Ys': -133, 'ZJ': 82, 'ZT': 39, 'Zy': -53,
};

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
                            child: cssText(_truncate(line[i].caption),
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
