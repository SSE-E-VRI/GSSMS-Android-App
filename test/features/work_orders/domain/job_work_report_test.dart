// ignore_for_file: prefer_const_literals_to_create_immutables, prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

WorkOrder _wo({
  String? ticket = 'JW-1',
  String? assignedTo = 'Tech A',
  String? station = 'Station X',
}) =>
    WorkOrder(
      id: 1,
      status: WorkOrderStatus.techCompleted,
      type: WorkOrderType.preventive,
      ticketNumber: ticket,
      title: 'Monthly PM',
      assignedToName: assignedTo,
      stationName: station,
      reportCompletedAt: DateTime(2026, 9, 9),
    );

Map<String, dynamic> _line(Map<String, dynamic> over) => {
      'item_name': 'Panel',
      'inspection_point': 'Check',
      'asset_unique_id': 'A1',
      ...over,
    };

void main() {
  group('helpers', () {
    test('reportStatusLabel', () {
      expect(
          reportStatusLabel(snapshot: 'Good', status: 'OK', addressed: true),
          'Good');
      expect(reportStatusLabel(status: 'NA', addressed: true),
          'Not applicable');
      expect(reportStatusLabel(status: 'NA', addressed: false),
          'Not recorded');
      expect(reportStatusLabel(addressed: true), 'Not recorded');
    });

    test('formatRecordedValue', () {
      expect(formatRecordedValue('{"R": 230, "Y": 231, "B": null, "N": ""}'),
          'R: 230, Y: 231');
      expect(formatRecordedValue({'a': 1}), 'a: 1');
      expect(formatRecordedValue('12.5'), '12.5');
      expect(formatRecordedValue('{bad'), '{bad');
      expect(formatRecordedValue(null), '');
      expect(formatRecordedValue(''), '');
    });
  });

  group('shared types', () {
    test('ReportOrganization fallbacks', () {
      expect(ReportOrganization.fromJson(null).railwayName, 'RAILWAY');
      final o = ReportOrganization.fromJson({
        'railway_name': 'southern',
        'register_title': 'Reg Title',
      }, useRegisterTitle: true);
      expect(o.railwayName, 'SOUTHERN');
      expect(o.divisionName, 'Division');
      expect(o.depotName, 'Reg Title');
    });

    test('ReportVerification is null without a name', () {
      expect(ReportVerification.fromJson(null), isNull);
      expect(ReportVerification.fromJson({'verified_by_name': ''}), isNull);
      final v = ReportVerification.fromJson({
        'verified_by_name': 'Sup',
        'verified_at': '2026-09-09T10:00:00',
        'remarks': 'ok',
      })!;
      expect(v.verifiedByName, 'Sup');
      expect(v.remarks, 'ok');
      expect(v.verifiedAt, isNotNull);
    });

    test('ReportPhoto reads image ?? url and kind ?? photo_type', () {
      final photos = ReportPhoto.listOf([
        {'image': 'http://h/media/a.jpg', 'kind': 'before'},
        {'url': '/media/b.jpg', 'photo_type': 'AFTER'},
        {'caption': 'no url'},
      ]);
      expect(photos, hasLength(2));
      expect(photos[0].key, 'http://h/media/a.jpg');
      expect(photos[0].kind, 'BEFORE');
      expect(photos[1].url, '/media/b.jpg');
      expect(photos[1].kind, 'AFTER');
    });
  });

  group('ChecklistJobWorkReport', () {
    test('skips unchecked/excluded lines and groups with fallbacks', () {
      final r = ChecklistJobWorkReport.fromRecordJson({
        'lines': [
          _line({'checked_out': false, 'item_name': 'skipme'}),
          _line({'excluded': true, 'item_name': 'skipme2'}),
          _line({'item_name': 'one'}),
          _line({'asset_unique_id': null, 'asset_category': 'Cat'}),
          _line({'asset_unique_id': null}),
        ],
      }, _wo());
      expect(r.groups.map((g) => g.name), ['A1', 'Cat', 'General Items']);
      expect(r.groups[0].rows.single.itemName, 'one');
      expect(r.isEmpty, isFalse);
    });

    test('status label addressed logic', () {
      final r = ChecklistJobWorkReport.fromRecordJson({
        'lines': [
          _line({'status_label_snapshot': 'Healthy'}),
          _line({'status': 'NA', 'observation_action': 'n/a here'}),
          _line({'status': 'OK'}),
          _line({}),
          _line({'status': 'NA'}),
        ],
      }, _wo());
      final labels = r.groups.single.rows.map((x) => x.statusLabel).toList();
      expect(labels,
          ['Healthy', 'Not applicable', 'Not recorded', 'Not recorded', 'Not applicable']);
    });

    test('item and record-parameter spans', () {
      Map<String, dynamic> rp(String name) => _line({
            'item_name': 'Meter',
            'item_kind': 'RECORD_PARAMETER',
            'inspection_point': name,
            'recorded_value': '{"R": 230, "Y": 231}',
            'unit_snapshot': 'V',
          });
      final r = ChecklistJobWorkReport.fromRecordJson({
        'lines': [
          _line({'item_name': 'Panel'}),
          rp('Voltage'),
          rp('Current'),
          _line({'item_name': 'Panel'}),
        ],
      }, _wo());
      final rows = r.groups.single.rows;
      expect(rows.map((x) => x.itemSpanLen), [1, 2, 0, 1]);
      expect(rows.map((x) => x.paramSpanLen), [0, 2, 0, 0]);
      expect(rows[1].itemSpanStart, isTrue);
      expect(rows[2].itemSpanStart, isFalse);
      expect(rows[1].paramSpanStart, isTrue);
      expect(rows[1].formattedValue, 'R: 230, Y: 231');
      expect(rows[1].unit, 'V');
      expect(rows[0].actionDisplay, '-');
    });

    test('deficiencies from status or action option, severity fallback', () {
      final r = ChecklistJobWorkReport.fromRecordJson({
        'lines': [
          _line({
            'id': 1,
            'status_option': 5,
            'action_option': 9,
            'status_options': [
              {
                'id': 5,
                'label': 'Defective',
                'is_deficiency': true,
                'action_options': [
                  {'id': 9, 'label': 'Replace'}
                ],
              }
            ],
            'deficiency_severity_label': 'Major',
          }),
          _line({
            'id': 2,
            'status_option': '6',
            'action_option': '7',
            'status_label_snapshot': 'Worn',
            'status_options': [
              {
                'id': 6,
                'label': 'Worn',
                'action_options': [
                  {'id': 7, 'label': 'Monitor', 'is_deficiency': true}
                ],
              }
            ],
          }),
          _line({
            'id': 3,
            'status_option': 1,
            'status_options': [
              {'id': 1, 'label': 'Fine'}
            ],
          }),
          _line({
            'id': 4,
            'excluded': true,
            'status_option': 5,
            'status_options': [
              {'id': 5, 'is_deficiency': true}
            ],
          }),
        ],
      }, _wo());
      expect(r.deficiencies, hasLength(2));
      expect(r.deficiencies[0].finding, 'Defective');
      expect(r.deficiencies[0].action, 'Replace');
      expect(r.deficiencies[0].severity, 'Major');
      expect(r.deficiencies[1].action, 'Monitor');
      expect(r.deficiencies[1].severity, 'Pending review');
    });

    test('metadata, verification, organization, attachments', () {
      final r = ChecklistJobWorkReport.fromRecordJson({
        'date_of_maintenance': '2026-09-10',
        'technician_name': 'Rec Tech',
        'remarks': 'all good',
        'other_staff': 'Helper',
        'verification': {
          'verified_by_name': 'Sup',
          'verified_at': '2026-09-11T09:30:00',
          'remarks': 'fine',
        },
        'schedule_details': {
          'station_name': 'Sched Stn',
          'template_name': 'Quarterly',
          'organization': {'railway_name': 'sr', 'division_name': 'MAS'},
        },
        'lines': [
          _line({
            'attachments': [
              {'image': '/media/a.jpg', 'kind': 'BEFORE'}
            ],
          }),
        ],
      }, _wo());
      expect(r.station, 'Sched Stn');
      expect(r.schedule, 'Quarterly');
      expect(r.technician, 'Rec Tech');
      expect(r.dateLabel, '10/09/2026');
      expect(r.remarks, 'all good');
      expect(r.otherStaff, 'Helper');
      expect(r.verification!.verifiedByName, 'Sup');
      expect(r.org.railwayName, 'SR');
      expect(r.org.divisionName, 'MAS');
      expect(r.groups.single.rows.single.attachments.single.kind, 'BEFORE');
      expect(r.allPhotos.map((p) => p.url), ['/media/a.jpg']);
      expect(r.ticket, 'JW-1');
    });

    test('falls back to work order fields without schedule_details', () {
      final r = ChecklistJobWorkReport.fromRecordJson({'lines': []}, _wo());
      expect(r.station, 'Station X');
      expect(r.schedule, 'Monthly PM');
      expect(r.technician, 'Tech A');
      expect(r.dateLabel, '09/09/2026');
      expect(r.verification, isNull);
      expect(r.isEmpty, isTrue);
    });

    test('empty() has no groups', () {
      final r = ChecklistJobWorkReport.empty(_wo());
      expect(r.isEmpty, isTrue);
      expect(r.groups, isEmpty);
      expect(r.deficiencies, isEmpty);
      expect(r.title, 'Preventive Maintenance Report');
    });
  });

  group('ComplaintJobWorkReport', () {
    final photos = [
      {'image': '/media/b.jpg', 'kind': 'BEFORE'},
      {'image': '/media/a.jpg', 'kind': 'AFTER'},
    ];

    test('uses the latest submission over live fields', () {
      final r = ComplaintJobWorkReport.fromJson({
        'initial_findings': 'live',
        'photos': const [],
        'organization': {'railway_name': 'sr'},
        'verification': {'verified_by_name': 'Sup'},
        'submission_history': [
          {'submission_no': 1, 'initial_findings': 'first'},
          {
            'submission_no': 2,
            'timestamp': '2026-09-12T10:00:00',
            'initial_findings': 'second',
            'action_taken': 'fixed',
            'final_remarks': 'done',
            'submitted_by_name': 'Sub Name',
            'parameters': [
              {'parameter': 'V', 'value': 230, 'unit': 'V'}
            ],
            'photos': photos,
          },
        ],
      }, {
        'ticket_number': 'BD-9',
        'station_name': 'Stn',
      });
      expect(r.initialFindings, 'second');
      expect(r.actionTaken, 'fixed');
      expect(r.finalRemarks, 'done');
      expect(r.submitter, 'Sub Name');
      expect(r.submission!.number, '2');
      expect(r.parameters.single.value, '230');
      expect(r.beforePhotos.single.url, '/media/b.jpg');
      expect(r.afterPhotos.single.url, '/media/a.jpg');
      expect(r.verification!.verifiedByName, 'Sup');
      expect(r.org.railwayName, 'SR');
      expect(r.ticket, 'BD-9');
      expect(r.location, 'Stn');
      expect(r.dateLabel, '12/09/2026');
      expect(r.allPhotos, hasLength(2));
    });

    test('section 1 precedence: deficiency > complaint > job work', () {
      final both = ComplaintJobWorkReport.fromJson({}, {
        'original_deficiency_details': {'source_ticket': 'D-1'},
        'original_complaint_details': {'complaint_number': 'C-1'},
      });
      expect(both.section1Kind, ComplaintSection1Kind.deficiency);
      expect(both.deficiencyDetails!.sourceTicket, 'D-1');
      expect(both.deficiencyDetails!.severity, 'N/A');

      final complaint = ComplaintJobWorkReport.fromJson({}, {
        'original_complaint_details': {
          'complaint_number': 'C-1',
          'failure_date': '2026-09-01',
          'failure_time': '14:05:00',
          'general_asset_description': 'Lobby fan',
        },
        'description': 'wo desc',
      });
      expect(complaint.section1Kind, ComplaintSection1Kind.complaint);
      expect(complaint.complaintDetails!.failureDateTime,
          '01/09/2026 14:05');
      expect(complaint.complaintDetails!.reportedAsset, 'Lobby fan');
      expect(complaint.complaintDetails!.description, 'wo desc');
      expect(complaint.complaintDetails!.complainant, 'N/A');

      final none = ComplaintJobWorkReport.fromJson({}, {
        'title': 'Fix',
        'description': 'Door',
      });
      expect(none.section1Kind, ComplaintSection1Kind.jobWork);
      expect(none.assetName, 'General');
      expect(none.workToBeDone, 'Fix \u2014 Door');
    });

    test('submitter fallback chain', () {
      String submitter(Map<String, dynamic> exec, Map<String, dynamic> wo) =>
          ComplaintJobWorkReport.fromJson(exec, wo).submitter;
      expect(submitter({'submitted_by': 'S'}, {}), 'S');
      expect(submitter({'updated_by_name': 'U'}, {'assigned_to_name': 'A'}),
          'U');
      expect(submitter({}, {'assigned_to_name': 'A'}), 'A');
      expect(submitter({}, {}), 'Unknown');
    });

    test('ticket and station fallbacks', () {
      final r = ComplaintJobWorkReport.fromJson({}, {'depot_name': 'Depot'},
          fallbackTicket: 'WO #5');
      expect(r.ticket, 'WO #5');
      expect(r.location, 'Depot');
      expect(ComplaintJobWorkReport.fromJson({}, {}).location, 'Unknown');
    });
  });

  group('InspectionJobWorkReport', () {
    test('latest submission with point_snapshots gives pointwise rows', () {
      final r = InspectionJobWorkReport.fromJson({
        'ticket_number': 'IN-1',
        'verification': {'verified_by_name': 'Sup'},
        'inspection_details': {
          'station_name': 'Stn',
          'inspection_date': '2026-09-05',
          'inspection_time': '09:15:00',
          'inspection_number': 'INS-7',
          'original_observation': 'obs',
          'general_evidence_photos': [
            {'image': '/media/g.jpg'}
          ],
          'organization': {'depot_name': 'Dep'},
        },
        'submission_history': [
          {'submission_no': 1},
          {
            'submission_no': 2,
            'submitted_by': 'Tech',
            'timestamp': '2026-09-06T08:00:00',
            'point_snapshots': [
              {
                'point_number': 1,
                'observation': 'Loose bolt',
                'asset_name': 'Pole',
                'priority': 'HIGH',
                'initial_findings': 'f',
                'corrective_action_performed': false,
                'technical_parameters': [
                  {'parameter': 'T', 'value': '5', 'unit': ''}
                ],
                'before_photos': [
                  {'image': '/media/b.jpg'}
                ],
                'after_photos': [],
                'inspection_evidence_photos': [
                  {'image': '/media/e.jpg'}
                ],
              },
            ],
          },
        ],
      });
      expect(r.points, hasLength(1));
      final p = r.points.single;
      expect(p.isLegacy, isFalse);
      expect(p.pointNumber, 1);
      expect(p.assetName, 'Pole');
      expect(p.correctiveActionPerformed, isFalse);
      expect(p.technicalParameters.single.parameter, 'T');
      expect(r.submission!.number, '2');
      expect(r.technician, 'Tech');
      expect(r.verification!.verifiedByName, 'Sup');
      expect(r.inspectionRemarks, 'obs');
      expect(r.inspectionNumber, 'INS-7');
      expect(r.inspector, 'N/A');
      expect(r.dateLabel, '05/09/2026 09:15');
      expect(r.org.depotName, 'Dep');
      expect(r.allPhotos.map((x) => x.url),
          ['/media/g.jpg', '/media/e.jpg', '/media/b.jpg']);
    });

    test('submission without snapshots gives a legacy row', () {
      final r = InspectionJobWorkReport.fromJson({
        'inspection_details': {
          'points': [
            {'point_number': 2, 'observation': 'Rust', 'priority': 'LOW'},
            {'description': 'Crack'},
          ],
        },
        'submission_history': [
          {
            'submission_no': 1,
            'findings_summary': 'summary',
            'technician_remarks': 'remarks',
            'photos': [
              {'image': '/media/a.jpg', 'photo_type': 'AFTER'},
            ],
          },
        ],
      });
      final p = r.points.single;
      expect(p.isLegacy, isTrue);
      expect(p.initialFindings, 'summary');
      expect(p.finalRemarks, 'remarks');
      expect(p.afterPhotos.single.url, '/media/a.jpg');
      expect(r.coveredPoints.map((c) => c.number), [2, 2]);
      expect(r.coveredPoints[1].text, 'Crack');
    });

    test('no submission + is_pointwise uses points[].execution', () {
      final r = InspectionJobWorkReport.fromJson({
        'is_pointwise': true,
        'points': [
          {
            'observation': 'A',
            'execution': {
              'initial_findings': 'x',
              'photos': [
                {'image': '/media/1.jpg', 'photo_type': 'BEFORE'},
                {'image': '/media/2.jpg', 'photo_type': 'AFTER'},
              ],
              'inspection_evidence_photos': [
                {'image': '/media/3.jpg'}
              ],
            },
          },
          {'point_number': 7, 'description': 'B'},
        ],
      });
      expect(r.points, hasLength(2));
      expect(r.points[0].pointNumber, 1);
      expect(r.points[1].pointNumber, 7);
      expect(r.points[1].observation, 'B');
      expect(r.points[0].beforePhotos.single.url, '/media/1.jpg');
      expect(r.points[0].afterPhotos.single.url, '/media/2.jpg');
      expect(r.points[0].inspectionEvidencePhotos.single.url, '/media/3.jpg');
      expect(r.submission, isNull);
      expect(r.technician, '');
    });

    test('legacy payload and ticket fallback', () {
      final r = InspectionJobWorkReport.fromJson({
        'initial_findings': 'legacy',
        'corrective_action_performed': false,
      }, fallbackTicket: 'WO #3');
      expect(r.ticket, 'WO #3');
      expect(r.points.single.isLegacy, isTrue);
      expect(r.points.single.initialFindings, 'legacy');
      expect(r.points.single.correctiveActionPerformed, isFalse);
      expect(r.station, '—');
    });
  });

  group('RectificationJobWorkReport', () {
    test('counts, split photos, verification, fallbacks', () {
      final r = RectificationJobWorkReport.fromJson({
        'report_date': '2026-09-20',
        'final_remarks': 'closed',
        'technician': 'Tech',
        'other_staff': 'Help',
        'verified_by': 'Sup',
        'verified_at': '2026-09-21T10:00:00',
        'verified_remarks': 'ok',
        'items': [
          {
            'asset': 'Fan',
            'checkpoint': 'Blade',
            'source_ticket': 'D-1',
            'detected_at': '2026-09-01',
            'outcome': 'RECTIFIED',
            'photos': [
              {'image': '/media/b.jpg', 'kind': 'BEFORE'},
              {'image': '/media/a.jpg', 'kind': 'AFTER'},
            ],
          },
          {'asset': 'Door', 'outcome': 'NOT_RECTIFIED', 'reason': 'no part'},
          {'asset': 'Lamp'},
        ],
      }, fallbackTicket: 'WO #2', fallbackStation: 'Stn');
      expect(r.totalCount, 3);
      expect(r.rectifiedCount, 1);
      expect(r.notRectifiedCount, 1);
      expect(r.summaryLine, '3 items · 1 rectified · 1 not rectified');
      expect(r.items[2].outcome, RectificationOutcome.pending);
      expect(r.items[0].beforePhotos.single.url, '/media/b.jpg');
      expect(r.items[0].afterPhotos.single.url, '/media/a.jpg');
      expect(r.items[0].sourceLabel, 'D-1 · 01/09/2026');
      expect(r.items[1].reason, 'no part');
      expect(r.items[1].severity, 'N/A');
      expect(r.verification!.verifiedByName, 'Sup');
      expect(r.verification!.remarks, 'ok');
      expect(r.ticket, 'WO #2');
      expect(r.location, 'Stn');
      expect(r.dateLabel, '20/09/2026');
      expect(r.allPhotos.map((p) => p.url), ['/media/b.jpg', '/media/a.jpg']);
    });

    test('verification null when verified_by is empty; singular item', () {
      final r = RectificationJobWorkReport.fromJson({
        'verified_by': '',
        'items': [
          {'asset': 'x'}
        ],
      });
      expect(r.verification, isNull);
      expect(r.summaryLine, '1 item · 0 rectified · 0 not rectified');
    });
  });
}
