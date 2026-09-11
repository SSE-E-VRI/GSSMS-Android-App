import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';

void main() {
  group('Inspection Domain Model Tests', () {
    test('Inspection.fromJson parses full backend payload correctly', () {
      final json = {
        'id': 42,
        'inspection_number': 'INSP-2026-0042',
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
        'created_at': '2026-08-18T05:00:00Z',
        'inspection_date': '2026-08-20T00:00:00Z',
      };

      final i = Inspection.fromJson(json);

      expect(i.id, 42);
      expect(i.inspectionNumber, 'INSP-2026-0042');
      expect(i.title, 'EB Bunk Monthly Check');
      expect(i.status, InspectionStatus.open);
      expect(i.priority, InspectionPriority.medium);
      expect(i.stationName, 'Thalanallur');
      expect(i.reportedByName, 'depot_user');
      expect(i.inspectionDate, isNotNull);
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

    test('InspectionPriority.fromString defaults to medium', () {
      expect(InspectionPriority.fromString('CRITICAL'), InspectionPriority.critical);
      expect(InspectionPriority.fromString('HIGH'), InspectionPriority.high);
      expect(InspectionPriority.fromString('MEDIUM'), InspectionPriority.medium);
      expect(InspectionPriority.fromString('LOW'), InspectionPriority.low);
      expect(InspectionPriority.fromString(null), InspectionPriority.medium);
      expect(InspectionPriority.fromString('UNKNOWN'), InspectionPriority.medium);
    });

    test('fromJson tolerates legacy ticket_number and station fields', () {
      final json = {
        'id': 7,
        'ticket_number': 'INSP-LEGACY-07',
        'title': 'Legacy payload',
        'status': 'CLOSED',
      };
      final i = Inspection.fromJson(json);
      expect(i.inspectionNumber, 'INSP-LEGACY-07');
      expect(i.status, InspectionStatus.closed);
    });
  });
}
