import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';

void main() {
  group('WorkOrderAuditEvent.fromJson details', () {
    test('parses reassign from/to from details', () {
      final e = WorkOrderAuditEvent.fromJson({
        'event_id': 'e1',
        'event_type': 'REASSIGNED',
        'details': {'from_user': 'Alice', 'to_user': 'Bob'},
      });
      expect(e.fromUser, 'Alice');
      expect(e.toUser, 'Bob');
    });

    test('maps assigned_to to toUser', () {
      final e = WorkOrderAuditEvent.fromJson({
        'event_id': 'e2',
        'event_type': 'STATUS_CHANGE',
        'to_state': 'ASSIGNED',
        'details': {'assigned_to': 'Bob'},
      });
      expect(e.toUser, 'Bob');
      expect(e.fromUser, isNull);
    });

    test('absent or null details leaves users null', () {
      for (final json in [
        {'event_id': 'e3', 'event_type': 'X'},
        {'event_id': 'e4', 'event_type': 'X', 'details': null},
      ]) {
        final e = WorkOrderAuditEvent.fromJson(json);
        expect(e.fromUser, isNull);
        expect(e.toUser, isNull);
      }
    });
  });
}
