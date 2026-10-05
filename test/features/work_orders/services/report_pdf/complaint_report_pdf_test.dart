// ignore_for_file: prefer_const_literals_to_create_immutables
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/complaint_report_pdf.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<int> _pages(ComplaintJobWorkReport r, Map<String, Uint8List?> photos,
    {int expectWidgets = 0}) async {
  await ReportFonts.load();
  ReportRoot.lineHeight = 1.4;
  final body = buildComplaintReportPdf(r, photos, DateTime(2026, 1, 2, 3, 4));
  if (expectWidgets > 0) expect(body.length, expectWidgets);
  final doc = pw.Document(compress: false);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(27.75),
    theme: pw.ThemeData.withFont(
        base: ReportFonts.regular, bold: ReportFonts.bold),
    build: (_) => body,
  ));
  final bytes = await doc.save();
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  return doc.document.pdfPageList.pages.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final jpeg =
      Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 30)));
  final photoJson = [
    for (var i = 0; i < 6; i++) {'image': 'http://x/b$i.jpg', 'kind': 'BEFORE'},
    {'image': 'http://x/a0.jpg', 'kind': 'AFTER'},
  ];
  final photos = <String, Uint8List?>{
    for (var i = 0; i < 6; i++) 'http://x/b$i.jpg': jpeg,
    'http://x/a0.jpg': null,
  };

  Map<String, dynamic> exec({bool withPhotos = true}) => {
        'initial_findings': 'Line one\nLine two\n\nLine four',
        'action_taken': 'Replaced the seal.',
        'final_remarks': 'Done',
        'submitted_by_name': 'Tech',
        'parameters': [
          {'parameter': 'Pressure', 'value': '8', 'unit': 'bar'},
          {'parameter': 'Time', 'value': '2', 'unit': ''},
        ],
        if (withPhotos) 'photos': photoJson,
      };

  test('deficiency kind builds header, 6 cards/blocks and keep-together tail',
      () async {
    final r = ComplaintJobWorkReport.fromJson(exec(), {
      'ticket_number': 'JW-1',
      'original_deficiency_details': {
        'severity': 'HIGH',
        'finding': 'Air leak\nsecond line',
      },
    });
    // header, section 1, initial, action, params, evidence, final+sign-off.
    expect(await _pages(r, photos, expectWidgets: 7), inInclusiveRange(1, 2));
  });

  test('breakdown (complaint) kind builds with a 4-item grid', () async {
    final r = ComplaintJobWorkReport.fromJson(exec(), {
      'ticket_number': 'JW-2',
      'original_complaint_details': {
        'complaint_number': 'C-1',
        'description': 'Signal failed',
      },
    });
    expect(await _pages(r, photos), inInclusiveRange(1, 2));
  });

  test('job work kind builds with all empty states', () async {
    final r = ComplaintJobWorkReport.fromJson(
        {'parameters': <dynamic>[]}, {'ticket_number': 'JW-3'});
    // No parameters card: header, section 1, initial, action, evidence, tail.
    expect(await _pages(r, const {}, expectWidgets: 6), 1);
  });

  test('long pre-wrap bodies and many photos paginate', () async {
    final para = List.filled(8, 'Replaced the compression fitting.').join(' ');
    final e = exec()
      ..['initial_findings'] = List.filled(12, para).join('\n\n')
      ..['action_taken'] = List.filled(12, para).join('\n\n');
    final r = ComplaintJobWorkReport.fromJson(e, {
      'ticket_number': 'JW-4',
      'original_deficiency_details': {'finding': para},
    });
    expect(await _pages(r, photos), greaterThan(1));
  });
}
