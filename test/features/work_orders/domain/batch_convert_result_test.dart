import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/batch_convert_result.dart';

void main() {
  group('BatchConvertResult', () {
    test('parses legacy all-or-nothing bodies without results', () {
      final result = BatchConvertResult.fromJson(const {
        'work_order_ids': [7, 9],
        'message': 'ok',
      });
      expect(result.workOrderIds, [7, 9]);
      expect(result.count, 2);
      expect(result.itemResults, isEmpty);
      expect(result.failures, isEmpty);
    });

    test('S2 parses per-item results with a blocked item', () {
      final result = BatchConvertResult.fromJson(const {
        'work_order_ids': [812],
        'results': [
          {
            'schedule_id': 311,
            'created': false,
            'work_order_id': null,
            'code': 'PM_PENDING_EXISTS',
            'error': 'Another PM Job Work for this obligation is still open.',
            'existing_ticket': 'WO-2026-0142',
          },
          {
            'schedule_id': 312,
            'created': true,
            'work_order_id': 812,
            'code': null,
            'error': null,
            'existing_ticket': null,
          },
        ],
      });
      expect(result.count, 1);
      expect(result.itemResults, hasLength(2));
      final failures = result.failures;
      expect(failures, hasLength(1));
      expect(failures.single.scheduleId, 311);
      expect(failures.single.converted, isFalse);
      expect(failures.single.code, 'PM_PENDING_EXISTS');
      expect(failures.single.existingTicket, 'WO-2026-0142');
      expect(result.itemResults[1].converted, isTrue);
      expect(result.itemResults[1].workOrderId, 812);
    });

    test('empty body parses to empty result', () {
      final result = BatchConvertResult.fromJson(const {});
      expect(result.workOrderIds, isEmpty);
      expect(result.count, 0);
      expect(result.failures, isEmpty);
    });

    test('C1 asset refusal renders its code and error text', () {
      final result = BatchConvertResult.fromJson(const {
        'work_order_ids': [],
        'results': [
          {
            'schedule_id': 511,
            'created': false,
            'work_order_id': null,
            'code': 'ASSET_NO_LONGER_ELIGIBLE',
            'error': 'Asset VRI-PMP-CLS-TRN-001 is archived and can no longer receive preventive maintenance.',
            'existing_ticket': null,
          },
        ],
      });
      expect(result.failures, hasLength(1));
      expect(result.failures.single.code, 'ASSET_NO_LONGER_ELIGIBLE');
      expect(result.failures.single.error, contains('archived'));
    });
  });
}
