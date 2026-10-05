import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

const _fmt = PdfPageFormat(595.92, 842.88);

/// One text-showing operation (a word) with its baseline origin in
/// top-down page coordinates.
class _Word {
  _Word(this.x, this.y, this.size);
  final double x;
  final double y;
  final double size;
}

/// Minimal content-stream reader: tracks `q`/`Q`/`cm` (affine), reads `Tf`
/// sizes and `Td` positions of every `BT ... ET` text object. Enough for the
/// uncompressed output of the pdf package.
List<_Word> _words(Uint8List pdf) {
  final text = String.fromCharCodes(pdf);
  final start = text.indexOf('stream');
  final end = text.indexOf('endstream', start);
  final tokens = text.substring(start + 6, end).trim().split(RegExp(r'\s+'));
  var m = <double>[1, 0, 0, 1, 0, 0];
  final stack = <List<double>>[];
  final words = <_Word>[];
  var size = 0.0;
  final nums = <double>[];
  for (final t in tokens) {
    final v = double.tryParse(t);
    if (v != null) {
      nums.add(v);
      continue;
    }
    switch (t) {
      case 'q':
        stack.add(List.of(m));
      case 'Q':
        m = stack.removeLast();
      case 'cm':
        final a = nums.sublist(nums.length - 6);
        // CTM' = M x CTM
        m = [
          a[0] * m[0] + a[1] * m[2],
          a[0] * m[1] + a[1] * m[3],
          a[2] * m[0] + a[3] * m[2],
          a[2] * m[1] + a[3] * m[3],
          a[4] * m[0] + a[5] * m[2] + m[4],
          a[4] * m[1] + a[5] * m[3] + m[5],
        ];
      case 'Tf':
        size = nums.last;
      case 'Td':
        final x = nums[nums.length - 2];
        final y = nums.last;
        words.add(_Word(
          x * m[0] + y * m[2] + m[4],
          _fmt.height - (x * m[1] + y * m[3] + m[5]),
          size,
        ));
    }
    nums.clear();
  }
  return words;
}

Future<List<_Word>> _render(pw.Widget widget) async {
  final doc = pw.Document(compress: false);
  doc.addPage(pw.Page(
    pageFormat: _fmt,
    margin: pw.EdgeInsets.zero,
    build: (c) => pw.Align(alignment: pw.Alignment.topLeft, child: widget),
  ));
  return _words(await doc.save());
}

/// Distinct baselines (top-down), in order.
List<double> _baselines(List<_Word> words) {
  final out = <double>[];
  for (final w in words) {
    if (out.isEmpty || (w.y - out.last).abs() > 0.01) out.add(w.y);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => ReportFonts.load());

  double expected(double top, double lh, double s, int k) =>
      top + (lh / 2 + 0.41405) * s + k * lh * s;

  test('cssBaselineEm matches the Segoe line box', () {
    expect(cssBaselineEm(1.5), closeTo(1.16405, 1e-9));
    expect(cssBaselineEm(1.2), closeTo(1.01405, 1e-9));
  });

  test('single line baseline = top + (L/2 + 0.41405) * s', () async {
    for (final (lh, s) in [(1.5, 10.2), (1.4, 12.0), (1.35, 10.2), (1.3, 9.0)]) {
      final w = await _render(
          pw.SizedBox(width: 300, child: cssText('Hello', sizePt: s, lineHeight: lh)));
      expect(_baselines(w), hasLength(1));
      expect(w.first.y, closeTo(expected(0, lh, s, 0), 0.05), reason: 'L=$lh s=$s');
    }
  });

  test('multi-line baselines step by exactly L * s', () async {
    const s = 9.75;
    for (final lh in [1.5, 1.4, 1.35]) {
      final w = await _render(pw.SizedBox(
        width: 70,
        child: cssText('alpha beta gamma delta epsilon zeta eta theta iota',
            sizePt: s, lineHeight: lh),
      ));
      final b = _baselines(w);
      expect(b.length, greaterThanOrEqualTo(3));
      for (var k = 0; k < b.length; k++) {
        expect(b[k], closeTo(expected(0, lh, s, k), 0.05), reason: 'L=$lh line $k');
      }
    }
  });

  test('L = 1.2 (negative bottom inset) keeps baselines and block height',
      () async {
    const s = 15.0;
    const lh = 1.2;
    expect(cssInsetBottom(lh, s), lessThan(0));
    final w = await _render(pw.SizedBox(
      width: 60,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          cssText('alpha beta gamma', sizePt: s, lineHeight: lh, weight: 700),
          // Follows a block of n lines, so its top must be n * L * s down.
          cssText('next', sizePt: 10, lineHeight: 1.5),
        ],
      ),
    ));
    final b = _baselines(w);
    final n = b.length - 1; // lines of the first block
    expect(n, greaterThanOrEqualTo(2));
    for (var k = 0; k < n; k++) {
      expect(b[k], closeTo(expected(0, lh, s, k), 0.05), reason: 'line $k');
    }
    expect(b[n], closeTo(expected(n * lh * s, 1.5, 10, 0), 0.05));
  });

  test('cssRich lays mixed runs on one baseline and wraps like cssText',
      () async {
    final w = await _render(pw.SizedBox(
      width: 120,
      child: cssRich(
        [
          const CssSpan('Label:', weight: 700),
          const CssSpan(' value that is long enough to wrap onto lines'),
        ],
        sizePt: 10.2,
        lineHeight: 1.4,
      ),
    ));
    final b = _baselines(w);
    expect(b.length, greaterThanOrEqualTo(2));
    for (var k = 0; k < b.length; k++) {
      expect(b[k], closeTo(expected(0, 1.4, 10.2, k), 0.05));
    }
  });

  test('autoColumnWidths follows the CSS auto-layout rule', () {
    // Sum of max fits: proportional to max.
    final fit = autoColumnWidths([20, 20], [100, 300], 800);
    expect(fit[0], closeTo(200, 1e-9));
    expect(fit[1], closeTo(600, 1e-9));
    // Overflow: grow from min in proportion to (max - min).
    final over = autoColumnWidths([50, 50], [150, 450], 400);
    expect(over.reduce((a, b) => a + b), closeTo(400, 1e-9));
    expect(over[0], closeTo(50 + 100 * (300 / 500), 1e-9));
    // Cannot even fit the minima: minima win.
    expect(autoColumnWidths([200, 300], [250, 350], 400), [200, 300]);
  });

  test('truncateCaption fits 76.5pt with an ellipsis', () {
    final t = truncateCaption('A very long photo caption that cannot fit');
    expect(t.endsWith('…'), isTrue);
    expect(measureText(t, 10.5), lessThanOrEqualTo(76.5));
    expect(truncateCaption('Short'), 'Short');
  });

  test('weight 500 maps to the semibold face', () {
    expect(identical(ReportFonts.fontForWeight(500), ReportFonts.semibold), isTrue);
    expect(identical(ReportFonts.fontForWeight(400), ReportFonts.regular), isTrue);
    expect(identical(ReportFonts.fontForWeight(700), ReportFonts.bold), isTrue);
  });

  test('CssBox: content starts at border + padding, box is border-box',
      () async {
    final w = await _render(CssBox.bordered(
      fillWidth: false,
      side: const CssSide(0.75, PdfColors.black),
      padding: const pw.EdgeInsets.all(2),
      margin: const pw.EdgeInsets.only(left: 5, top: 3),
      child: cssText('Hi', sizePt: 10, lineHeight: 1.5),
    ));
    expect(w, hasLength(1));
    expect(w.first.x, closeTo(5 + 0.75 + 2, 0.01));
    expect(w.first.y, closeTo(expected(3 + 0.75 + 2, 1.5, 10, 0), 0.05));
  });

  test('statusBadge is padded 1.2 + 0.75 border above a 1.3 line box', () async {
    final w = await _render(statusBadge('ok', 'OK'));
    // baseline = border + padding + (1.3 / 2 + 0.41405) * 9
    expect(w.first.y, closeTo(0.75 + 1.2 + (0.65 + 0.41405) * 9, 0.05));
    expect(w.first.size, 9.0);
  });
}
