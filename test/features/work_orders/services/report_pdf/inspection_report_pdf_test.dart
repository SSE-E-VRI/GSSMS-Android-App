// ignore_for_file: prefer_const_literals_to_create_immutables
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/inspection_report_pdf.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Map<String, dynamic> _photo(String key, String caption) =>
    {'image': key, 'caption': caption};

InspectionJobWorkReport _pointwise({int points = 3, int photos = 2}) {
  return InspectionJobWorkReport.fromJson({
    'ticket_number': 'JW-1',
    'inspection_details': {
      'inspection_title': 'Quarterly audit',
      'inspection_remarks': 'Line one\nLine two',
      'general_evidence_photos': [
        for (var i = 0; i < photos; i++) _photo('http://x/$i.jpg', 'General $i'),
      ],
    },
    'submission_history': [
      {
        'submission_no': 1,
        'submitted_by_name': 'Tech',
        'point_snapshots': [
          for (var i = 1; i <= points; i++)
            {
              'point_number': i,
              'observation': 'Observation $i',
              'asset_name': 'ASSET-$i',
              'priority': 'HIGH',
              'initial_findings': 'Found $i',
              'corrective_action_performed': i != 1,
              'technical_parameters': [
                {'parameter': 'Torque', 'value': '12', 'unit': 'Nm'},
              ],
              'inspection_evidence_photos': [_photo('http://x/0.jpg', 'Ev')],
              'before_photos': [
                for (var k = 0; k < photos; k++) _photo('http://x/$k.jpg', 'B$k'),
              ],
              'after_photos': <dynamic>[],
            },
        ],
      }
    ],
  });
}

InspectionJobWorkReport _legacy() => InspectionJobWorkReport.fromJson({
      'initial_findings': 'f',
      'inspection_details': {
        'points': [
          {'point_number': 1, 'observation': 'Obs', 'priority': 'LOW'},
          {'point_number': 2, 'observation': 'Two'},
        ],
      },
      'photos': [
        {'image': 'http://x/0.jpg', 'photo_type': 'BEFORE', 'caption': 'c'},
      ],
    }, fallbackTicket: 'JW-2');

Future<pw.Document> _doc(List<pw.Widget> body) async {
  final doc = pw.Document(compress: false);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(27.75),
    theme: pw.ThemeData.withFont(
        base: ReportFonts.regular, bold: ReportFonts.bold),
    build: (_) => body,
  ));
  return doc;
}

int _pages(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(pdf)).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 400, height: 300)));
  final photos = <String, Uint8List?>{
    for (var i = 0; i < 8; i++) 'http://x/$i.jpg': jpeg,
  };
  final at = DateTime(2026, 10, 3, 9, 30);

  setUpAll(ReportFonts.load);
  setUp(() => ReportRoot.lineHeight = 1.5);

  test('pointwise report lays out and ends in a keep-together tail', () async {
    final body = buildInspectionReportPdf(_pointwise(), photos, at);
    expect(body.last, isA<AvoidBreakInside>());
    final bytes = await (await _doc(body)).save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(_pages(bytes), greaterThanOrEqualTo(1));
  });

  test('photo grids are emitted as separate page children', () {
    // One point: header + fields + table rows + grid bands + footer, so the
    // child count grows well beyond the old "one widget per point" layout.
    final one = buildInspectionReportPdf(_pointwise(points: 1), photos, at);
    final three = buildInspectionReportPdf(_pointwise(points: 3), photos, at);
    expect(one.length, greaterThan(8));
    expect(three.length, greaterThan(one.length));
  });

  test('a page break may fall between a thumbnail row and its captions',
      () async {
    final body = buildInspectionReportPdf(_pointwise(points: 1), photos, at);
    // Pad the page so the photo grid straddles the page bottom.
    var pages = 0;
    for (final pad in [330.0, 345.0, 360.0, 375.0, 390.0]) {
      final doc = await _doc([pw.SizedBox(height: pad), ...body]);
      pages = _pages(await doc.save());
      if (pages > 1) break;
    }
    expect(pages, greaterThan(1));
  });

  test('legacy report with covered points and photos builds', () async {
    final bytes = await (await _doc(buildInspectionReportPdf(
            _legacy(), photos, at)))
        .save();
    expect(_pages(bytes), 1);
  });

  test('empty report (no points) still produces a sign-off', () async {
    final r = InspectionJobWorkReport.fromJson(
        {'inspection_details': <String, dynamic>{}, 'submission_history': []},
        fallbackTicket: 'JW-3');
    final bytes =
        await (await _doc(buildInspectionReportPdf(r, const {}, at))).save();
    expect(_pages(bytes), 1);
  });
}
