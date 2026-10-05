import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_service.dart';

import '../../../report_parity/fixture_loader.dart';
import 'pdf_layout_probe.dart';

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
  'checklist_pm_stress',
  'breakdown_long',
  'rectification_long',
  'register_checklist',
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
  'checklist_pm_stress': 2,
  'breakdown_long': 2,
  'rectification_long': 3,
  'register_checklist': 2,
};

/// Geometry tolerance (pt) for word/rect/line positions against the
/// committed snapshots. Text, font, size and colour must match exactly;
///
/// Chrome pixel-snapping alone moves box edges by up to ~0.75pt, so the
/// tolerance only guards our own layout: any systematic drift shows up as
/// many entries breaching it at once.
const double _geomTol = 0.25;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final goldenFile = File(
      'test/features/work_orders/services/goldens/job_work_report_layout_golden.json');
  final layoutGoldenFile = File(
      'test/features/work_orders/services/goldens/pdf_layout_golden.json');
  final updateGoldens = Platform.environment['UPDATE_PDF_GOLDENS'] == '1';

  final Map<String, dynamic> goldenData =
      goldenFile.existsSync() && !updateGoldens
          ? jsonDecode(goldenFile.readAsStringSync()) as Map<String, dynamic>
          : <String, dynamic>{};
  final Map<String, dynamic> layoutGoldenData =
      layoutGoldenFile.existsSync() && !updateGoldens
          ? jsonDecode(layoutGoldenFile.readAsStringSync())
              as Map<String, dynamic>
          : <String, dynamic>{};

  final Map<String, dynamic> updatedData = <String, dynamic>{};
  final Map<String, dynamic> updatedLayout = <String, dynamic>{};

  tearDownAll(() async {
    if (updateGoldens && updatedData.isNotEmpty) {
      if (!goldenFile.parent.existsSync()) {
        goldenFile.parent.createSync(recursive: true);
      }
      const encoder = JsonEncoder.withIndent('  ');
      goldenFile.writeAsStringSync('${encoder.convert(updatedData)}\n');
      // ignore: avoid_print
      print('Updated PDF layout golden at ${goldenFile.path}');
    }
    if (updateGoldens && updatedLayout.isNotEmpty) {
      const encoder = JsonEncoder.withIndent('  ');
      layoutGoldenFile
          .writeAsStringSync('${encoder.convert(updatedLayout)}\n');
      // ignore: avoid_print
      print('Updated PDF geometry golden at ${layoutGoldenFile.path}');
    }
  });

  group('JobWorkReportPdf layout snapshot golden regression tests', () {
    for (final id in _fixtureIds) {
      test('fixture $id layout matches golden snapshot', () async {
        final fixture = await FixtureLoader.load(id);
        // Twice: the second build proves the layout is deterministic.
        Future<Uint8List> render() async {
          final doc = await JobWorkReportPdfService.build(
            fixture.report,
            photos: fixture.photos,
            generatedAt: fixture.generatedAt,
            compress: false,
          );
          return doc.save();
        }

        final bytes = await render();
        final again = await render();
        final first = probePdfLayout(bytes);
        final second = probePdfLayout(again);
        expect(
          jsonEncode(second),
          equals(jsonEncode(first)),
          reason: 'Layout probe of $id must be deterministic across builds',
        );

        final pages = first['words'] as List;
        final pageCount =
            (first['words'] as List).isEmpty && (first['rects'] as List).isEmpty
                ? 0
                : {
                    for (final e in [
                      ...(first['words'] as List),
                      ...(first['rects'] as List),
                      ...(first['lines'] as List),
                    ])
                      (e as Map)['page'],
                  }.length;
        expect(
          pageCount,
          equals(_expectedPageCounts[id]),
          reason: 'Page count for $id must match expected parity threshold',
        );
        expect(pages, isNotEmpty,
            reason: 'Probe must extract words for $id');

        if (updateGoldens) {
          updatedLayout[id] = first;
        } else {
          expect(
            layoutGoldenData.containsKey(id),
            isTrue,
            reason: 'Geometry golden missing for $id in '
                '${layoutGoldenFile.path}. Run with UPDATE_PDF_GOLDENS=1.',
          );
          final expected =
              layoutGoldenData[id] as Map<String, dynamic>;
          _expectGeometryLike(id, expected, first);
        }

        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      });
    }

    for (final id in _fixtureIds) {
      test('fixture $id page metrics match golden snapshot', () async {
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
                  'height':
                      double.parse(p.pageFormat.height.toStringAsFixed(2)),
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

void _expectGeometryLike(
    String id, Map<String, dynamic> expected, Map<String, dynamic> actual) {
  final problems = <String>[];

  void checkList(String key, bool Function(Map a, Map e, int i) same,
      String Function(Map a, Map e, int i) describe) {
    final exp = (expected[key] as List).cast<Map>();
    final got = (actual[key] as List).cast<Map>();
    if (exp.length != got.length) {
      problems.add(
          '$key count: expected ${exp.length}, got ${got.length}');
      return;
    }
    for (var i = 0; i < exp.length; i++) {
      if (!same(got[i], exp[i], i)) {
        problems.add(describe(got[i], exp[i], i));
        if (problems.length >= 10) return;
      }
    }
  }

  bool closeNum(dynamic a, dynamic e) =>
      a is num && e is num && (a - e).abs() <= _geomTol;

  checkList('words', (a, e, i) {
    return a['page'] == e['page'] &&
        a['text'] == e['text'] &&
        a['font'] == e['font'] &&
        a['size'] == e['size'] &&
        a['color'] == e['color'] &&
        closeNum(a['x'], e['x']) &&
        closeNum(a['y'], e['y']);
  }, (a, e, i) {
    return 'word#$i page${a['page']}: expected ${e['text']} @(${e['x']},${e['y']}) '
        '${e['font']} ${e['size']} ${e['color']}, got ${a['text']} '
        '@(${a['x']},${a['y']}) ${a['font']} ${a['size']} ${a['color']}';
  });

  checkList('rects', (a, e, i) {
    return a['page'] == e['page'] &&
        closeNum(a['x'], e['x']) &&
        closeNum(a['y'], e['y']) &&
        closeNum(a['w'], e['w']) &&
        closeNum(a['h'], e['h']) &&
        (a['fill'] ?? '') == (e['fill'] ?? '') &&
        (a['stroke'] ?? '') == (e['stroke'] ?? '') &&
        closeNum(a['width'] ?? 0, e['width'] ?? 0);
  }, (a, e, i) {
    return 'rect#$i page${a['page']}: expected $e, got $a';
  });

  checkList('lines', (a, e, i) {
    return a['page'] == e['page'] &&
        closeNum(a['x1'], e['x1']) &&
        closeNum(a['y1'], e['y1']) &&
        closeNum(a['x2'], e['x2']) &&
        closeNum(a['y2'], e['y2']) &&
        a['stroke'] == e['stroke'] &&
        closeNum(a['width'], e['width']);
  }, (a, e, i) {
    return 'line#$i page${a['page']}: expected $e, got $a';
  });

  expect(
    problems,
    isEmpty,
    reason: 'Geometry drift in $id (tolerance ${_geomTol}pt):\n'
        '${problems.take(10).join('\n')}',
  );
}
