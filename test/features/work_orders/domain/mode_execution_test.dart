import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

WorkOrder _wo({
  int? complaint,
  int? deficiency,
  int? inspection,
  String? mode,
  String type = 'CORRECTIVE',
}) {
  return WorkOrder(
    id: 1,
    status: WorkOrderStatus.inProgress,
    type: WorkOrderType.fromString(type),
    originalComplaintId: complaint,
    originalDeficiencyId: deficiency,
    originalInspectionId: inspection,
    executionMode: mode,
  );
}

void main() {
  group('executionRouteFor', () {
    test('routes by execution mode, mirroring web jobWorkType order', () {
      expect(executionRouteFor(_wo(complaint: 5)),
          ExecutionRoute.complaint);
      expect(executionRouteFor(_wo(deficiency: 6)),
          ExecutionRoute.rectification);
      expect(executionRouteFor(_wo(inspection: 7)),
          ExecutionRoute.inspection);
      expect(executionRouteFor(_wo()), ExecutionRoute.checklist);
      expect(executionRouteFor(_wo(mode: 'RECTIFICATION')),
          ExecutionRoute.rectification);
      expect(executionRouteFor(_wo(mode: 'INSPECTION')),
          ExecutionRoute.inspection);
      expect(executionRouteFor(_wo(mode: 'CHECKLIST')),
          ExecutionRoute.checklist);
      // Complaint wins ties, as on web.
      expect(
          executionRouteFor(
              _wo(complaint: 5, deficiency: 6, inspection: 7)),
          ExecutionRoute.complaint);
    });

    test('maps explicit COMPLAINT mode and null/unknown modes', () {
      expect(executionRouteFor(_wo(mode: 'COMPLAINT')),
          ExecutionRoute.complaint);
      expect(executionRouteFor(_wo(mode: 'complaint')),
          ExecutionRoute.complaint);
      expect(executionRouteFor(_wo(mode: null)), ExecutionRoute.checklist);
      expect(executionRouteFor(_wo(mode: 'SOMETHING_ELSE')),
          ExecutionRoute.checklist);
    });

    test('displayTypeLabel covers the deficiency branch', () {
      expect(_wo(deficiency: 6).displayTypeLabel,
          'Deficiency Rectification');
      expect(_wo(mode: 'RECTIFICATION').displayTypeLabel,
          'Deficiency Rectification');
    });
  });

  group('ComplaintExecution', () {
    test('parses fields, params and kind-grouped photos', () {
      final exec = ComplaintExecution.fromJson({
        'id': 9,
        'initial_findings': 'Burnt smell',
        'action_taken': 'Replaced contactor',
        'final_remarks': 'Tested OK',
        'parameters': [
          {'parameter': 'IR', 'value': '0.5', 'unit': 'A'},
        ],
        'photos': [
          {'id': 1, 'kind': 'BEFORE', 'url': 'https://x/1.jpg'},
          {
            'id': 2,
            'kind': 'AFTER',
            'url': 'https://x/2.jpg',
            'locked_by_submission': 44,
            'source_complaint_photo_id': 7,
          },
        ],
      });
      expect(exec.initialFindings, 'Burnt smell');
      expect(exec.parameters.single['unit'], 'A');
      expect(exec.hasBefore, isTrue);
      expect(exec.hasAfter, isTrue);
      expect(exec.photos[1].locked, isTrue);
      expect(exec.photos[1].fromComplaint, isTrue);
    });
  });

  group('RectificationPayload', () {
    test('parses items with outcomes and photos', () {
      final payload = RectificationPayload.fromJson({
        'work_order_id': 200,
        'ticket_number': 'TLNR-202610-0020',
        'status': 'IN_PROGRESS',
        'editable': true,
        'final_remarks': '',
        'other_staff': '',
        'items': [
          {
            'id': 31,
            'deficiency_id': 21,
            'asset': 'TR-VRI-01',
            'checkpoint': 'Oil level',
            'finding': 'Low oil',
            'severity': 'High',
            'action_taken': '',
            'outcome': '',
            'reason': '',
            'photos': [],
            'is_active': true,
          }
        ],
      });
      expect(payload.editable, isTrue);
      expect(payload.items.length, 1);
      expect(payload.items.first.isRectified, isFalse);
    });
  });

  group('PointwiseInspectionExecution', () {
    test('parses merged point entries and submit shape', () {
      final exec = PointwiseInspectionExecution.fromJson({
        'work_order': 300,
        'ticket_number': 'WO-300',
        'points': [
          {
            'id': 51,
            'point_job_work_id': 901,
            'point_number': 1,
            'observation': 'Flashover damage',
            'priority': 'HIGH',
            'sequence': 1,
            'has_execution': true,
            'execution': {
              'id': 61,
              'point_job_work_id': 901,
              'initial_findings': 'Tracked',
              'action_taken': 'Cleaned',
              'final_remarks': 'OK',
              'corrective_action_performed': true,
              'technical_parameters': [
                {'parameter': 'V', 'value': '25', 'unit': 'kV'},
              ],
              'photos': [
                {'id': 71, 'photo_type': 'BEFORE', 'url': 'https://x/b.jpg'},
              ],
            },
          }
        ],
        'inspection_details': {
          'inspection_number': 'INSP-202609-0001',
          'inspection_title': 'Monthly',
          'station_name': 'VRI',
          'inspector_name': 'SSE/VRI',
        },
      });
      expect(exec.points.length, 1);
      final pt = exec.points.first;
      expect(pt.pointJobWorkId, 901);
      expect(pt.initialFindings, 'Tracked');
      expect(pt.technicalParameters.single['unit'], 'kV');
      expect(pt.photos.single.isBefore, isTrue);
      expect(exec.inspectionNumber, 'INSP-202609-0001');
      final submitted = pt.toSubmitJson();
      expect(submitted['point_job_work_id'], 901);
      expect(submitted['technical_parameters'], isNotEmpty);
    });
  });
}
