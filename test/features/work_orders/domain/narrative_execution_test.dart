import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/narrative_execution.dart';

Map<String, dynamic> _record({
  String mode = 'COMPLAINT',
  List<dynamic> lines = const [],
  Map<String, dynamic>? context,
}) =>
    {
      'id': 80,
      'work_order': 105,
      'lines': lines,
      'work_order_context': {
        'work_order_id': 105,
        'execution_mode': mode,
        'ticket_number': 'PNDM-202610-0001',
        'title': 'Fix: DG set not working',
        'description': 'portable dg set not working',
        'station_name': 'Pennadam',
        'status': 'IN_PROGRESS',
        'original_complaint_id': 17,
        'deficiency_details': null,
        ...?context,
      },
    };

void main() {
  group('NarrativeContext', () {
    test('uses the narrative form for COMPLAINT mode with no checklist lines', () {
      final c = NarrativeContext.fromRecordJson(_record());
      expect(c.usesNarrativeForm, isTrue);
      expect(c.workOrderId, 105);
      expect(c.ticketNumber, 'PNDM-202610-0001');
      expect(c.stationName, 'Pennadam');
      expect(c.isEditable, isTrue);
    });

    test('keeps the checklist when the record already has lines', () {
      final c = NarrativeContext.fromRecordJson(_record(lines: [
        {'id': 1}
      ]));
      expect(c.usesNarrativeForm, isFalse);
    });

    test('keeps the checklist for CHECKLIST mode', () {
      expect(NarrativeContext.fromRecordJson(_record(mode: 'CHECKLIST')).usesNarrativeForm, isFalse);
    });

    test('is read-only unless IN_PROGRESS', () {
      final c = NarrativeContext.fromRecordJson(_record(context: {'status': 'TECH_COMPLETED'}));
      expect(c.isEditable, isFalse);
    });

    test('parses deficiency details for a rectification Job Work', () {
      final c = NarrativeContext.fromRecordJson(_record(context: {
        'original_complaint_id': null,
        'deficiency_details': {
          'finding': 'not available / Pending',
          'equipment': 'EB Bunk',
          'checkpoint': 'Check whether 2 earth pits are available',
          'severity': 'Medium',
          'source_ticket': 'TLNR-202608-0015',
          'station_name': 'Thalanallur',
        },
      }));
      expect(c.deficiency, isNotNull);
      expect(c.deficiency!.finding, 'not available / Pending');
      expect(c.deficiency!.sourceTicket, 'TLNR-202608-0015');
      expect(c.originalComplaintId, isNull);
    });

    test('tolerates a record with no work_order_context', () {
      final c = NarrativeContext.fromRecordJson({'id': 1, 'work_order': 9, 'lines': <dynamic>[]});
      expect(c.usesNarrativeForm, isFalse);
      expect(c.workOrderId, 9);
    });
  });

  group('NarrativeExecution', () {
    test('parses text, parameters and photos by kind', () {
      final e = NarrativeExecution.fromJson({
        'initial_findings': 'Fan motor not running',
        'action_taken': 'Replaced motor',
        'final_remarks': 'Restored',
        'parameters': [
          {'parameter': 'Voltage', 'value': '230', 'unit': 'V'},
        ],
        'photos': [
          {'id': 1, 'kind': 'before', 'url': 'http://x/b.jpg', 'locked': true},
          {'id': 2, 'kind': 'AFTER', 'image': 'http://x/a.jpg'},
        ],
      });
      expect(e.initialFindings, 'Fan motor not running');
      expect(e.parameters.single.unit, 'V');
      expect(e.photosOf(NarrativePhotoKind.before).single.locked, isTrue);
      expect(e.photosOf(NarrativePhotoKind.after).single.url, 'http://x/a.jpg');
    });

    test('a parameter row needs both a parameter and a value', () {
      expect(const NarrativeParameter(parameter: 'V', value: '1').isComplete, isTrue);
      expect(const NarrativeParameter(parameter: 'V').isComplete, isFalse);
      expect(const NarrativeParameter(value: '1').isComplete, isFalse);
      expect(const NarrativeParameter(parameter: ' ', value: ' ').isComplete, isFalse);
    });

    test('empty payload yields an empty execution', () {
      final e = NarrativeExecution.fromJson({});
      expect(e.initialFindings, isEmpty);
      expect(e.photos, isEmpty);
      expect(e.parameters, isEmpty);
    });
  });
}
