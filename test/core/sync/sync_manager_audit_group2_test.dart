import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/network/paginated_fetch.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';

class MockWorkOrderApiService extends Mock implements WorkOrderApiService {}
class MockEvidenceService extends Mock implements EvidenceService {}

class _FakeEvidenceFallback extends Fake implements EvidenceService {}

OutboxCommand _command(
  String key,
  OutboxCommandType type,
  int entityId,
  Map<String, dynamic> payload,
) {
  return OutboxCommand(
    idempotencyKey: key,
    type: type,
    entityId: entityId,
    payload: payload,
    createdAt: DateTime.now(),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeEvidenceFallback());
  });

  group('H4 — enqueueDeduped atomic dedup (audit 2026-10-20)', () {
    late ILocalCacheService cacheService;
    late MockWorkOrderApiService mockApiService;
    late ProviderContainer container;
    late SyncManager syncManager;

    setUp(() {
      cacheService = InMemoryLocalCacheService();
      mockApiService = MockWorkOrderApiService();
      container = ProviderContainer(
        overrides: [
          localCacheServiceProvider.overrideWithValue(cacheService),
          workOrderApiServiceProvider.overrideWithValue(mockApiService),
          evidenceServiceProvider.overrideWithValue(MockEvidenceService()),
        ],
      );
      syncManager = container.read(syncManagerProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('two near-simultaneous deduped enqueues land exactly one command',
        () async {
      // Both enqueues start before either save lands — the old check-then-act
      // enqueued both (different idempotency keys ⇒ server applies twice).
      when(() => mockApiService.submitLine(
            10,
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((_) async {});

      final cmd = _command('line_10_7', OutboxCommandType.submitLine, 10,
          {'line_id': 7, 'value': '230V'});
      final results = await Future.wait([
        syncManager.enqueueDeduped(
          cmd,
          isDuplicate: (c) =>
              c.type == cmd.type &&
              c.entityId == cmd.entityId &&
              c.payload['line_id'] == cmd.payload['line_id'],
          autoDrain: false,
        ),
        syncManager.enqueueDeduped(
          cmd,
          isDuplicate: (c) =>
              c.type == cmd.type &&
              c.entityId == cmd.entityId &&
              c.payload['line_id'] == cmd.payload['line_id'],
          autoDrain: false,
        ),
      ]);

      expect(results.where((enqueued) => enqueued), hasLength(1));
      final stored = await cacheService.getOutboxCommands();
      expect(stored, hasLength(1));
    });

    test('verified H6: evidence without proof_path dedups on remarks+staff, '
        'distinct no-photo submissions are both kept', () async {
      final first = _command(
          'evidence_10_1', OutboxCommandType.uploadEvidence, 10,
          {'remarks': 'people A', 'other_staff': 'S1'});
      final enqueue = (OutboxCommand c) => syncManager.enqueueDeduped(
            c,
            isDuplicate: (existing) {
              final proof = existing.payload['proof_path'];
              if (c.payload['proof_path'] != null) {
                return proof == c.payload['proof_path'];
              }
              if (proof is String && proof.isNotEmpty) return false;
              return existing.payload['remarks'] == c.payload['remarks'] &&
                  existing.payload['other_staff'] == c.payload['other_staff'];
            },
            autoDrain: false,
          );

      expect(await enqueue(first), isTrue);
      // Same no-photo content → dedup hit.
      final duplicate = first.copyWith();
      expect(await enqueue(duplicate), isFalse);
      // Different no-photo submission → kept.
      final distinct = _command(
          'evidence_10_2', OutboxCommandType.uploadEvidence, 10,
          {'remarks': 'lonely station', 'other_staff': 'S2'});
      expect(await enqueue(distinct), isTrue);

      final stored = await cacheService.getOutboxCommands();
      expect(stored.map((c) => c.idempotencyKey),
          unorderedEquals(['evidence_10_1', 'evidence_10_2']));
    });
  });

  group('M6/M7 — retry budget and resume backoff (audit 2026-10-20)', () {
    late InMemoryLocalCacheService cacheService;
    late MockWorkOrderApiService mockApiService;
    late MockEvidenceService evidenceService;
    late ProviderContainer container;
    late SyncManager syncManager;

    setUp(() {
      cacheService = InMemoryLocalCacheService();
      mockApiService = MockWorkOrderApiService();
      evidenceService = MockEvidenceService();
      container = ProviderContainer(
        overrides: [
          localCacheServiceProvider.overrideWithValue(cacheService),
          workOrderApiServiceProvider.overrideWithValue(mockApiService),
          evidenceServiceProvider.overrideWithValue(evidenceService),
        ],
      );
      syncManager = container.read(syncManagerProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('offline drain enters resume backoff; user retry allocates a fresh budget', () async {
      when(() => evidenceService.cleanupExpiredEvidence(
          excludePaths: any(named: 'excludePaths'))).thenAnswer((_) async {});
      var submitAttempts = 0;
      when(() => mockApiService.submitLine(
            10,
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((_) {
        submitAttempts++;
        throw DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        );
      });

      final cmd = _command(
          'line_10_7', OutboxCommandType.submitLine, 10, {'line_id': 7});
      final enqueued = await syncManager
          .enqueueDeduped(cmd, isDuplicate: (_) => false, autoDrain: false);
      expect(enqueued, isTrue);

      // M7: manual retry grants a fresh retry budget even if capped.
      final capped =
          (await cacheService.getOutboxCommands()).single.copyWith(
        retryCount: 25,
        status: OutboxCommandStatus.failed,
      );
      await cacheService.saveOutboxCommands([capped]);
      await syncManager.retryCommand('line_10_7');
      final afterRetry = await cacheService.getOutboxCommands();
      // drainOutbox inside retryCommand hit the network once:
      expect(afterRetry.single.retryCount, 1,
          reason: 'explicit retry must start from zero, not stay capped');
      expect(afterRetry.single.status, OutboxCommandStatus.pending);
      final attemptsAfterExplicitRetry = submitAttempts;
      expect(attemptsAfterExplicitRetry, 1);

      // M6: the offline drain parked resume drains in backoff.
      await syncManager.resumePendingSync();
      expect(submitAttempts, attemptsAfterExplicitRetry,
          reason: 'a resume during backoff must not attempt the server');

      // Explicit user action drains regardless of backoff.
      await syncManager.retryCommand('line_10_7');
      expect(submitAttempts, greaterThan(attemptsAfterExplicitRetry),
          reason: 'retryCommand is explicit action and bypasses backoff');
    });
  });

  group('M8 — completion must not overtake unsynced line work', () {
    late InMemoryLocalCacheService cacheService;
    late MockWorkOrderApiService mockApiService;
    late MockEvidenceService evidenceService;
    late ProviderContainer container;
    late SyncManager syncManager;

    setUp(() {
      cacheService = InMemoryLocalCacheService();
      mockApiService = MockWorkOrderApiService();
      evidenceService = MockEvidenceService();
      container = ProviderContainer(
        overrides: [
          localCacheServiceProvider.overrideWithValue(cacheService),
          workOrderApiServiceProvider.overrideWithValue(mockApiService),
          evidenceServiceProvider.overrideWithValue(evidenceService),
        ],
      );
      syncManager = container.read(syncManagerProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('completeRecord waits while a submitLine for the record is unsynced',
        () async {
      await cacheService.saveOutboxCommands([
        _command('complete_10', OutboxCommandType.completeRecord, 10,
            {'technician_name': 'Tech', 'remarks': 'Done'}),
        _command(
            'line_10_3', OutboxCommandType.submitLine, 10, {'line_id': 3}),
      ]);
      when(() => evidenceService.cleanupExpiredEvidence(
          excludePaths: any(named: 'excludePaths'))).thenAnswer((_) async {});
      when(() => mockApiService.submitLine(
            10,
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((_) async {});

      await syncManager.drainOutbox();

      // Line went through; the completion is still queued.
      final remaining = await cacheService.getOutboxCommands();
      expect(remaining, hasLength(1));
      expect(remaining.single.idempotencyKey, 'complete_10');
      expect(remaining.single.status, OutboxCommandStatus.pending);
      verifyNever(() => mockApiService.completeRecord(
            10,
            technicianName: any(named: 'technicianName'),
            remarks: any(named: 'remarks'),
            supervisorName: any(named: 'supervisorName'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ));
    });

    test('tech-completed transition waits for unsynced line work too', () async {
      await cacheService.saveOutboxCommands([
        _command('trans_10', OutboxCommandType.transitionStatus, 10,
            {'status': 'TECH_COMPLETED'}),
        _command('line_10_4', OutboxCommandType.submitLine, 10,
            {'line_id': 4}),
      ]);
      when(() => evidenceService.cleanupExpiredEvidence(
          excludePaths: any(named: 'excludePaths'))).thenAnswer((_) async {});
      when(() => mockApiService.submitLine(
            10,
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((_) async {});

      await syncManager.drainOutbox();

      final remaining = await cacheService.getOutboxCommands();
      expect(remaining.single.idempotencyKey, 'trans_10');
    });
  });

  group('Low 5 / Low 8 — outbox status parsing and badge counts', () {
    test('unknown status code is parked as FAILED, never replayed', () {
      final status = OutboxCommandStatus.fromCode('GARBAGE');
      expect(status, OutboxCommandStatus.failed);
    });

    test('attention counts include other users’ commands present on disk',
        () async {
      final cacheService = InMemoryLocalCacheService();
      final mockApiService = MockWorkOrderApiService();
      final evidenceService = MockEvidenceService();
      final container = ProviderContainer(
        overrides: [
          localCacheServiceProvider.overrideWithValue(cacheService),
          workOrderApiServiceProvider.overrideWithValue(mockApiService),
          evidenceServiceProvider.overrideWithValue(evidenceService),
        ],
      );
      addTearDown(container.dispose);
      final syncManager = container.read(syncManagerProvider.notifier);

      // Current owner is user 1; user 2 has one FAILED command left on disk.
      await cacheService.saveOutboxCommands([
        _command('mine_1', OutboxCommandType.submitLine, 11, {'line_id': 1})
            .copyWith(ownerUserId: 1),
        _command('other_1', OutboxCommandType.submitLine, 12, {'line_id': 1})
            .copyWith(ownerUserId: 2, status: OutboxCommandStatus.failed),
      ]);
      await cacheService.setCacheOwnerUserId(1);

      when(() => evidenceService.cleanupExpiredEvidence(
          excludePaths: any(named: 'excludePaths'))).thenAnswer((_) async {});
      when(() => mockApiService.submitLine(
            11,
            any(),
            idempotencyKey: any(named: 'idempotencyKey'),
          )).thenAnswer((_) async {});

      await syncManager.drainOutbox();

      final state = container.read(syncManagerProvider);
      expect(state.pendingCount, 0,
          reason: 'user 1 queue is empty after drain');
      expect(state.attentionCount, 1,
          reason: 'the stuck FAILED command still on disk must be visible');
      expect(state.isFullySynced, isFalse);
    });
  });

  group('M4 — fetchAllPages truncation honesty', () {
    test('malformed `next` reports truncated: true', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      var calls = 0;
      dio.httpClientAdapter = MockHttpClientAdapterForPages((options) async {
        calls++;
        if (calls == 1) {
          return _pageBody({'results': [1, 2], 'next': ':::not a uri:::'});
        }
        return _pageBody({'results': []});
      });

      final result = await fetchAllPages(dio, '/api/v1/things/');
      expect(result.truncated, isTrue,
          reason: 'ends early with a `next` present ⇒ partial data');
    });

    test('repeating `next` reports truncated: true', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      var calls = 0;
      dio.httpClientAdapter = MockHttpClientAdapterForPages((options) async {
        calls++;
        return _pageBody({
          'results': [calls],
          'next': 'https://gssms.share.zrok.io/api/v1/things/?page=1'
        });
      });

      final result = await fetchAllPages(dio, '/api/v1/things/?page=1');
      expect(result.truncated, isTrue);
    });

    test('clean end of pagination reports truncated: false', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      var calls = 0;
      dio.httpClientAdapter = MockHttpClientAdapterForPages((options) async {
        calls++;
        return _pageBody(calls == 1 ? {'results': [1], 'next': null} : {'results': []});
      });

      final result = await fetchAllPages(dio, '/api/v1/things/');
      expect(result.truncated, isFalse);
      expect(result.items, [1]);
    });
  });
}

ResponseBody _pageBody(dynamic data) {
  return ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class MockHttpClientAdapterForPages implements HttpClientAdapter {
  MockHttpClientAdapterForPages(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
