import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';

void main() {
  group('PendingAction from a summary.pending_tasks schedule row', () {
    test('uses master name, asset/station and the linked work order', () {
      final a = PendingAction.fromJson({
        'id': 41,
        'maintenance_master_name': 'Station Monthly Maintenance',
        'asset_name': 'Lift 2',
        'station_name': 'Vadalur',
        'due_date': '2026-10-20',
        'location': 'Vadalur Station',
        'linked_work_order': {'id': 900, 'status': 'IN_PROGRESS'},
        'is_breakdown': false,
      });
      expect(a.title, 'Station Monthly Maintenance');
      expect(a.subtitle, 'Lift 2 • Vadalur');
      expect(a.workOrderId, 900);
      expect(a.kind, PendingActionKind.task);
      expect(a.dueDate, DateTime(2026, 10, 20));
    });

    test('a tech-completed linked job reads as a verification', () {
      final a = PendingAction.fromJson({
        'id': 1,
        'maintenance_master_name': 'Quarterly',
        'linked_work_order': {'id': 5, 'status': 'TECH_COMPLETED'},
      });
      expect(a.kind, PendingActionKind.verification);
    });

    test('Unknown Asset placeholder is dropped and station dedupes', () {
      final a = PendingAction.fromJson({
        'id': 2,
        'maintenance_master_name': 'Monthly',
        'asset_name': 'Unknown Asset',
        'station_name': 'Sendurai',
      });
      expect(a.subtitle, 'Sendurai');
    });
  });
}
