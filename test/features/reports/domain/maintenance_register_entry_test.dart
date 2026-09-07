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
}
