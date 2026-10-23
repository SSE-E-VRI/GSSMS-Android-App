import 'dart:async';
import 'dart:io';

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

class _MockApi extends Mock implements WorkOrderApiService {}

class _MockEvidence extends Mock implements EvidenceService {}

OutboxCommand _cmd(
  String key,
  OutboxCommandType type,
  int entityId,
  Map<String, dynamic> payload, {
  int? ownerUserId,
}) =>
    OutboxCommand(
      idempotencyKey: key,
      type: type,
      entityId: entityId,
      payload: payload,
      createdAt: DateTime.now(),
      ownerUserId: ownerUserId,
    );

DioException _http(int status, {Map<String, List<String>>? headers}) {
  final ro = RequestOptions(path: '/');
  return DioException(
    requestOptions: ro,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: ro,
      statusCode: status,
      headers: Headers.fromMap(headers ?? const {}),
    ),
  );
}

void main() {
  late InMemoryLocalCacheService cache;
  late _MockApi api;
  late _MockEvidence evidence;
  late ProviderContainer container;
  late SyncManager manager;

  void stubSubmitThrows(Object error) {
    when(() => api.submitLine(
          10,
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).thenAnswer((_) => Future<void>.error(error));
  }

  setUp(() {
    cache = InMemoryLocalCacheService();
    api = _MockApi();
    evidence = _MockEvidence();
    when(() => evidence.cleanupExpiredEvidence(
        excludePaths: any(named: 'excludePaths'))).thenAnswer((_) async {});
    container = ProviderContainer(overrides: [
      localCacheServiceProvider.overrideWithValue(cache),
      workOrderApiServiceProvider.overrideWithValue(api),
      evidenceServiceProvider.overrideWithValue(evidence),
    ]);
    manager = container.read(syncManagerProvider.notifier);
  });

  tearDown(() => container.dispose());

  Future<OutboxCommand> drainSingleSubmitLine() async {
    await cache.saveOutboxCommands([
      _cmd('line_10_1', OutboxCommandType.submitLine, 10, {'line_id': 1}),
    ]);
    await manager.drainOutbox();
    return (await cache.getOutboxCommands()).single;
  }

  group('transient HTTP statuses keep the command pending', () {
    for (final status in [503, 502, 504, 429, 408]) {
      test('$status -> pending, retryCount + 1, mode offline', () async {
        stubSubmitThrows(_http(status));
        final cmd = await drainSingleSubmitLine();
        expect(cmd.status, OutboxCommandStatus.pending);
        expect(cmd.retryCount, 1);
        expect(container.read(syncManagerProvider).mode,
            SyncConnectivityMode.offline);
      });
    }

    test('429 with Retry-After still stays pending', () async {
      stubSubmitThrows(_http(429, headers: {
        'retry-after': ['120']
      }));
      final cmd = await drainSingleSubmitLine();
      expect(cmd.status, OutboxCommandStatus.pending);
      expect(cmd.retryCount, 1);
    });

    test('retry cap parks a transient failure as FAILED', () async {
      stubSubmitThrows(_http(503));
      await cache.saveOutboxCommands([
        _cmd('line_10_1', OutboxCommandType.submitLine, 10, {'line_id': 1})
            .copyWith(retryCount: 25),
      ]);
      await manager.drainOutbox();
      final cmd = (await cache.getOutboxCommands()).single;
      expect(cmd.status, OutboxCommandStatus.failed);
    });
  });

  group('non-transient statuses', () {
    for (final status in [500, 400]) {
      test('$status -> failed', () async {
        stubSubmitThrows(_http(status));
        final cmd = await drainSingleSubmitLine();
        expect(cmd.status, OutboxCommandStatus.failed);
        expect(container.read(syncManagerProvider).mode,
            SyncConnectivityMode.online);
      });
    }

    test('409 -> conflict', () async {
      stubSubmitThrows(_http(409));
      final cmd = await drainSingleSubmitLine();
      expect(cmd.status, OutboxCommandStatus.conflict);
    });
  });

  test('FAILED line with blocked pending completion ends online, not offline',
      () async {
    stubSubmitThrows(_http(400));
    await cache.saveOutboxCommands([
      _cmd('line_10_1', OutboxCommandType.submitLine, 10, {'line_id': 1}),
      _cmd('complete_10', OutboxCommandType.completeRecord, 10,
          {'technician_name': 'T', 'remarks': 'R'}),
    ]);

    await manager.drainOutbox();

    final state = container.read(syncManagerProvider);
    expect(state.mode, SyncConnectivityMode.online);
    expect(state.pendingCount, 1);
    expect(state.attentionCount, 1);
  });

  test('session epoch bump mid-drain does not leave mode syncing', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    when(() => api.submitLine(
          10,
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).thenAnswer((_) async {
      started.complete();
      await release.future;
    });
    await cache.saveOutboxCommands([
      _cmd('line_10_1', OutboxCommandType.submitLine, 10, {'line_id': 1}),
      _cmd('line_10_2', OutboxCommandType.submitLine, 10, {'line_id': 2}),
    ]);

    final drain = manager.drainOutbox();
    await started.future;
    expect(container.read(syncManagerProvider).mode,
        SyncConnectivityMode.syncing);
    manager.invalidateSessionBoundWork();
    release.complete();
    await drain;

    expect(container.read(syncManagerProvider).mode,
        isNot(SyncConnectivityMode.syncing));
  });

  test('evidence sweep excludes files queued by another owner', () async {
    const otherPath = 'other_user_photo.jpg';
    await cache.setCacheOwnerUserId(1);
    await cache.saveOutboxCommands([
      _cmd('mine', OutboxCommandType.submitLine, 10, {'line_id': 1},
          ownerUserId: 1),
      _cmd('theirs', OutboxCommandType.uploadLineAttachment, 20,
          {'line_id': 1, 'file_path': otherPath, 'kind': 'BEFORE'},
          ownerUserId: 2),
    ]);
    when(() => api.submitLine(
          10,
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).thenAnswer((_) async {});
    Set<String>? captured;
    when(() => evidence.cleanupExpiredEvidence(
        excludePaths: any(named: 'excludePaths'))).thenAnswer((inv) async {
      captured = inv.namedArguments[#excludePaths] as Set<String>?;
    });

    await manager.drainOutbox();

    expect(captured, isNotNull);
    expect(captured, contains(File(otherPath).absolute.path));
  });
}
