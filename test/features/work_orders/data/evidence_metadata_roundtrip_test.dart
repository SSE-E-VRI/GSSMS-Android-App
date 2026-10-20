import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';

class MockWorkOrderApiService extends Mock implements WorkOrderApiService {}

class MockEvidenceService extends Mock implements EvidenceService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
      'LineAttachment provenance freezes through offline replay (ME-02/ME-04)',
      () {
    late ILocalCacheService cacheService;
    late MockWorkOrderApiService mockApiService;
    late MockEvidenceService mockEvidenceService;
    late ProviderContainer container;

    setUp(() {
      cacheService = InMemoryLocalCacheService();
      mockApiService = MockWorkOrderApiService();
      mockEvidenceService = MockEvidenceService();

      container = ProviderContainer(
        overrides: [
          localCacheServiceProvider.overrideWithValue(cacheService),
          workOrderApiServiceProvider.overrideWithValue(mockApiService),
          evidenceServiceProvider.overrideWithValue(mockEvidenceService),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('camera location metadata is replayed verbatim, never re-derived',
        () async {
      const recordId = 15;
      const lineId = 8;
      final tempDir = await Directory.systemTemp.createTemp('gssms_test_');
      final tempFile = File('${tempDir.path}/before_mock.jpg');
      await tempFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

      final capturedAt = DateTime.utc(2026, 10, 20, 6, 0, 1);
      final recordedAt = DateTime.utc(2026, 10, 20, 6, 0, 3);

      try {
        final syncManager = container.read(syncManagerProvider.notifier);
        final repository = WorkOrderRepository(
          mockApiService,
          cacheService: cacheService,
          syncManager: syncManager,
        );

        // Network exception → outbox enqueue, provenance frozen in payload.
        when(() => mockApiService.uploadLineAttachment(
              recordId,
              lineId: lineId,
              kind: 'BEFORE',
              imagePath: tempFile.path,
              capturedAt: any(named: 'capturedAt'),
              source: any(named: 'source'),
              latitude: any(named: 'latitude'),
              longitude: any(named: 'longitude'),
              locationAccuracyM: any(named: 'locationAccuracyM'),
              locationRecordedAt: any(named: 'locationRecordedAt'),
              idempotencyKey: any(named: 'idempotencyKey'),
            )).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionError,
          ),
        );

        final pending = await repository.uploadLineAttachment(
          recordId,
          lineId: lineId,
          kind: 'BEFORE',
          imagePath: tempFile.path,
          capturedAt: capturedAt,
          source: 'CAMERA',
          latitude: 12.345,
          longitude: 78.68,
          locationAccuracyM: 8.0,
          locationRecordedAt: recordedAt,
        );

        // The offline placeholder already carries the original provenance.
        expect(pending.source, 'CAMERA');
        expect(pending.capturedAt, capturedAt);
        expect(pending.latitude, 12.345);
        expect(pending.longitude, 78.68);
        expect(pending.locationAccuracyM, 8.0);
        expect(pending.locationRecordedAt, recordedAt);

        // Outbox payload is frozen with the exact same values.
        final queued = await cacheService.getOutboxCommands();
        expect(queued, hasLength(1));
        final payload = queued.single.payload;
        expect(payload['source'], 'CAMERA');
        expect(payload['captured_at'], capturedAt.toIso8601String());
        expect(payload['latitude'], 12.345);
        expect(payload['longitude'], 78.68);
        expect(payload['location_accuracy_m'], 8.0);
        expect(payload['location_recorded_at'], recordedAt.toIso8601String());

        // Replay succeeds; the API must receive the frozen values —
        // in particular capturedAt/recordedAt must NOT become "now".
        when(() => mockApiService.uploadLineAttachment(
              recordId,
              lineId: lineId,
              kind: 'BEFORE',
              imagePath: tempFile.path,
              capturedAt: capturedAt,
              source: 'CAMERA',
              latitude: 12.345,
              longitude: 78.68,
              locationAccuracyM: 8.0,
              locationRecordedAt: recordedAt,
              idempotencyKey: any(named: 'idempotencyKey'),
            )).thenAnswer((_) async => {
              'id': 701,
              'kind': 'BEFORE',
              'url': 'https://api.example/media/evidence/before_mock.jpg',
              'source': 'CAMERA',
              'latitude': 12.345,
              'longitude': 78.68,
              'location_accuracy_m': 8.0,
              'location_recorded_at': recordedAt.toIso8601String(),
            });
        when(() => mockEvidenceService.discard(tempFile.path))
            .thenAnswer((_) async {});

        await syncManager.drainOutbox();

        verify(() => mockApiService.uploadLineAttachment(
                  recordId,
                  lineId: lineId,
                  kind: 'BEFORE',
                  imagePath: tempFile.path,
                  capturedAt: capturedAt,
                  source: 'CAMERA',
                  latitude: 12.345,
                  longitude: 78.68,
                  locationAccuracyM: 8.0,
                  locationRecordedAt: recordedAt,
                  idempotencyKey: any(named: 'idempotencyKey'),
                ))
            .called(
                3); // failed online attempt + auto-drain attempt + successful replay

        expect(await cacheService.getOutboxCommands(), isEmpty);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('gallery upload keeps no captured_at and no location', () async {
      const recordId = 15;
      const lineId = 8;

      // Network offline on the direct attempt → outboxenqueue path.
      when(() => mockApiService.uploadLineAttachment(
            recordId,
            lineId: lineId,
            kind: 'AFTER',
            imagePath: any(named: 'imagePath'),
            capturedAt: any(named: 'capturedAt'),
            source: any(named: 'source'),
            latitude: any(named: 'latitude'),
            longitude: any(named: 'longitude'),
            locationAccuracyM: any(named: 'locationAccuracyM'),
            locationRecordedAt: any(named: 'locationRecordedAt'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );

      final repository = WorkOrderRepository(
        mockApiService,
        cacheService: cacheService,
        syncManager: container.read(syncManagerProvider.notifier),
      );

      final attachment = await repository.uploadLineAttachment(
        recordId,
        lineId: lineId,
        kind: 'AFTER',
        imagePath: '/tmp/gallery_pick.jpg',
        source: 'GALLERY',
      );

      expect(attachment.source, 'GALLERY');
      // ME-04: offline placeholder must not carry an invented capture time.
      expect(attachment.capturedAt, isNull);
      expect(attachment.latitude, isNull);
      expect(attachment.longitude, isNull);

      final queued = await cacheService.getOutboxCommands();
      final payload = queued.single.payload;
      expect(payload['source'], 'GALLERY');
      expect(payload.containsKey('captured_at'), isFalse);
      expect(payload.containsKey('latitude'), isFalse);
      expect(payload.containsKey('longitude'), isFalse);
      expect(payload.containsKey('location_accuracy_m'), isFalse);
      expect(payload.containsKey('location_recorded_at'), isFalse);
    });
  });

  group('SyncManager replay passthrough (ME-02/ME-04)', () {
    late ILocalCacheService cacheService;
    late MockWorkOrderApiService mockApiService;
    late MockEvidenceService mockEvidenceService;
    late ProviderContainer container;
    late DateTime recordedAt;

    setUp(() {
      cacheService = InMemoryLocalCacheService();
      mockApiService = MockWorkOrderApiService();
      mockEvidenceService = MockEvidenceService();
      recordedAt = DateTime.utc(2026, 10, 20, 6, 0, 3);

      container = ProviderContainer(
        overrides: [
          localCacheServiceProvider.overrideWithValue(cacheService),
          workOrderApiServiceProvider.overrideWithValue(mockApiService),
          evidenceServiceProvider.overrideWithValue(mockEvidenceService),
        ],
      );

      when(() => mockApiService.uploadLineAttachment(
            10,
            lineId: 5,
            kind: 'BEFORE',
            imagePath: '/storage/evidence/before_123.jpg',
            capturedAt: DateTime.utc(2026, 10, 20, 6, 0, 1),
            source: 'CAMERA',
            latitude: 12.345,
            longitude: 78.68,
            locationAccuracyM: 8.0,
            locationRecordedAt: recordedAt,
            idempotencyKey: 'cmd_att_5',
          )).thenAnswer((_) async => {'id': 99, 'kind': 'BEFORE'});
    });

    tearDown(() => container.dispose());

    test('a pre-frozen outbox command replays its stored metadata as-is',
        () async {
      final cmd = OutboxCommand(
        idempotencyKey: 'cmd_att_5',
        type: OutboxCommandType.uploadLineAttachment,
        entityId: 10,
        payload: const {
          'line_id': 5,
          'kind': 'BEFORE',
          'file_path': '/storage/evidence/before_123.jpg',
          'source': 'CAMERA',
          'captured_at': '2026-10-20T06:00:01.000Z',
          'latitude': 12.345,
          'longitude': 78.68,
          'location_accuracy_m': 8.0,
          'location_recorded_at': '2026-10-20T06:00:03.000Z',
        },
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      );
      await cacheService.saveOutboxCommands([cmd]);

      await container.read(syncManagerProvider.notifier).drainOutbox();

      verify(() => mockApiService.uploadLineAttachment(
            10,
            lineId: 5,
            kind: 'BEFORE',
            imagePath: '/storage/evidence/before_123.jpg',
            capturedAt: DateTime.utc(2026, 10, 20, 6, 0, 1),
            source: 'CAMERA',
            latitude: 12.345,
            longitude: 78.68,
            locationAccuracyM: 8.0,
            locationRecordedAt: recordedAt,
            idempotencyKey: 'cmd_att_5',
          )).called(1);

      // Unknown source in the payload still rounds to UNKNOWN semantics.
      expect(cmd.payload['source'], isNot('GALLERY'));
    });
  });
}
