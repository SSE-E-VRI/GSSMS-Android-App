import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_service.dart';
import 'package:image/image.dart' as img;

Map<String, dynamic> _line(int i, {String item = 'DG Set', String? asset}) => {
      'asset_unique_id': asset ?? 'AST-1',
      'item_name': item,
      'inspection_point': 'Check point $i — • “quoted”',
      'item_kind': 'CHECKPOINT',
      'status': 'OK',
      'status_label_snapshot': 'Working',
      'action_label_snapshot': 'None',
      'attachments': [
        {'image': 'http://x/media/a.jpg', 'kind': 'BEFORE'},
        {'image': 'http://x/media/missing.jpg', 'kind': 'AFTER'},
      ],
    };

Future<void> _check(JobWorkReport r, Map<String, Uint8List?> photos) async {
  final doc = await JobWorkReportPdfService.build(r,
      photos: photos, generatedAt: DateTime(2026, 1, 2, 3, 4));
  final bytes = await doc.save();
  expect(bytes, isNotEmpty);
  expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 2, height: 2)));
  final photos = <String, Uint8List?>{
    'http://x/media/a.jpg': jpeg,
    'http://x/media/missing.jpg': null,
  };
  final photoJson = [
    {'image': 'http://x/media/a.jpg', 'kind': 'BEFORE'},
    {'image': 'http://x/media/missing.jpg', 'kind': 'AFTER'},
  ];

  test('pdfSafe maps non-Latin-1 punctuation', () {
    expect(pdfSafe('a—b • ‘x’ ₹5…'), 'a—b • ‘x’ Rs.5…');
  });

  test('checklist report builds with photos and merged cells', () async {
    final r = ChecklistJobWorkReport.fromRecordJson({
      'technician_name': 'Tech',
      'remarks': 'All good — done',
      'lines': [
        _line(1),
        _line(2),
        {
          ..._line(3, item: 'Voltage'),
          'item_kind': 'RECORD_PARAMETER',
          'recorded_value': '{"R":"230","Y":"231"}',
          'unit_snapshot': 'V',
        },
      ],
    }, _wo());
    await _check(r, photos);
  });

  test('60-line checklist paginates', () async {
    final r = ChecklistJobWorkReport.fromRecordJson({
      'lines': [
        for (var i = 0; i < 60; i++) _line(i, item: 'Item ${i ~/ 3}'),
      ],
    }, _wo());
    final doc = await JobWorkReportPdfService.build(r, photos: photos);
    await doc.save();
    expect(doc.document.pdfPageList.pages.length, greaterThan(1));
  });

  test('empty checklist builds', () async {
    await _check(ChecklistJobWorkReport.empty(_wo()), const {});
  });

  test('complaint report builds for each section 1 kind', () async {
    final exec = {
      'submission_history': [
        {
          'submission_no': 1,
          'timestamp': '2026-01-01T10:00:00Z',
          'initial_findings': 'Found — fault',
          'action_taken': 'Fixed',
          'final_remarks': 'OK',
          'parameters': [
            {'parameter': 'Voltage', 'value': '230', 'unit': 'V'}
          ],
          'photos': photoJson,
        }
      ],
    };
    for (final extra in <Map<String, dynamic>>[
      {
        'original_deficiency_details': {'severity': 'HIGH', 'finding': 'x'}
      },
      {
        'original_complaint_details': {
          'complaint_number': 'C-1',
          'description': 'd'
        }
      },
      <String, dynamic>{'title': 'T', 'description': 'D'},
    ]) {
      await _check(ComplaintJobWorkReport.fromJson(exec, {
        'ticket_number': 'JW-1',
        ...extra,
      }), photos);
    }
  });

  test('inspection report builds pointwise and legacy', () async {
    await _check(
        InspectionJobWorkReport.fromJson({
          'ticket_number': 'JW-2',
          'inspection_details': {
            'general_evidence_photos': photoJson,
            'points': [
              {'point_number': 1, 'observation': 'Obs'}
            ],
          },
          'submission_history': [
            {
              'submission_no': 2,
              'submitted_by_name': 'Tech',
              'point_snapshots': [
                {
                  'point_number': 1,
                  'observation': 'Obs • one',
                  'asset_name': 'Pump',
                  'priority': 'HIGH',
                  'corrective_action_performed': false,
                  'before_photos': photoJson,
                  'after_photos': <dynamic>[],
                }
              ],
            }
          ],
        }),
        photos);
    await _check(
        InspectionJobWorkReport.fromJson({
          'initial_findings': 'f',
          'inspection_details': {
            'points': [
              {'point_number': 1, 'observation': 'Obs'}
            ],
          },
          'photos': photoJson,
        }, fallbackTicket: 'JW-3'),
        photos);
  });

  test('rectification report builds', () async {
    await _check(
        RectificationJobWorkReport.fromJson({
          'ticket_number': 'JW-4',
          'final_remarks': 'Done — all',
          'verified_by': 'Sup',
          'items': [
            {
              'asset': 'Fan',
              'outcome': 'RECTIFIED',
              'photos': photoJson,
            },
            {'asset': 'Light', 'outcome': 'NOT_RECTIFIED', 'reason': 'No part'},
            {'asset': 'Pump'},
          ],
        }),
        photos);
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
