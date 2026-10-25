import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/pending_execution_photo_store.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApi extends Mock implements WorkOrderApiService {}

class _MockEvidence extends Mock implements EvidenceService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = PendingExecutionPhotoStore();
  late Directory dir;

  String photo(String name) {
    final file = File('${dir.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    return file.path;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pending_store_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('each user sees only their own pending photos for a Job Work', () async {
    final mine = photo('mine.jpg');
    final theirs = photo('theirs.jpg');
    await store.save(7, [PendingExecutionPhoto(kind: 'BEFORE', localPath: theirs)],
        ownerUserId: 2);
    await store.save(7, [PendingExecutionPhoto(kind: 'AFTER', localPath: mine)],
        ownerUserId: 1);

    final forOne = await store.load(7, ownerUserId: 1);
    final forTwo = await store.load(7, ownerUserId: 2);

    expect(forOne.map((p) => p.localPath), [mine]);
    expect(forTwo.map((p) => p.localPath), [theirs]);
  });

  test('saving keeps another user\'s photos and clearing removes only mine',
      () async {
    final theirs = photo('theirs.jpg');
    await store.save(7, [PendingExecutionPhoto(kind: 'BEFORE', localPath: theirs)],
        ownerUserId: 2);
    await store.save(7, [PendingExecutionPhoto(kind: 'BEFORE', localPath: photo('a.jpg'))],
        ownerUserId: 1);

    await store.save(7, const [], ownerUserId: 1);

    expect(await store.load(7, ownerUserId: 1), isEmpty);
    expect((await store.load(7, ownerUserId: 2)).single.localPath, theirs);
  });

  test('legacy ownerless photos are quarantined and retained', () async {
    final legacy = photo('legacy.jpg');
    SharedPreferences.setMockInitialValues({
      PendingExecutionPhotoStore.keyFor(7): jsonEncode([
        {'kind': 'BEFORE', 'localPath': legacy},
      ]),
    });

    expect(await store.load(7, ownerUserId: 5), isEmpty);
    expect(await store.load(7, ownerUserId: 6), isEmpty);
    await store.save(7, const [], ownerUserId: 5);
    expect(await PendingExecutionPhotoStore.allReferencedPaths(),
        contains(File(legacy).absolute.path));
    expect(File(legacy).existsSync(), isTrue);
  });

  test('photos whose file is gone are dropped on load', () async {
    await store.save(
        7, const [PendingExecutionPhoto(kind: 'BEFORE', localPath: '/gone.jpg')],
        ownerUserId: 1);

    expect(await store.load(7, ownerUserId: 1), isEmpty);
  });

  test('allReferencedPaths covers every Job Work and every user', () async {
    final a = photo('a.jpg');
    final b = photo('b.jpg');
    await store.save(7, [PendingExecutionPhoto(kind: 'BEFORE', localPath: a)],
        ownerUserId: 1);
    await store.save(9, [PendingExecutionPhoto(kind: 'AFTER', localPath: b)],
        ownerUserId: 2);

    expect(await PendingExecutionPhotoStore.allReferencedPaths(), {a, b});
  });

  test('the outbox retention sweep never deletes pending Breakdown photos',
      () async {
    final pending = photo('pending.jpg');
    await store.save(7, [PendingExecutionPhoto(kind: 'BEFORE', localPath: pending)],
        ownerUserId: 1);

    final api = _MockApi();
    final evidence = _MockEvidence();
    Set<String>? excluded;
    when(() => evidence.cleanupExpiredEvidence(
        excludePaths: any(named: 'excludePaths'))).thenAnswer((inv) async {
      excluded = inv.namedArguments[#excludePaths] as Set<String>?;
    });
    when(() => api.submitLine(10, any(),
        idempotencyKey: any(named: 'idempotencyKey'))).thenAnswer((_) async {});
    final cache = InMemoryLocalCacheService();
    await cache.saveOutboxCommands([
      OutboxCommand(
        idempotencyKey: 'line_10_1',
        type: OutboxCommandType.submitLine,
        entityId: 10,
        payload: const {'line_id': 1},
        createdAt: DateTime.now(),
      ),
    ]);
    final container = ProviderContainer(overrides: [
      localCacheServiceProvider.overrideWithValue(cache),
      workOrderApiServiceProvider.overrideWithValue(api),
      evidenceServiceProvider.overrideWithValue(evidence),
    ]);
    addTearDown(container.dispose);

    await container.read(syncManagerProvider.notifier).drainOutbox();

    expect(excluded, contains(File(pending).absolute.path));
  });
}
