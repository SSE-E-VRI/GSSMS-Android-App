import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_service.dart';

import '../../../report_parity/fixture_loader.dart';

const _fixtureIds = [
  'checklist_pm_full',
  'checklist_pm_minimal',
  'checklist_pm_long',
  'breakdown_deficiency',
  'breakdown_complaint',
  'breakdown_jobwork',
  'inspection_pointwise',
  'inspection_legacy',
  'rectification_mixed',
  'rectification_single',
];

const _expectedPageCounts = {
  'checklist_pm_full': 2,
  'checklist_pm_minimal': 1,
  'checklist_pm_long': 5,
  'breakdown_deficiency': 2,
  'breakdown_complaint': 1,
  'breakdown_jobwork': 1,
  'inspection_pointwise': 2,
  'inspection_legacy': 1,
  'rectification_mixed': 2,
  'rectification_single': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final goldenFile = File(
      'test/features/work_orders/services/goldens/job_work_report_layout_golden.json');
  final updateGoldens = Platform.environment['UPDATE_PDF_GOLDENS'] == '1';

  final Map<String, dynamic> goldenData =
      goldenFile.existsSync() && !updateGoldens
          ? jsonDecode(goldenFile.readAsStringSync()) as Map<String, dynamic>
          : <String, dynamic>{};

  final Map<String, dynamic> updatedData = <String, dynamic>{};

  tearDownAll(() async {
    if (updateGoldens && updatedData.isNotEmpty) {
      if (!goldenFile.parent.existsSync()) {
        goldenFile.parent.createSync(recursive: true);
      }
      final encoder = const JsonEncoder.withIndent('  ');
      goldenFile.writeAsStringSync('${encoder.convert(updatedData)}\n');
      // ignore: avoid_print
      print('Updated PDF layout golden at ${goldenFile.path}');
    }
  });

  group('JobWorkReportPdf layout snapshot golden regression tests', () {
    for (final id in _fixtureIds) {
      test('fixture $id layout matches golden snapshot', () async {
        final fixture = await FixtureLoader.load(id);
        final doc = await JobWorkReportPdfService.build(
          fixture.report,
          photos: fixture.photos,
          generatedAt: fixture.generatedAt,
        );

        final pages = doc.document.pdfPageList.pages;
        final pageCount = pages.length;
        expect(
          pageCount,
          equals(_expectedPageCounts[id]),
          reason: 'Page count for $id must match expected parity threshold',
        );

        final pageSizes = pages
            .map((p) => {
                  'width': double.parse(p.pageFormat.width.toStringAsFixed(2)),
                  'height': double.parse(p.pageFormat.height.toStringAsFixed(2)),
                })
            .toList();

        final snapshot = {
          'pageCount': pageCount,
          'pageSizes': pageSizes,
          'objectCount': doc.document.objects.length,
        };

        if (updateGoldens) {
          updatedData[id] = snapshot;
        } else {
          expect(
            goldenData.containsKey(id),
            isTrue,
            reason: 'Golden snapshot missing for $id in ${goldenFile.path}. '
                'Run with UPDATE_PDF_GOLDENS=1 to generate.',
          );
          final expected = goldenData[id] as Map<String, dynamic>;
          expect(snapshot['pageCount'], equals(expected['pageCount']));
          expect(snapshot['pageSizes'], equals(expected['pageSizes']));
          expect(snapshot['objectCount'], equals(expected['objectCount']));
        }

        final bytes = await doc.save();
        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      });
    }
  });
}
