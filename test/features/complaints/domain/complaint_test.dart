import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';

void main() {
  group('Complaint Domain Model Tests', () {
    test('Complaint.fromJson parses full backend payload correctly', () {
      final json = {
        'id': 12,
        'complaint_number': 'CMP-2026-0012',
        'title': 'Transformer oil leakage',
        'description': 'Oil dripping from valve A',
        'status': 'OPEN',
        'severity': 'HIGH',
        'station': 1,
        'station_name': 'VRI',
        'depot': 2,
        'depot_name': 'Vriddhachalam Depot',
        'asset': 88,
        'asset_name': 'TR-01',
        'created_by_name': 'tech_ramesh',
        'created_at': '2026-08-18T05:00:00Z',
      };

      final c = Complaint.fromJson(json);

      expect(c.id, 12);
      expect(c.complaintNumber, 'CMP-2026-0012');
      expect(c.title, 'Transformer oil leakage');
      expect(c.status, ComplaintStatus.open);
      expect(c.severity, ComplaintSeverity.high);
      expect(c.stationName, 'VRI');
      expect(c.assetName, 'TR-01');
      expect(c.reportedByName, 'tech_ramesh');
    });

    test('ComplaintStatus.fromString handles canonical values (SSOT §10.3)', () {
      expect(ComplaintStatus.fromString('OPEN'), ComplaintStatus.open);
      expect(ComplaintStatus.fromString('CONVERTED'), ComplaintStatus.converted);
      expect(ComplaintStatus.fromString('CLOSED'), ComplaintStatus.closed);
      // Removed backend values must map to unknown, never to invented states.
      expect(ComplaintStatus.fromString('in_progress'), ComplaintStatus.unknown);
      expect(ComplaintStatus.fromString('RESOLVED'), ComplaintStatus.unknown);
      expect(ComplaintStatus.fromString('REJECTED'), ComplaintStatus.unknown);
      expect(ComplaintStatus.fromString(null), ComplaintStatus.unknown);
      expect(ComplaintStatus.fromString('INVALID'), ComplaintStatus.unknown);
    });

    test('ComplaintSeverity.fromString defaults to medium on null or unrecognized values', () {
      expect(ComplaintSeverity.fromString('CRITICAL'), ComplaintSeverity.critical);
      expect(ComplaintSeverity.fromString('HIGH'), ComplaintSeverity.high);
      expect(ComplaintSeverity.fromString('MEDIUM'), ComplaintSeverity.medium);
      expect(ComplaintSeverity.fromString('LOW'), ComplaintSeverity.low);
      expect(ComplaintSeverity.fromString(null), ComplaintSeverity.medium);
      expect(ComplaintSeverity.fromString('UNKNOWN_SEV'), ComplaintSeverity.medium);
    });
  });
}
