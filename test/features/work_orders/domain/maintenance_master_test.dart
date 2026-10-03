import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_master.dart';

void main() {
  group('MaintenanceTemplateKind S-V4 checklist kinds', () {
    test("fromString('AMC') returns amc, not the assetTemplate fallback", () {
      expect(
        MaintenanceTemplateKind.fromString('AMC'),
        MaintenanceTemplateKind.amc,
      );
    });

    test('handover/takeover/specialDrive parse instead of misclassifying', () {
      expect(
        MaintenanceTemplateKind.fromString('HANDOVER'),
        MaintenanceTemplateKind.handover,
      );
      expect(
        MaintenanceTemplateKind.fromString('TAKEOVER'),
        MaintenanceTemplateKind.takeover,
      );
      expect(
        MaintenanceTemplateKind.fromString('SPECIAL_DRIVE'),
        MaintenanceTemplateKind.specialDrive,
      );
    });

    test('truly unknown codes still fall back to assetTemplate', () {
      expect(
        MaintenanceTemplateKind.fromString('SOMETHING_NEW'),
        MaintenanceTemplateKind.assetTemplate,
      );
      expect(
        MaintenanceTemplateKind.fromString(null),
        MaintenanceTemplateKind.assetTemplate,
      );
    });
  });

  group('MaintenanceMaster version (S-V1 field, surfaced in S-V4)', () {
    test('version parses when present', () {
      final master = MaintenanceMaster.fromJson(const {
        'id': 7,
        'name': 'DG Set AMC',
        'schedule_type': 'QUARTERLY',
        'template_kind': 'AMC',
        'version': '1.2.0',
      });

      expect(master.templateKind, MaintenanceTemplateKind.amc);
      expect(master.version, '1.2.0');
    });

    test('version stays null when absent (back-compat)', () {
      final master = MaintenanceMaster.fromJson(const {
        'id': 8,
        'name': 'Panel Monthly',
        'schedule_type': 'MONTHLY',
        'template_kind': 'ASSET_TEMPLATE',
      });

      expect(master.version, isNull);
    });

    test('displayLabel appends the version only when present', () {
      const withVersion = MaintenanceMaster(
        id: 7,
        name: 'DG Set AMC',
        scheduleType: MaintenanceScheduleType.quarterly,
        templateKind: MaintenanceTemplateKind.amc,
        version: '1.2.0',
      );
      const withoutVersion = MaintenanceMaster(
        id: 8,
        name: 'Panel Monthly',
        scheduleType: MaintenanceScheduleType.monthly,
        templateKind: MaintenanceTemplateKind.assetTemplate,
      );

      expect(withVersion.displayLabel, 'DG Set AMC (Quarterly) v1.2.0');
      expect(withoutVersion.displayLabel, 'Panel Monthly (Monthly)');
    });
  });

  group('Template kind display names (WP1)', () {
    test('stationTemplate displayName is Station', () {
      expect(MaintenanceTemplateKind.stationTemplate.displayName, 'Station');
    });
  });
}
