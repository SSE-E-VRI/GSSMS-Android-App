import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';

void main() {
  group('EvidenceSource (ME-01)', () {
    test('maps server codes and defaults to UNKNOWN', () {
      expect(EvidenceSource.fromCode('CAMERA'), EvidenceSource.camera);
      expect(EvidenceSource.fromCode('gallery'), EvidenceSource.gallery);
      expect(EvidenceSource.fromCode('UNKNOWN'), EvidenceSource.unknown);
      expect(EvidenceSource.fromCode('banana'), EvidenceSource.unknown);
      expect(EvidenceSource.fromCode(null), EvidenceSource.unknown);
    });
  });

  group('EvidenceLocation.validated (ME-05)', () {
    final ts = DateTime.utc(2026, 10, 20, 6, 0);

    test('accepts a complete finite ranged fix', () {
      final loc = EvidenceLocation.validated(12.345, 78.68, 8.0, ts);
      expect(loc, isNotNull);
      expect(loc!.latitude, 12.345);
      expect(loc.longitude, 78.68);
      expect(loc.accuracyM, 8.0);
      expect(loc.recordedAt, ts);
    });

    test('rejects partial metadata (all-or-nothing)', () {
      expect(EvidenceLocation.validated(null, 78.68, 8.0, ts), isNull);
      expect(EvidenceLocation.validated(12.3, null, 8.0, ts), isNull);
      expect(EvidenceLocation.validated(12.3, 78.68, null, ts), isNull);
      expect(EvidenceLocation.validated(12.3, 78.68, 8.0, null), isNull);
    });

    test('rejects out-of-range or non-finite coordinates', () {
      expect(EvidenceLocation.validated(90.5, 78.68, 8.0, ts), isNull);
      expect(EvidenceLocation.validated(-90.5, 78.68, 8.0, ts), isNull);
      expect(EvidenceLocation.validated(12.3, 181.0, 8.0, ts), isNull);
      expect(EvidenceLocation.validated(double.nan, 78.68, 8.0, ts), isNull);
    });

    test('rejects negative accuracy', () {
      expect(EvidenceLocation.validated(12.3, 78.68, -1.0, ts), isNull);
      expect(
          EvidenceLocation.validated(12.3, 78.68, double.infinity, ts), isNull);
    });
  });

  group('EvidenceFile.withCapture (ME-01–ME-04)', () {
    const base = EvidenceFile(
      path: '/docs/gssms_evidence/after_1.jpg',
      sizeBytes: 100,
      kind: EvidenceKind.after,
    );
    final fix = EvidenceLocation(
      latitude: 12.345,
      longitude: 78.68,
      accuracyM: 8.0,
      recordedAt: DateTime.utc(2026, 10, 20, 6, 0),
    );

    test('camera rows keep captured_at and the fix only when valid', () {
      final decorated = base.withCapture(
        source: EvidenceSource.camera,
        capturedAt: DateTime.utc(2026, 10, 20, 6, 0, 1),
        location: fix,
      );
      expect(decorated.source, EvidenceSource.camera);
      expect(decorated.capturedAt, isNotNull);
      expect(decorated.location, fix);
    });

    test('camera without a fix keeps the photo without GPS (ME-03)', () {
      final decorated = base.withCapture(
        source: EvidenceSource.camera,
        capturedAt: DateTime.utc(2026, 10, 20, 6, 0, 1),
        location: null,
      );
      expect(decorated.source, EvidenceSource.camera);
      expect(decorated.location, isNull);
    });

    test('gallery rows never get captured_at or a device fix (ME-04)', () {
      final decorated = base.withCapture(
        source: EvidenceSource.gallery,
        capturedAt: DateTime.utc(2026, 10, 20, 6, 0, 1),
        location: fix,
      );
      expect(decorated.source, EvidenceSource.gallery);
      expect(decorated.capturedAt, isNull);
      expect(decorated.location, isNull);
    });
  });
}
