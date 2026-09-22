import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';

void main() {
  group('Dashboard model parsing survives type-mismatched server fields', () {
    // Regression: the live backend returned an int (observed value: 2) for a
    // field the model expected as a string, and `json['x'] as String?`
    // crashed the whole dashboard with a TypeError instead of degrading.
    // These fields aren't fixed by contract with the server, so the parser
    // must coerce rather than assume the type.
    test('AttentionItem coerces non-string master_name/station_name/priority', () {
      final item = AttentionItem.fromJson(const {
        'id': 7,
        'master_name': 2,
        'station_name': 5,
        'depot_name': 9,
        'priority': 1,
        'due_date': '2026-08-01',
        'days_overdue': 3,
      });

      expect(item.masterName, '2');
      expect(item.stationName, '5');
      expect(item.depotName, '9');
      expect(item.priority, '1');
    });

    test('WorkOrderStatusSegment coerces a non-string label/color', () {
      final segment = WorkOrderStatusSegment.fromJson(const {
        'label': 4,
        'color': 8,
        'count': 3,
      });

      expect(segment.label, '4');
      expect(segment.colorHex, '8');
      expect(segment.count, 3);
    });

    test('MaintenanceTypeStat coerces a non-string label', () {
      final stat = MaintenanceTypeStat.fromJson(const {
        'label': 1,
        'count': 8,
        'percentage': 73,
      });

      expect(stat.label, '1');
      expect(stat.count, 8);
    });

    test('DashboardSummary.fromJson does not throw when nested fields are type-mismatched', () {
      final summary = DashboardSummary.fromJson(const {
        'stats': {
          'total_work_orders': 11,
          'compliance_rate': 27,
          'status_segments': [
            {'label': 2, 'color': 5, 'count': 3},
          ],
          'type_stats': [
            {'label': 8, 'count': 3, 'percentage': 27},
          ],
        },
        'pending_tasks': [],
      });

      expect(summary.stats.totalWorkOrders, 11);
      expect(summary.stats.statusSegments.single.label, '2');
      expect(summary.stats.typeStats.single.label, '8');
    });

    test('PendingAction parses tolerant shapes and skips non-maps', () {
      final summary = DashboardSummary.fromJson(const {
        'stats': {'total_work_orders': 5},
        'pending_tasks': [
          {
            'id': 9,
            'kind': 'verification',
            'title': 'Verify TR-01 job',
            'station_name': 'VRI',
            'work_order_id': 101,
          },
          {'type': 'COMPLAINT', 'name': 'Fan failure', 'complaint_id': 7},
          'not-a-map',
          42,
        ],
      });

      expect(summary.pendingTasks.length, 2);
      expect(summary.pendingTasks[0].kind, PendingActionKind.verification);
      expect(summary.pendingTasks[0].workOrderId, 101);
      expect(summary.pendingTasks[0].subtitle, 'VRI');
      expect(summary.pendingTasks[1].kind, PendingActionKind.complaint);
      expect(summary.pendingTasks[1].complaintId, 7);
    });

    test('AttentionItem parses asset fields when present', () {
      final item = AttentionItem.fromJson(const {
        'id': 21,
        'master_name': 'Pump Monthly',
        'station_name': 'VRI',
        'due_date': '2026-09-01',
        'asset_id': 44,
        'asset_name': 'Pump 1 (Room A)',
      });

      expect(item.assetId, 44);
      expect(item.assetName, 'Pump 1 (Room A)');
    });

    test('AttentionItem keeps asset fields null for a station row', () {
      final item = AttentionItem.fromJson(const {
        'id': 22,
        'master_name': 'Station Monthly',
        'station_name': 'VRI',
        'due_date': '2026-09-01',
      });

      expect(item.assetId, isNull);
      expect(item.assetName, isNull);
    });
  });
}
