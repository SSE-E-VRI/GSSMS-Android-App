import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';

Map<String, dynamic> _json({String? status, String? woStatus}) => {
      'id': 5,
      'status': status ?? 'IN_PROGRESS',
      'schedule_details': {
        'station': 9,
        'infrastructure': 4,
        'station_name': 'Vriddhachalam',
        'work_order_id': 99,
      },
      'work_order_context': {
        'work_order_id': 123,
        'asset_id': 501,
        'asset_unique_id': 'STN-001',
        'asset_name': 'CLS Panel',
        if (woStatus != null) 'status': woStatus,
      },
      'lines': [],
    };

void main() {
  group('MaintenanceRecord replacement fields', () {
    test('parses schedule and work_order_context', () {
      final r = MaintenanceRecord.fromJson(_json(woStatus: 'ASSIGNED'));
      expect(r.stationId, 9);
      expect(r.infrastructureId, 4);
      expect(r.jobWorkAssetId, 501);
      expect(r.jobWorkAssetUniqueId, 'STN-001');
      expect(r.jobWorkAssetName, 'CLS Panel');
      expect(r.workOrderStatus, 'ASSIGNED');
      // context id wins over schedule_details.work_order_id
      expect(r.workOrderId, 123);
    });

    test('falls back to schedule_details.work_order_status', () {
      final j = _json();
      (j['schedule_details'] as Map)['work_order_status'] = 'COMPLETED';
      expect(MaintenanceRecord.fromJson(j).workOrderStatus, 'COMPLETED');
    });

    test('absent context parses to nulls and legacy work_order chain', () {
      final r = MaintenanceRecord.fromJson(const {
        'id': 1,
        'schedule_details': {'work_order_id': 7},
      });
      expect(r.workOrderId, 7);
      expect(r.jobWorkAssetId, isNull);
      expect(r.stationId, isNull);
    });

    test('toCacheJson round-trips through fromJson', () {
      final r = MaintenanceRecord.fromJson(_json(woStatus: 'ASSIGNED'));
      final back = MaintenanceRecord.fromJson(r.toCacheJson());
      expect(back.stationId, 9);
      expect(back.infrastructureId, 4);
      expect(back.jobWorkAssetId, 501);
      expect(back.jobWorkAssetUniqueId, 'STN-001');
      expect(back.jobWorkAssetName, 'CLS Panel');
      expect(back.workOrderStatus, 'ASSIGNED');
      expect(back.workOrderId, 123);
      expect(back, r);
    });

    test('copyWith keeps the replacement fields', () {
      final r = MaintenanceRecord.fromJson(_json(woStatus: 'ASSIGNED'));
      expect(r.copyWith(lines: const []), r);
    });

    test('isReplacementLocked', () {
      expect(
          MaintenanceRecord.fromJson(_json(woStatus: 'ASSIGNED'))
              .isReplacementLocked,
          isFalse);
      expect(
          MaintenanceRecord.fromJson(_json(woStatus: 'TECH_COMPLETED'))
              .isReplacementLocked,
          isTrue);
      // Falls back to the record status when the Job Work status is absent.
      expect(
          MaintenanceRecord.fromJson(_json(status: 'VERIFIED'))
              .isReplacementLocked,
          isTrue);
      expect(MaintenanceRecord.fromJson(_json()).isReplacementLocked, isFalse);
      // Record past tech completion locks even if the Job Work status is open.
      expect(
          MaintenanceRecord.fromJson(_json(status: 'TECH_COMPLETED', woStatus: 'ASSIGNED'))
              .isReplacementLocked,
          isTrue);
    });
  });
}
