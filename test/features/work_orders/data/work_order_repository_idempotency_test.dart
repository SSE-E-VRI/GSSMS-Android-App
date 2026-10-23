import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/mutation_outcome.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:mocktail/mocktail.dart';

class MockApi extends Mock implements WorkOrderApiService {}

class MockSync extends Mock implements SyncManager {}

class FakeCmd extends Fake implements OutboxCommand {}

class CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'id': 1}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioException _timeout() => DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionTimeout,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(FakeCmd());
  });

  late MockApi api;
  late MockSync sync;
  late WorkOrderRepository repo;
  late InMemoryLocalCacheService cache;

  setUp(() {
    api = MockApi();
    sync = MockSync();
    cache = InMemoryLocalCacheService();
    repo = WorkOrderRepository(
      api,
      cacheService: cache,
      syncManager: sync,
    );
    when(() => sync.enqueueDeduped(any(),
        isDuplicate: any(named: 'isDuplicate'))).thenAnswer((_) async => true);
  });

  OutboxCommand queued() {
    final cmd = verify(() => sync.enqueueDeduped(captureAny(),
        isDuplicate: any(named: 'isDuplicate'))).captured.single;
    return cmd as OutboxCommand;
  }

  const key = 'idempotencyKey';

  group('first attempt and queued command share one idempotency key', () {
    test('startExecution', () async {
      when(() => api.startExecution(7, idempotencyKey: any(named: key)))
          .thenThrow(_timeout());
      await expectLater(
          repo.startExecution(7), throwsA(isA<StartExecutionQueuedOffline>()));
      final sent = verify(() =>
              api.startExecution(7, idempotencyKey: captureAny(named: key)))
          .captured
          .single as String?;
      expect(sent, isNotNull);
      expect(queued().idempotencyKey, sent);
    });

    test('transitionStatus', () async {
      when(() => api.changeStatus(7,
          status: 'TECH_COMPLETED',
          remarks: any(named: 'remarks'),
          checklist: any(named: 'checklist'),
          evidence: any(named: 'evidence'),
          idempotencyKey: any(named: key))).thenThrow(_timeout());
      await cache.cacheWorkOrderDetail(const WorkOrder(
        id: 7,
        status: WorkOrderStatus.assigned,
        type: WorkOrderType.preventive,
        title: 'WO',
      ));
      await repo.transitionStatus(7, status: 'TECH_COMPLETED');
      final sent = verify(() => api.changeStatus(7,
              status: 'TECH_COMPLETED',
              remarks: any(named: 'remarks'),
              checklist: any(named: 'checklist'),
              evidence: any(named: 'evidence'),
              idempotencyKey: captureAny(named: key)))
          .captured
          .single as String?;
      expect(sent, isNotNull);
      expect(queued().idempotencyKey, sent);
    });

    test('submitChecklistLine', () async {
      when(() => api.submitLine(5, any(), idempotencyKey: any(named: key)))
          .thenThrow(_timeout());
      final outcome = await repo.submitChecklistLine(5, {'line_id': 3});
      expect(outcome, MutationOutcome.queued);
      final sent = verify(() =>
              api.submitLine(5, any(), idempotencyKey: captureAny(named: key)))
          .captured
          .single as String?;
      expect(sent, isNotNull);
      expect(queued().idempotencyKey, sent);
    });

    test('uploadEvidence', () async {
      when(() => api.uploadRecordEvidence(5,
          proofJpegPath: any(named: 'proofJpegPath'),
          remarks: any(named: 'remarks'),
          otherStaff: any(named: 'otherStaff'),
          idempotencyKey: any(named: key))).thenThrow(_timeout());
      final outcome = await repo.uploadEvidence(5, remarks: 'done');
      expect(outcome, MutationOutcome.queued);
      final sent = verify(() => api.uploadRecordEvidence(5,
              proofJpegPath: any(named: 'proofJpegPath'),
              remarks: any(named: 'remarks'),
              otherStaff: any(named: 'otherStaff'),
              idempotencyKey: captureAny(named: key)))
          .captured
          .single as String?;
      expect(sent, isNotNull);
      expect(queued().idempotencyKey, sent);
    });

    test('completeMaintenanceRecord', () async {
      when(() => api.completeRecord(5,
          technicianName: any(named: 'technicianName'),
          remarks: any(named: 'remarks'),
          supervisorName: any(named: 'supervisorName'),
          idempotencyKey: any(named: key))).thenThrow(_timeout());
      final outcome = await repo.completeMaintenanceRecord(5,
          technicianName: 'T', remarks: 'All work completed fine');
      expect(outcome, MutationOutcome.queued);
      final sent = verify(() => api.completeRecord(5,
              technicianName: any(named: 'technicianName'),
              remarks: any(named: 'remarks'),
              supervisorName: any(named: 'supervisorName'),
              idempotencyKey: captureAny(named: key)))
          .captured
          .single as String?;
      expect(sent, isNotNull);
      expect(queued().idempotencyKey, sent);
    });
  });

  group('online success passes a non-null key', () {
    test('startExecution', () async {
      when(() => api.startExecution(7, idempotencyKey: any(named: key)))
          .thenAnswer((_) async => 99);
      expect(await repo.startExecution(7), 99);
      final sent = verify(() =>
              api.startExecution(7, idempotencyKey: captureAny(named: key)))
          .captured
          .single;
      expect(sent, isNotNull);
    });

    test('submitChecklistLine', () async {
      when(() => api.submitLine(5, any(), idempotencyKey: any(named: key)))
          .thenAnswer((_) async {});
      expect(await repo.submitChecklistLine(5, {'line_id': 3}),
          MutationOutcome.synced);
      final sent = verify(() =>
              api.submitLine(5, any(), idempotencyKey: captureAny(named: key)))
          .captured
          .single;
      expect(sent, isNotNull);
      verifyNever(() => sync.enqueueDeduped(any(),
          isDuplicate: any(named: 'isDuplicate')));
    });

    test('completeMaintenanceRecord', () async {
      when(() => api.completeRecord(5,
          technicianName: any(named: 'technicianName'),
          remarks: any(named: 'remarks'),
          supervisorName: any(named: 'supervisorName'),
          idempotencyKey: any(named: key))).thenAnswer((_) async {});
      await repo.completeMaintenanceRecord(5,
          technicianName: 'T', remarks: 'All work completed fine');
      final sent = verify(() => api.completeRecord(5,
              technicianName: any(named: 'technicianName'),
              remarks: any(named: 'remarks'),
              supervisorName: any(named: 'supervisorName'),
              idempotencyKey: captureAny(named: key)))
          .captured
          .single;
      expect(sent, isNotNull);
    });
  });

  group('upload API methods use long per-request timeouts', () {
    late Directory dir;
    late File photo;
    late CapturingAdapter adapter;
    late WorkOrderApiService service;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wo_upload_test');
      photo = File('${dir.path}${Platform.pathSeparator}p.jpg');
      await photo.writeAsBytes(List<int>.filled(16, 1));
      adapter = CapturingAdapter();
      final dio = Dio(BaseOptions(
        baseUrl: 'http://localhost',
        receiveTimeout: const Duration(seconds: 15),
      ))
        ..httpClientAdapter = adapter;
      service = WorkOrderApiService(dio);
    });

    tearDown(() async {
      // Windows keeps the multipart file handle open briefly; temp-dir cleanup
      // must not fail the test.
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Best effort: the OS temp cleaner removes it later.
      }
    });

    test('uploadRecordEvidence', () async {
      await service.uploadRecordEvidence(5,
          proofJpegPath: photo.path, idempotencyKey: 'k1');
      final o = adapter.requests.single;
      expect(o.sendTimeout!, greaterThanOrEqualTo(const Duration(seconds: 120)));
      expect(
          o.receiveTimeout!, greaterThanOrEqualTo(const Duration(seconds: 120)));
      expect(o.headers['X-Idempotency-Key'], 'k1');
      expect(o.headers['Idempotency-Key'], 'k1');
    });

    test('uploadLineAttachment', () async {
      await service.uploadLineAttachment(5,
          lineId: 2,
          kind: 'before',
          imagePath: photo.path,
          idempotencyKey: 'k2');
      final o = adapter.requests.single;
      expect(o.sendTimeout!, greaterThanOrEqualTo(const Duration(seconds: 120)));
      expect(
          o.receiveTimeout!, greaterThanOrEqualTo(const Duration(seconds: 120)));
      expect(o.headers['X-Idempotency-Key'], 'k2');
    });
  });
}
