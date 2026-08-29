import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';

void main() {
  group('Inspection Domain Model Tests', () {
    test('Inspection.fromJson parses full backend payload correctly', () {
      final json = {
        'id': 42,
        'inspection_number': 'INSP-2026-0042',
        'title': 'EB Bunk Monthly Check',
        'description': 'Check earth resistance and cleaning',
        'status': 'PENDING',
        'priority': 'HIGH',
        'station': 48,
        'station_name': 'Thalanallur',
        'depot': 23,
        'depot_name': 'Vriddhachalam Depot',
        'asset': 101,
        'asset_name': 'EB-01',
        'created_by_name': 'depot_user',
        'created_at': '2026-08-18T05:00:00Z',
        'scheduled_date': '2026-08-20T00:00:00Z',
      };

      final i = Inspection.fromJson(json);

      expect(i.id, 42);
      expect(i.inspectionNumber, 'INSP-2026-0042');
      expect(i.title, 'EB Bunk Monthly Check');
      expect(i.status, InspectionStatus.pending);
      expect(i.priority, InspectionPriority.high);
      expect(i.stationName, 'Thalanallur');
      expect(i.assetName, 'EB-01');
      expect(i.reportedByName, 'depot_user');
      expect(i.scheduledDate, isNotNull);
    });

    test('InspectionStatus.fromString handles all canonical values', () {
      expect(InspectionStatus.fromString('PENDING'), InspectionStatus.pending);
      expect(InspectionStatus.fromString('IN_PROGRESS'), InspectionStatus.inProgress);
      expect(InspectionStatus.fromString('COMPLETED'), InspectionStatus.completed);
      expect(InspectionStatus.fromString('CONVERTED'), InspectionStatus.converted);
      expect(InspectionStatus.fromString('CANCELLED'), InspectionStatus.cancelled);
      expect(InspectionStatus.fromString(null), InspectionStatus.unknown);
      expect(InspectionStatus.fromString('INVALID'), InspectionStatus.unknown);
      expect(InspectionStatus.fromString('pending'), InspectionStatus.pending);
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
        'status': 'COMPLETED',
      };
      final i = Inspection.fromJson(json);
      expect(i.inspectionNumber, 'INSP-LEGACY-07');
      expect(i.status, InspectionStatus.completed);
    });
  });
}
