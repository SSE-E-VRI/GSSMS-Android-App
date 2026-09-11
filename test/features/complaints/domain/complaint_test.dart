import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';

void main() {
  group('Complaint Domain Model Tests', () {
    // Fixture mirrors ComplaintSerializer (SSOT §10.1) exactly — no fields the
    // backend does not send.
    final json = {
      'id': 12,
      'title': 'Transformer oil leakage',
      'description': 'Oil dripping from valve A',
      'source': 'MANUAL',
      'status': 'CONVERTED',
      'department': 'ELECTRICAL',
      'station': 1,
      'station_name': 'VRI',
      'depot': 2,
      'depot_name': 'Vriddhachalam Depot',
      'infrastructure': null,
      'infrastructure_name': null,
      'asset': 88,
      'asset_unique_id': 'VRI-SS01-TR-001',
      'created_at': '2026-09-09T14:30:00+05:30',
      'is_converted': true,
      'wo_id': 501,
      'wo_status': 'IN_PROGRESS',
      'wo_ticket_number': 'VRI-202609-0042',
    };

    test('Complaint.fromJson parses the serializer payload', () {
      final c = Complaint.fromJson(json);

      expect(c.id, 12);
      expect(c.reference, '#12');
      expect(c.title, 'Transformer oil leakage');
      expect(c.status, ComplaintStatus.converted);
      expect(c.department, 'ELECTRICAL');
      expect(c.stationName, 'VRI');
      expect(c.assetId, 88);
      expect(c.assetUniqueId, 'VRI-SS01-TR-001');
      expect(c.isConverted, isTrue);
      expect(c.workOrderId, 501);
      expect(c.workOrderStatus, 'IN_PROGRESS');
      expect(c.workOrderTicketNumber, 'VRI-202609-0042');
    });

    // Regression B11: DRF sends `+05:30`; Dart parses that to UTC, and the
    // screens used to format the UTC fields — 14:30 IST displayed as 09:00.
    test('created_at is converted to device-local time', () {
      final c = Complaint.fromJson(json);
      expect(c.createdAt!.isUtc, isFalse);
      expect(
        c.createdAt!.isAtSameMomentAs(DateTime.utc(2026, 9, 9, 9, 0)),
        isTrue,
      );
    });

    test('location label follows the Web register (getInfraName)', () {
      expect(Complaint.fromJson(json).locationLabel, 'VRI (Station)');
      expect(
        Complaint.fromJson(const {
          'id': 1,
          'title': 't',
          'lc_gate_number': '42A',
        }).locationLabel,
        'Gate 42A (LC Gate)',
      );
      expect(Complaint.fromJson(const {'id': 1, 'title': 't'}).locationLabel, isNull);
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

    test('markConverted keeps identity and records the Job Work id', () {
      const open = Complaint(id: 3, title: 'x', status: ComplaintStatus.open);
      final converted = open.markConverted(workOrderId: 9);
      expect(converted.status, ComplaintStatus.converted);
      expect(converted.isConverted, isTrue);
      expect(converted.workOrderId, 9);
      expect(converted.title, 'x');
    });
  });
}
