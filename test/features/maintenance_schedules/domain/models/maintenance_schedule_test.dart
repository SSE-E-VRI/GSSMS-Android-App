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
}
