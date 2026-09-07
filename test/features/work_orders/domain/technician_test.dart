import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/technician.dart';

void main() {
  group('Technician.fromJson', () {
    test('prefers full_name over username', () {
      final tech = Technician.fromJson(const {
        'id': 4,
        'full_name': 'Ramesh Kumar',
        'username': 'tech_ramesh',
      });
      expect(tech.id, 4);
      expect(tech.name, 'Ramesh Kumar');
    });

    test('joins first_name and last_name when full_name is absent', () {
      final tech = Technician.fromJson(const {
        'id': 5,
        'first_name': 'Anita',
        'last_name': 'Singh',
        'username': 'anita',
      });
      expect(tech.name, 'Anita Singh');
    });

    test('falls back to username', () {
      final tech = Technician.fromJson(const {
        'id': 6,
        'username': 'tech_krishna',
      });
      expect(tech.name, 'tech_krishna');
    });
  });
}
