import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

void main() {
  group('WorkOrder Domain Model Tests', () {
    test('WorkOrder.fromJson parses full backend payload correctly', () {
      final json = {
        'id': 142,
        'status': 'ASSIGNED',
        'type': 'PM',
        'title': 'Monthly Transformer Inspection',
        'description': 'Check oil level and thermal imaging',
        'priority': 'HIGH',
        'asset': 88,
        'asset_name': 'TR-VRI-01',
        'asset_criticality': 'CRITICAL',
        'depot': 10,
        'depot_name': 'Vriddhachalam Depot',
        'station_name': 'VRI',
        'infrastructure_name': 'Substation Bay 1',
        'infrastructure_type': 'STATION',
        'assigned_to': 4,
        'assigned_to_name': 'tech_ramesh',
        'reported_by_name': 'incharge_kumar',
        'verified_by_name': null,
        'due_date': '2026-08-25T18:30:00Z',
        'created_at': '2026-08-18T06:00:00Z',
        'report_completed_at': null,
        'linked_record_id': 95,
        'latest_event_summary': {
          'event_type': 'ASSIGNED',
          'actor': 'incharge_kumar',
          'timestamp': '2026-08-18T06:10:00Z',
          'remarks': 'Assigned for urgent monthly inspection',
        },
      };

      final wo = WorkOrder.fromJson(json);

      expect(wo.id, 142);
      expect(wo.status, WorkOrderStatus.assigned);
      expect(wo.type, WorkOrderType.preventive);
      expect(wo.priority, WorkOrderPriority.high);
      expect(wo.assetName, 'TR-VRI-01');
      expect(wo.assetCriticality, 'CRITICAL');
      expect(wo.stationName, 'VRI');
      expect(wo.assignedToName, 'tech_ramesh');
      expect(wo.linkedRecordId, 95);
      expect(wo.isExecutionAllowed, isTrue);
      expect(wo.latestEventSummary?.eventType, 'ASSIGNED');
      expect(wo.latestEventSummary?.remarks, 'Assigned for urgent monthly inspection');
    });

    test('WorkOrderStatus.fromString parses all canonical statuses safely', () {
      expect(WorkOrderStatus.fromString('NEW'), WorkOrderStatus.newOrder);
      expect(WorkOrderStatus.fromString('ASSIGNED'), WorkOrderStatus.assigned);
      expect(WorkOrderStatus.fromString('IN_PROGRESS'), WorkOrderStatus.inProgress);
      expect(WorkOrderStatus.fromString('TECH_COMPLETED'), WorkOrderStatus.techCompleted);
      expect(WorkOrderStatus.fromString('VERIFIED'), WorkOrderStatus.verified);
      expect(WorkOrderStatus.fromString('REWORK_REQUIRED'), WorkOrderStatus.reworkRequired);
      expect(WorkOrderStatus.fromString('ON_HOLD'), WorkOrderStatus.onHold);
      expect(WorkOrderStatus.fromString('CLOSED'), WorkOrderStatus.closed);
      expect(WorkOrderStatus.fromString('CANCELLED'), WorkOrderStatus.cancelled);
      expect(WorkOrderStatus.fromString('INVALID_STATUS'), WorkOrderStatus.unknown);
      expect(WorkOrderStatus.fromString(null), WorkOrderStatus.unknown);
    });

    test('WorkOrderType.fromString parses types safely', () {
      // The values the Django backend actually sends (WO_TYPE_CHOICES).
      expect(WorkOrderType.fromString('PREVENTIVE'), WorkOrderType.preventive);
      expect(WorkOrderType.fromString('BREAKDOWN'), WorkOrderType.breakdown);
      expect(WorkOrderType.fromString('CORRECTIVE'), WorkOrderType.corrective);
      expect(WorkOrderType.fromString('CALIBRATION'), WorkOrderType.calibration);
      expect(WorkOrderType.fromString('INSTALLATION'), WorkOrderType.installation);
      expect(WorkOrderType.fromString('OTHER'), WorkOrderType.other);
      // 'PM' is the superseded short form kept for previously cached rows.
      expect(WorkOrderType.fromString('PM'), WorkOrderType.preventive);
      expect(WorkOrderType.fromString('NONSENSE'), WorkOrderType.unknown);
    });

    test('parses the work order payload the server actually returns', () {
      // Field-for-field from GET /api/v1/maintenance/work-orders/.
      final json = <String, dynamic>{
        'id': 20,
        'ticket_number': 'TLNR-202608-0015',
        'title': 'Station Monthly Maintenance',
        'description': '',
        'type': 'PREVENTIVE',
        'priority': 'MEDIUM',
        'status': 'IN_PROGRESS',
        'maintenance_master_name': 'Station Monthly Maintenance',
        'depot_name': 'Vriddhachalam Depot',
        'station_name': 'Thalanallur',
        'assigned_to_name': 'krishna',
        'reported_by_name': 'vri',
        'due_date': '2026-08-08',
        'sla_status': 'OK',
        'escalation_level': 'NONE',
        'infrastructure_type': 'STATION',
        'linked_record_id': 22,
        'station': 48,
        'depot': 23,
        'asset': null,
        'latest_event_summary': {
          'event_type': 'STATUS_CHANGE',
          'created_at': '2026-08-09T03:48:35.700709Z',
          'actor': 'krishna',
          'remarks': 'Execution started',
        },
      };

      final wo = WorkOrder.fromJson(json);

      expect(wo.id, 20);
      expect(wo.ticketNumber, 'TLNR-202608-0015');
      expect(wo.displayReference, 'TLNR-202608-0015');
      expect(
        wo.type,
        WorkOrderType.preventive,
        reason: 'PREVENTIVE must not fall through to Unknown',
      );
      expect(wo.status, WorkOrderStatus.inProgress);
      expect(wo.linkedRecordId, 22);
      expect(wo.stationId, 48);
      expect(wo.isSlaAtRisk, isFalse);
      expect(wo.latestEventSummary?.actor, 'krishna');
    });
  });

  group('MaintenanceRecord Domain Model Tests', () {
    // Shapes below are taken from a live GET /api/v1/maintenance/records/{id}/
    // response, including the nested status -> action option structure and the
    // typed value_types the register uses.
    Map<String, dynamic> statusLine() => {
          'id': 1541,
          'item_name': 'EB Bunk',
          'inspection_point': 'Check and clean the EB meter bunk',
          'value_type': 'STATUS',
          'item_kind': 'INSPECTION_POINT',
          'required': true,
          'asset_category': 'EB Bunk',
          'status_options': [
            {
              'id': 2071,
              'label': 'Dirty',
              'semantic': 'NORMAL',
              'is_deficiency': false,
              'action_options': [
                {'id': 4204, 'label': 'Cleaned', 'is_deficiency': false},
                {'id': 4205, 'label': 'Pending', 'is_deficiency': true},
              ],
            },
            {
              'id': 2072,
              'label': 'Clean',
              'semantic': 'NORMAL',
              'is_deficiency': false,
              'action_options': [
                {'id': 4206, 'label': 'No Action Required', 'is_deficiency': false},
              ],
            },
          ],
          'recorded_value': null,
          'status': 'OK',
          'status_option': 2071,
          'action_option': 4204,
          'observation_action': null,
          'deficiency': null,
          'deficiency_attended': false,
          'excluded': false,
          'unit_snapshot': '',
        };

    Map<String, dynamic> rybLine() => {
          'id': 1550,
          'item_name': 'EB Bunk',
          'inspection_point': 'Voltage',
          'value_type': 'RYB',
          'item_kind': 'RECORD_PARAMETER',
          'required': true,
          'asset_category': 'EB Bunk',
          'status_options': <dynamic>[],
          'recorded_value': null,
          'status': 'OK',
          'unit_snapshot': 'V',
          'excluded': false,
        };

    test('parses nested status and action options', () {
      final line = MaintenanceRecordLine.fromJson(statusLine());

      expect(line.itemName, 'EB Bunk');
      expect(line.inspectionPoint, 'Check and clean the EB meter bunk');
      expect(line.displayTitle, 'Check and clean the EB meter bunk');
      expect(line.valueType, MaintenanceValueType.status);
      expect(line.itemKind, MaintenanceItemKind.inspectionPoint);
      expect(line.assetCategory, 'EB Bunk');
      expect(line.statusOptions.length, 2);
      expect(line.statusOptions.first.label, 'Dirty');
      expect(line.statusOptions.first.actionOptions.length, 2);
      expect(line.statusOptionId, 2071);
      expect(line.actionOptionId, 4204);
    });

    test('only offers actions belonging to the selected status', () {
      final line = MaintenanceRecordLine.fromJson(statusLine());

      expect(
        line.availableActionOptions.map((a) => a.id),
        [4204, 4205],
        reason: 'actions for status 2071',
      );

      final switched = line.copyWith(statusOptionId: 2072, actionOptionId: null);
      expect(
        switched.availableActionOptions.map((a) => a.id),
        [4206],
        reason: 'switching status must switch the action list with it',
      );
    });

    test('an inspection point needs a status and, where offered, an action', () {
      final line = MaintenanceRecordLine.fromJson(statusLine());
      expect(line.isCompleted, isTrue);

      final noAction = line.copyWith(actionOptionId: null);
      expect(
        noAction.isCompleted,
        isFalse,
        reason: 'status 2071 offers actions, so one must be chosen',
      );

      final noStatus = line.copyWith(statusOptionId: null, actionOptionId: null);
      expect(noStatus.isCompleted, isFalse);
    });

    test('reads three-phase readings from both object and JSON-string forms', () {
      final base = MaintenanceRecordLine.fromJson(rybLine());
      expect(base.valueType, MaintenanceValueType.ryb);
      expect(base.valueType.componentKeys, ['R', 'Y', 'B']);
      expect(base.unit, 'V');
      expect(base.isCompleted, isFalse);

      final asMap = base.copyWith(
        recordedValue: const {'R': '240', 'Y': '238', 'B': '241'},
      );
      expect(asMap.componentValues['R'], '240');
      expect(asMap.isCompleted, isTrue);

      // The backend has historically stored this as a JSON string.
      final asString = base.copyWith(
        recordedValue: '{"R":"240","Y":"238","B":"241"}',
      );
      expect(asString.componentValues['Y'], '238');
      expect(asString.isCompleted, isTrue);
    });

    test('clearing a reading actually clears it', () {
      final line = MaintenanceRecordLine.fromJson(rybLine())
          .copyWith(recordedValue: '230');
      expect(line.scalarValue, '230');

      final cleared = line.copyWith(recordedValue: null);
      expect(
        cleared.recordedValue,
        isNull,
        reason: 'copyWith must distinguish an explicit null from "unchanged"',
      );
    });

    test('record progress counts only lines that are part of the work', () {
      final json = <String, dynamic>{
        'id': 22,
        'schedule_details': {
          'work_order_id': 20,
          'work_order_ticket': 'TLNR-202608-0015',
          'template_name': 'Station Monthly Maintenance',
          'station_name': 'Thalanallur',
        },
        'lines': [
          statusLine(),
          rybLine(),
          {...rybLine(), 'id': 1551, 'excluded': true},
        ],
      };

      final record = MaintenanceRecord.fromJson(json);

      expect(record.id, 22);
      expect(record.workOrderId, 20);
      expect(record.workOrderTicket, 'TLNR-202608-0015');
      expect(record.templateName, 'Station Monthly Maintenance');
      expect(record.lines.length, 3);
      expect(
        record.totalLines,
        2,
        reason: 'the excluded line is not part of this record',
      );
      expect(record.completedLines, 1);
      expect(record.progress, 0.5);
    });

    test('survives a cache round-trip without losing options or readings', () {
      final original = MaintenanceRecord.fromJson({
        'id': 22,
        'lines': [statusLine(), rybLine()],
      });

      final restored = MaintenanceRecord.fromJson(
        jsonDecode(jsonEncode(original.toCacheJson())) as Map<String, dynamic>,
      );

      expect(restored.lines.length, 2);
      expect(restored.lines[0].statusOptions.length, 2);
      expect(restored.lines[0].statusOptions.first.actionOptions.length, 2);
      expect(restored.lines[0].statusOptionId, 2071);
      expect(restored.lines[0].actionOptionId, 4204);
      expect(restored.lines[1].valueType, MaintenanceValueType.ryb);
      expect(restored.lines[1].unit, 'V');
      expect(restored, original);
    });
  });
}
