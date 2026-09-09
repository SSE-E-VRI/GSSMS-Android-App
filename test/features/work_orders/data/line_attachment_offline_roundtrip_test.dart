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

  group('LineAttachment offline round-trip', () {
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

    test('offline capture queues command -> reconnect drains multipart upload and discards local file',
        () async {
      const recordId = 15;
      const lineId = 8;
      final tempDir = await Directory.systemTemp.createTemp('gssms_test_');
      final tempFile = File('${tempDir.path}/before_mock.jpg');
      await tempFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]); // JPEG magic bytes

      try {
        final syncManager = container.read(syncManagerProvider.notifier);
        final repository = WorkOrderRepository(
          mockApiService,
          cacheService: cacheService,
          syncManager: syncManager,
        );

        // 1. First upload attempt encounters network connection error
        when(() => mockApiService.uploadLineAttachment(
              recordId,
              lineId: lineId,
              kind: 'BEFORE',
              imagePath: tempFile.path,
              capturedAt: any(named: 'capturedAt'),
              idempotencyKey: any(named: 'idempotencyKey'),
            )).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionError,
          ),
        );

        final pendingAttachment = await repository.uploadLineAttachment(
          recordId,
          lineId: lineId,
          kind: 'BEFORE',
          imagePath: tempFile.path,
        );

        // Verify returns pending attachment
        expect(pendingAttachment.kind, 'BEFORE');
        expect(pendingAttachment.localPath, tempFile.path);
        expect(pendingAttachment.syncStatus, OutboxCommandStatus.pending);
        expect(pendingAttachment.idempotencyKey, isNotNull);

        // Verify queued in outbox
        final queued = await cacheService.getOutboxCommands();
        expect(queued.length, 1);
        expect(queued.first.type, OutboxCommandType.uploadLineAttachment);
        expect(queued.first.entityId, recordId);
        expect(queued.first.payload['line_id'], lineId);
        expect(queued.first.payload['kind'], 'BEFORE');
        expect(queued.first.payload['file_path'], tempFile.path);

        // 2. Connectivity restored: next upload succeeds
        when(() => mockApiService.uploadLineAttachment(
              recordId,
              lineId: lineId,
              kind: 'BEFORE',
              imagePath: tempFile.path,
              capturedAt: any(named: 'capturedAt'),
              idempotencyKey: any(named: 'idempotencyKey'),
            )).thenAnswer((_) async => {
              'id': 701,
              'kind': 'BEFORE',
              'url': 'https://api.railways.gov.in/media/evidence/before_mock.jpg',
            });

        when(() => mockEvidenceService.discard(tempFile.path))
            .thenAnswer((_) async {});

        // Drain outbox on reconnect
        await syncManager.drainOutbox();

        // Verify API was called with multipart parameters
        verify(() => mockApiService.uploadLineAttachment(
              recordId,
              lineId: lineId,
              kind: 'BEFORE',
              imagePath: tempFile.path,
              capturedAt: any(named: 'capturedAt'),
              idempotencyKey: any(named: 'idempotencyKey'),
            )).called(3); // 1 offline direct attempt + 1 autoDrain attempt + 1 successful drain on reconnect

        // Verify discard was called on accepted upload
        verify(() => mockEvidenceService.discard(tempFile.path)).called(1);

        // Verify outbox is drained
        final remaining = await cacheService.getOutboxCommands();
        expect(remaining, isEmpty);
        expect(container.read(syncManagerProvider).pendingCount, 0);
        expect(container.read(syncManagerProvider).mode, SyncConnectivityMode.online);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
