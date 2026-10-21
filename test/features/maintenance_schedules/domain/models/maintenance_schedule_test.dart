import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/maintenance_schedules/domain/models/maintenance_schedule.dart';

void main() {
  group('ScheduleStatus.fromString', () {
    test('SKIPPED parses to the real enum value, not the unknown fallback', () {
      expect(ScheduleStatus.fromString('SKIPPED'), ScheduleStatus.skipped);
    });

    test('an unrecognized code still falls back to unknown', () {
      expect(ScheduleStatus.fromString('SOME_FUTURE_STATUS'), ScheduleStatus.unknown);
    });

    test('null falls back to unknown', () {
      expect(ScheduleStatus.fromString(null), ScheduleStatus.unknown);
    });
  });

  group('MaintenanceSchedule.isBreakdown', () {
    test('parses is_breakdown true', () {
      final s = MaintenanceSchedule.fromJson(
          {'id': 1, 'template_name': 'T', 'status': 'PENDING', 'is_breakdown': true});
      expect(s.isBreakdown, isTrue);
    });

    test('defaults to false when absent or null', () {
      expect(
          MaintenanceSchedule.fromJson(
              {'id': 1, 'template_name': 'T', 'status': 'PENDING'}).isBreakdown,
          isFalse);
      expect(
          MaintenanceSchedule.fromJson({
            'id': 1,
            'template_name': 'T',
            'status': 'PENDING',
            'is_breakdown': null,
          }).isBreakdown,
          isFalse);
    });
  });

  group('MaintenanceSchedule.isSkipped', () {
    MaintenanceSchedule scheduleWith(String status) {
      return MaintenanceSchedule.fromJson({
        'id': 1,
        'template_name': 'Test',
        'status': status,
      });
    }

    test('is true for a SKIPPED row', () {
      expect(scheduleWith('SKIPPED').isSkipped, isTrue);
    });

    test('is false for a PENDING row', () {
      expect(scheduleWith('PENDING').isSkipped, isFalse);
    });

    test('is false for an OVERDUE row', () {
      expect(scheduleWith('OVERDUE').isSkipped, isFalse);
    });
  });
  group('MaintenanceSchedule C1 asset parity', () {
    test('SKIPPED parses to skipped, not unknown', () {
      final schedule = MaintenanceSchedule.fromJson(const {
        'id': 11,
        'template_name': 'Pump Monthly',
        'status': 'SKIPPED',
      });

      expect(schedule.status, ScheduleStatus.skipped);
    });

    test('asset fields parse when present', () {
      final schedule = MaintenanceSchedule.fromJson(const {
        'id': 12,
        'template_name': 'Pump Monthly',
        'status': 'PENDING',
        'asset': 44,
        'asset_unique_id': 'VRI-PMP-CLS-TRN-001',
        'asset_name': 'Pump 1 (Room A)',
        'termination_reason': null,
      });

      expect(schedule.assetId, 44);
      expect(schedule.assetUniqueId, 'VRI-PMP-CLS-TRN-001');
      expect(schedule.assetName, 'Pump 1 (Room A)');
      expect(schedule.terminationReason, isNull);
    });

    test('termination reason parses when present', () {
      final schedule = MaintenanceSchedule.fromJson(const {
        'id': 13,
        'template_name': 'Pump Monthly',
        'status': 'SKIPPED',
        'asset': 44,
        'termination_reason': 'ASSET_TRANSFERRED',
      });

      expect(schedule.status, ScheduleStatus.skipped);
      expect(schedule.terminationReason, 'ASSET_TRANSFERRED');
    });

    test('asset fields stay null for a station occurrence', () {
      final schedule = MaintenanceSchedule.fromJson(const {
        'id': 14,
        'template_name': 'Station Monthly',
        'status': 'PENDING',
        'asset': null,
        'asset_unique_id': null,
        'asset_name': null,
        'termination_reason': null,
      });

      expect(schedule.assetId, isNull);
      expect(schedule.assetUniqueId, isNull);
      expect(schedule.assetName, isNull);
      expect(schedule.terminationReason, isNull);
    });

    test('payload missing the new keys entirely still parses', () {
      final schedule = MaintenanceSchedule.fromJson(const {
        'id': 15,
        'template_name': 'Station Monthly',
        'status': 'PENDING',
      });

      expect(schedule.id, 15);
      expect(schedule.status, ScheduleStatus.pending);
      expect(schedule.assetId, isNull);
      expect(schedule.terminationReason, isNull);
    });

    test('unrecognized status still falls back to unknown', () {
      final schedule = MaintenanceSchedule.fromJson(const {
        'id': 16,
        'template_name': 'Station Monthly',
        'status': 'SOMETHING_NEW',
      });

      expect(schedule.status, ScheduleStatus.unknown);
    });
  });
}
