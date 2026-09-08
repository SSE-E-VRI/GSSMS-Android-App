import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/reports/domain/models/maintenance_register_entry.dart';

void main() {
  group('MaintenanceRegisterEntry parsing survives type-mismatched server fields', () {
    // Same class of bug as the dashboard models: a string-typed field
    // arriving as a number must be coerced, not crash the register screen.
    test('coerces non-string master/organization/technician fields', () {
      final entry = MaintenanceRegisterEntry.fromJson(const {
        'id': 1,
        'master': 3,
        'date': '2026-08-22',
        'organization': {
          'depot_name': 4,
          'station_name': 6,
          'register_title': 9,
        },
        'technician': 2,
        'supervisor': 5,
        'remarks': 7,
        'items': [
          {
            'asset_name': 1,
            'inspection': 2,
            'value': 240,
            'status': 3,
            'status_label': 4,
            'action': 5,
            'remarks': 6,
          },
        ],
      });

      expect(entry.masterName, '3');
      expect(entry.depotName, '4');
      expect(entry.stationName, '6');
      expect(entry.registerTitle, '9');
      expect(entry.technician, '2');
      expect(entry.supervisor, '5');
      expect(entry.remarks, '7');

      final item = entry.items.single;
      expect(item.assetName, '1');
      expect(item.inspection, '2');
      expect(item.value, '240');
      expect(item.status, '3');
      expect(item.statusLabel, '4');
      expect(item.action, '5');
      expect(item.remarks, '6');
    });
  });

  group('MaintenanceRegisterEntry.groupedByAsset', () {
    test('groups rows by asset name in first-appearance order', () {
      const entry = MaintenanceRegisterEntry(
        id: 1,
        masterName: 'Monthly Inspection',
        items: [
          RegisterLineItem(assetName: 'EB Bunk', inspection: 'Check meter'),
          RegisterLineItem(assetName: 'Earth Pit', inspection: 'Check resistance'),
          // A second EB Bunk row arriving later must join the first group,
          // not start a new one — matches web's FormPreview grouping.
          RegisterLineItem(assetName: 'EB Bunk', inspection: 'Check wiring'),
        ],
      );

      final groups = entry.groupedByAsset;

      expect(groups.map((g) => g.assetName), ['EB Bunk', 'Earth Pit']);
      expect(groups[0].items.map((i) => i.inspection), ['Check meter', 'Check wiring']);
      expect(groups[1].items.map((i) => i.inspection), ['Check resistance']);
    });

    test('returns no groups for an entry with no items', () {
      const entry = MaintenanceRegisterEntry(id: 1, masterName: 'Empty');
      expect(entry.groupedByAsset, isEmpty);
    });
  });

  group('MaintenanceRegisterEntry.fromJson organization letterhead', () {
    test('parses railway_name and division_name from organization', () {
      final entry = MaintenanceRegisterEntry.fromJson(const {
        'id': 1,
        'master': 'MTUR-202608-0016',
        'organization': {
          'railway_name': 'Southern Railway',
          'division_name': 'Tiruchchirappalli Division',
          'depot_name': 'Vriddhachalam Depot',
        },
      });

      expect(entry.railwayName, 'Southern Railway');
      expect(entry.divisionName, 'Tiruchchirappalli Division');
      expect(entry.depotName, 'Vriddhachalam Depot');
    });
  });

  group('RegisterLineItem.isRecordedParameter', () {
    test('true for a reading with a value and no action', () {
      const item = RegisterLineItem(
        assetName: 'EB Bunk',
        inspection: 'Voltage',
        value: 'B: 210, R: 214, Y: 218',
      );
      expect(item.isRecordedParameter, isTrue);
    });

    test('false for a checkpoint with status and action', () {
      const item = RegisterLineItem(
        assetName: 'EB Bunk',
        inspection: 'Check and clean the EB meter bunk',
        statusLabel: 'Dirty',
        action: 'Cleaned',
      );
      expect(item.isRecordedParameter, isFalse);
    });

    test('false when neither value nor action is set', () {
      const item = RegisterLineItem(assetName: 'EB Bunk', inspection: 'Check normal');
      expect(item.isRecordedParameter, isFalse);
    });
  });
}
