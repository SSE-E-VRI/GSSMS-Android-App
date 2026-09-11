import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';

void main() {
  group('Inspection Domain Model Tests', () {
    // Mirrors InspectionSerializer (SSOT §11.1) — no priority, no asset,
    // no inspection number.
    final json = {
      'id': 42,
      'title': 'EB Bunk Monthly Check',
      'notes': 'Check earth resistance and cleaning',
      'status': 'OPEN',
      'station': 48,
      'station_name': 'Thalanallur',
      'depot': 23,
      'depot_name': 'Vriddhachalam Depot',
      'infrastructure': 101,
      'infrastructure_name': 'EB-01',
      'created_by_name': 'depot_user',
      'created_by_first_name': 'Ravi',
      'created_by_last_name': 'Kumar',
      'created_by_designation': 'SSE',
      'created_at': '2026-08-18T05:00:00Z',
      'inspection_date': '2026-08-20T10:30:00+05:30',
      'is_converted': false,
      'wo_status': null,
      'wo_id': null,
    };

    test('Inspection.fromJson parses the serializer payload', () {
      final i = Inspection.fromJson(json);

      expect(i.id, 42);
      expect(i.reference, '#42');
      expect(i.title, 'EB Bunk Monthly Check');
      expect(i.status, InspectionStatus.open);
      expect(i.stationName, 'Thalanallur');
      expect(i.locationLabel, 'Thalanallur (Station)');
      expect(i.createdByName, 'Ravi Kumar');
      expect(i.createdByDesignation, 'SSE');
      expect(i.isConverted, isFalse);
    });

    test('inspector falls back to the username without first/last names', () {
      final i = Inspection.fromJson(const {
        'id': 1,
        'title': 't',
        'created_by_name': 'depot_user',
      });
      expect(i.createdByName, 'depot_user');
    });

    test('inspection_date is converted to device-local time (B11)', () {
      final i = Inspection.fromJson(json);
      expect(i.inspectionDate!.isUtc, isFalse);
      expect(
        i.inspectionDate!.isAtSameMomentAs(DateTime.utc(2026, 8, 20, 5, 0)),
        isTrue,
      );
    });

    test('InspectionStatus.fromString handles all canonical values', () {
      expect(InspectionStatus.fromString('OPEN'), InspectionStatus.open);
      expect(InspectionStatus.fromString('ACTION_REQUIRED'),
          InspectionStatus.actionRequired);
      expect(InspectionStatus.fromString('CONVERTED'), InspectionStatus.converted);
      expect(InspectionStatus.fromString('CLOSED'), InspectionStatus.closed);
      expect(InspectionStatus.fromString(null), InspectionStatus.unknown);
      expect(InspectionStatus.fromString('INVALID'), InspectionStatus.unknown);
      expect(InspectionStatus.fromString('open'), InspectionStatus.open);
      // Pre-SSOT values must map to unknown, never to invented states.
      expect(InspectionStatus.fromString('PENDING'), InspectionStatus.unknown);
      expect(InspectionStatus.fromString('IN_PROGRESS'), InspectionStatus.unknown);
      expect(InspectionStatus.fromString('COMPLETED'), InspectionStatus.unknown);
      expect(InspectionStatus.fromString('CANCELLED'), InspectionStatus.unknown);
    });

    test('markConverted sets status and Job Work id', () {
      final converted = Inspection.fromJson(json).markConverted(workOrderId: 7);
      expect(converted.status, InspectionStatus.converted);
      expect(converted.isConverted, isTrue);
      expect(converted.workOrderId, 7);
    });
  });
}
