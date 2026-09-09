import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';

class MockWorkOrderApiService extends Mock implements WorkOrderApiService {}
class MockEvidenceService extends Mock implements EvidenceService {}

void main() {
  group('SyncManager line attachment ordering guard & discard', () {
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

    test('attachment command does NOT execute if submitLine for same line fails', () async {
      const recordId = 10;
      const lineId = 5;

      // submitLine fails with 400 validation error
      when(() => mockApiService.submitLine(
            recordId,
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 400,
            data: {'error': 'Invalid observation'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final submitCmd = OutboxCommand(
        idempotencyKey: 'cmd_submit_line_5',
        type: OutboxCommandType.submitLine,
        entityId: recordId,
        payload: const {'line_id': lineId, 'value': 'DEFECTIVE'},
        createdAt: DateTime.now(),
      );

      final attachCmd = OutboxCommand(
        idempotencyKey: 'cmd_attach_line_5',
        type: OutboxCommandType.uploadLineAttachment,
        entityId: recordId,
        payload: const {
          'line_id': lineId,
          'kind': 'BEFORE',
          'file_path': '/storage/evidence/before_123.jpg',
        },
        createdAt: DateTime.now(),
      );

      await cacheService.saveOutboxCommands([submitCmd, attachCmd]);

      await container.read(syncManagerProvider.notifier).drainOutbox();

      // Verify uploadLineAttachment was NEVER called because prerequisite submitLine failed
      verifyNever(() => mockApiService.uploadLineAttachment(
            any(),
            lineId: any(named: 'lineId'),
            kind: any(named: 'kind'),
            imagePath: any(named: 'imagePath'),
            capturedAt: any(named: 'capturedAt'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ));

      verifyNever(() => mockEvidenceService.discard(any()));

      final remaining = await cacheService.getOutboxCommands();
      expect(remaining.length, 2);
      expect(remaining[0].idempotencyKey, 'cmd_submit_line_5');
      expect(remaining[0].status, OutboxCommandStatus.failed);
      expect(remaining[1].idempotencyKey, 'cmd_attach_line_5');
      expect(remaining[1].status, OutboxCommandStatus.pending);
    });

    test('attachment executes and discards local file once submitLine succeeds', () async {
      const recordId = 10;
      const lineId = 5;
      const filePath = '/storage/evidence/before_123.jpg';

      when(() => mockApiService.submitLine(
            recordId,
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((_) async {});

      when(() => mockApiService.uploadLineAttachment(
            recordId,
            lineId: lineId,
            kind: 'BEFORE',
            imagePath: filePath,
            capturedAt: any(named: 'capturedAt'),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((_) async => {'id': 99, 'kind': 'BEFORE'});

      when(() => mockEvidenceService.discard(filePath)).thenAnswer((_) async {});

      final submitCmd = OutboxCommand(
        idempotencyKey: 'cmd_submit_line_5',
        type: OutboxCommandType.submitLine,
        entityId: recordId,
        payload: const {'line_id': lineId, 'value': 'DEFECTIVE'},
        createdAt: DateTime.now(),
      );

      final attachCmd = OutboxCommand(
        idempotencyKey: 'cmd_attach_line_5',
        type: OutboxCommandType.uploadLineAttachment,
        entityId: recordId,
        payload: const {
          'line_id': lineId,
          'kind': 'BEFORE',
          'file_path': filePath,
        },
        createdAt: DateTime.now(),
      );

      await cacheService.saveOutboxCommands([submitCmd, attachCmd]);

      await container.read(syncManagerProvider.notifier).drainOutbox();

      verify(() => mockApiService.submitLine(
            recordId,
            any(),
            idempotencyKey: 'cmd_submit_line_5',
          )).called(1);

      verify(() => mockApiService.uploadLineAttachment(
            recordId,
            lineId: lineId,
            kind: 'BEFORE',
            imagePath: filePath,
            capturedAt: any(named: 'capturedAt'),
            idempotencyKey: 'cmd_attach_line_5',
          )).called(1);

      verify(() => mockEvidenceService.discard(filePath)).called(1);

      final remaining = await cacheService.getOutboxCommands();
      expect(remaining, isEmpty);
    });
  });
}
