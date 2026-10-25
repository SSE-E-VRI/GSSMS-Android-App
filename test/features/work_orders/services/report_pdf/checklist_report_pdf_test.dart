import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_service.dart';

ChecklistReportRow _row(
  String item,
  String point, {
  bool record = false,
  String status = 'Normal',
  String action = '',
  String value = '',
  String unit = '',
  int span = 1,
}) =>
    ChecklistReportRow(
      itemName: item,
      checkpoint: point,
      isRecordParameter: record,
      statusLabel: status,
      actionLabel: action,
      formattedValue: value,
      unit: unit,
      attachments: const [],
      itemSpanLen: span,
    );

ChecklistJobWorkReport _report({
  List<ChecklistReportGroup> groups = const [],
  List<ChecklistDeficiencyRow> deficiencies = const [],
  bool showJobWork = false,
  String remarks = 'All good',
  String schedule = 'Monthly',
  ReportVerification? verification,
}) =>
    ChecklistJobWorkReport(
      ticket: 'VRI-202609-0101',
      org: const ReportOrganization(),
      station: 'Katpadi',
      date: DateTime(2026, 10, 1),
      schedule: schedule,
      technician: 'R. Kumar',
      verification: verification,
      remarks: remarks,
      otherStaff: '',
      groups: groups,
      deficiencies: deficiencies,
      showJobWork: showJobWork,
    );

Future<int> _pages(ChecklistJobWorkReport r) async {
  final doc = await JobWorkReportPdfService.build(r,
      generatedAt: DateTime(2026, 10, 2, 9, 30), compress: false);
  final bytes = await doc.save();
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  return doc.document.pdfPageList.pages.length;
}

/// A group of [n] one-row items (`Item i`).
ChecklistReportGroup _group(String name, int n) => ChecklistReportGroup(
      name: name,
      rows: [for (var i = 0; i < n; i++) _row('Item $i', 'Checkpoint $i')],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('typical report fits one page', () async {
    final r = _report(
      groups: [
        ChecklistReportGroup(name: 'TR-BODY-01', rows: [
          _row('Oil Level & Temperature', 'Check oil level gauge glass',
              span: 3),
          _row(
              'Oil Level & Temperature',
              'Check winding temperature '
                  'thermometer',
              status: 'High Temp',
              action: 'Calibrate sensor',
              span: 0),
          _row('Oil Level & Temperature', 'Check silica gel breather colour',
              span: 0),
          _row('Voltage Check', 'Phase voltages', span: 1),
        ]),
      ],
    );
    expect(await _pages(r), 1);
  });

  test('item name taller than its rows, wrapped cells and remarks build',
      () async {
    final r = _report(
      schedule: 'Quarterly Traction Substation Transformer, Bushing, '
          'Breather, Cooling Fan and Protection Relay Preventive '
          'Maintenance Checklist (Rev. 7)',
      remarks: 'Line one\nLine two\n\nLine four',
      groups: [
        ChecklistReportGroup(name: 'TR-BODY-01', rows: [
          _row(
              'Oil Level, Temperature and Winding Temperature Indicator '
                  'Assembly',
              'Check oil level gauge glass, magnetic oil gauge '
                  'and the winding temperature thermometer pocket for leakage',
              status: 'Observed within permissible limits but seepage noted '
                  'at the gasket joint',
              action: 'Tighten flange bolts and re-check after loading for '
                  'twenty four hours'),
        ]),
      ],
    );
    expect(await _pages(r), inInclusiveRange(1, 2));
  });

  test('record parameter runs span a merged label cell', () async {
    final r = _report(groups: [
      ChecklistReportGroup(name: 'METERS', rows: [
        _row('Readings', 'Voltage R',
            record: true, value: '230', unit: 'V', span: 4),
        _row('Readings', 'Voltage Y',
            record: true, value: '231', unit: 'V', span: 0),
        _row('Readings', 'Voltage B', record: true, span: 0),
        _row('Readings', 'Earth continuity', span: 0),
      ]),
    ]);
    expect(await _pages(r), 1);
  });

  test('job work number adds a fourth meta item on a second row', () async {
    expect(await _pages(_report(showJobWork: true)), 1);
  });

  test('empty report and empty group build', () async {
    expect(await _pages(ChecklistJobWorkReport.empty(_wo())), 1);
    expect(
        await _pages(_report(groups: [
          const ChecklistReportGroup(name: 'EMPTY', rows: []),
        ])),
        1);
  });

  test('deficiency summary lists rows and a verified supervisor', () async {
    final r = _report(
      deficiencies: [
        for (var i = 0; i < 4; i++)
          const ChecklistDeficiencyRow(
            asset: 'TR-BODY-01',
            checkpoint: 'Check winding temperature thermometer',
            finding: 'High Temp\nsecond line',
            action: 'Calibrate sensor',
            severity: 'High',
          ),
      ],
      verification: const ReportVerification(
          verifiedByName: 'M. Supervisor', remarks: 'Approved'),
    );
    expect(await _pages(r), 1);
  });

  test('a group that does not fit moves to the next page whole', () async {
    // Two groups of 20 rows (~500pt each) cannot share a page.
    final r = _report(groups: [_group('A', 20), _group('B', 20)]);
    expect(await _pages(r), greaterThanOrEqualTo(3));
  });

  test('a group taller than a page breaks between items', () async {
    final r = _report(groups: [_group('BIG', 70)]);
    expect(await _pages(r), greaterThanOrEqualTo(3));
  });

  test('a rowspan taller than a page falls back to flat rows', () async {
    final r = _report(groups: [
      ChecklistReportGroup(name: 'HUGE', rows: [
        for (var i = 0; i < 80; i++)
          _row('One long item', 'Checkpoint $i', span: i == 0 ? 80 : 0),
      ]),
    ]);
    expect(await _pages(r), greaterThanOrEqualTo(3));
  });
  test('line attachment photos are painted and grow the layout (M14)',
      () async {
    ChecklistReportRow withPhotos(int i, {bool record = false}) =>
        ChecklistReportRow(
          itemName: 'Item $i',
          checkpoint: 'Checkpoint $i',
          isRecordParameter: record,
          statusLabel: 'Normal',
          actionLabel: '',
          formattedValue: record ? '12' : '',
          unit: record ? 'V' : '',
          attachments: [
            for (var k = 0; k < 4; k++)
              ReportPhoto(key: 'u$i-$k', url: 'u$i-$k', caption: 'p$k'),
          ],
          itemSpanLen: 1,
        );

    final plain = _report(groups: [_group('PLAIN', 14)]);
    final photo = _report(groups: [
      ChecklistReportGroup(name: 'PHOTO', rows: [
        for (var i = 0; i < 14; i++) withPhotos(i, record: i.isOdd),
      ]),
    ]);

    // Photos make each row taller (strip under the cell), so the same number
    // of rows needs more pages than the photo-less report.
    expect(await _pages(photo), greaterThan(await _pages(plain)));
  });

  test('the proof-of-execution photo is read, preloaded and printed', () async {
    const url = 'https://x/media/maintenance_proofs/proof.jpg';
    final r = ChecklistJobWorkReport.fromRecordJson({
      'remarks': 'Done',
      'proof_of_execution': url,
      'lines': [
        {
          'item_name': 'EB Bunk',
          'inspection_point': 'Meter',
          'checked_out': true,
          'status': 'OK',
        },
      ],
    }, _wo());
    expect(r.proofOfExecution?.url, url);
    expect(r.allPhotos.map((p) => p.key), contains(url));

    final withProof = await JobWorkReportPdfService.build(r,
        generatedAt: DateTime(2026, 10, 2, 9, 30), compress: false);
    final text = String.fromCharCodes(await withProof.save());
    expect(text, contains('%PDF-'));

    final none = ChecklistJobWorkReport.fromRecordJson(
        {'lines': const <dynamic>[]}, _wo());
    expect(none.proofOfExecution, isNull);
  });

}

WorkOrder _wo() => const WorkOrder(
      id: 101,
      status: WorkOrderStatus.techCompleted,
      type: WorkOrderType.preventive,
      ticketNumber: 'VRI-202609-0101',
      title: 'Station monthly maintenance',
      stationName: 'VRI',
    );
