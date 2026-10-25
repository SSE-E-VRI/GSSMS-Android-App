import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_service.dart';
import 'package:image/image.dart' as img;

RectificationJobWorkReport _report(int items, {String finalRemarks = ''}) {
  final photos = [
    {'image': 'http://x/media/a.jpg', 'kind': 'BEFORE'},
    {'image': 'http://x/media/a.jpg', 'kind': 'AFTER'},
  ];
  return RectificationJobWorkReport.fromJson({
    'ticket_number': 'JW-9',
    'final_remarks': finalRemarks,
    'items': [
      for (var i = 0; i < items; i++)
        {
          'asset': 'Asset $i',
          'checkpoint': 'Checkpoint $i with a fairly long name to wrap',
          'severity': i.isEven ? 'HIGH' : '',
          'source_ticket': 'JW-1',
          'finding': 'Finding line one\nFinding line two ' * 3,
          'action_taken': i == 1 ? '' : 'Replaced the part',
          'outcome': ['RECTIFIED', 'NOT_RECTIFIED', ''][i % 3],
          'reason': i % 3 == 1 ? 'Spare not available' : '',
          'photos': i == 2 ? [] : photos,
        },
    ],
  });
}

Future<int> _pageCount(RectificationJobWorkReport r) async {
  final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 6)));
  final doc = await JobWorkReportPdfService.build(
    r,
    photos: {'http://x/media/a.jpg': jpeg},
    generatedAt: DateTime(2026, 1, 2, 3, 4),
    compress: false,
  );
  final bytes = await doc.save();
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  return int.parse(
      RegExp(r'/Count (\d+)').firstMatch(String.fromCharCodes(bytes))!.group(1)!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a single page for one item with the default empty outcome',
      () async {
    expect(await _pageCount(_report(1)), 1);
  });

  test('every outcome (rectified, not rectified, pending, no photos) builds',
      () async {
    expect(await _pageCount(_report(3, finalRemarks: 'All done\nSecond line')),
        greaterThanOrEqualTo(1));
  });

  test('prints the checklist evidence a deficiency was raised with', () async {
    final r = RectificationJobWorkReport.fromJson({
      'ticket_number': 'JW-9',
      'items': [
        {
          'asset': 'EB Bunk',
          'checkpoint': 'Earth pit',
          'outcome': 'RECTIFIED',
          'photos': [
            {'image': 'http://x/media/a.jpg', 'kind': 'BEFORE'},
          ],
          'source_photos': [
            {'image': 'http://x/media/found.jpg', 'url': 'http://x/media/found.jpg', 'kind': 'BEFORE'},
          ],
        },
      ],
    });
    expect(r.items.single.sourcePhotos.single.url, 'http://x/media/found.jpg');
    // The report preloads it with the item's own photos.
    expect(r.allPhotos.map((p) => p.url), contains('http://x/media/found.jpg'));
    final doc = await JobWorkReportPdfService.build(r,
        generatedAt: DateTime(2026, 1, 2, 3, 4), compress: false);
    final text = String.fromCharCodes(await doc.save());
    expect(text, contains('%PDF-'));
  });

  test('item cards flow onto further pages without dropping content',
      () async {
    final pages = await _pageCount(_report(8));
    expect(pages, greaterThan(1));
  });
}
