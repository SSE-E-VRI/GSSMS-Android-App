import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:mocktail/mocktail.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

MaintenanceRecordLine _line({required List<LineAttachment> attachments}) {
  return MaintenanceRecordLine(
    id: 5,
    itemName: 'Bushing',
    assetCategory: 'Substation',
    attachments: attachments,
  );
}

MaintenanceRecord _record({required List<LineAttachment> attachments}) {
  return MaintenanceRecord(
    id: 10,
    workOrderId: 11,
    lines: [_line(attachments: attachments)],
  );
}

OutboxCommand _attachCmd({
  required String key,
  OutboxCommandStatus status = OutboxCommandStatus.pending,
  String? lastError,
}) {
  return OutboxCommand(
    idempotencyKey: key,
    type: OutboxCommandType.uploadLineAttachment,
    entityId: 10,
    payload: const {
      'line_id': 5,
      'kind': 'BEFORE',
      'file_path': '/tmp/before_1.jpg',
    },
    createdAt: DateTime.now(),
    status: status,
    lastError: lastError,
  );
}

void main() {
  late ILocalCacheService cacheService;
  late MockWorkOrderRepository mockRepo;
  late ProviderContainer container;

  const serverAttachment = LineAttachment(
    id: 55,
    kind: 'BEFORE',
    url: 'https://example.com/before_55.jpg',
    syncStatus: OutboxCommandStatus.synced,
  );
  const placeholder = LineAttachment(
    id: -1,
    kind: 'BEFORE',
    localPath: '/tmp/before_1.jpg',
    syncStatus: OutboxCommandStatus.pending,
    idempotencyKey: 'key_reconcile_1',
  );

  setUp(() {
    cacheService = InMemoryLocalCacheService();
    mockRepo = MockWorkOrderRepository();
    container = ProviderContainer(
      overrides: [
        localCacheServiceProvider.overrideWithValue(cacheService),
        workOrderRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('uploaded placeholder is replaced by the server row once its command leaves the outbox',
      () async {
    when(() => mockRepo.fetchMaintenanceRecord(10))
        .thenAnswer((_) async => _record(attachments: [serverAttachment]));

    container
        .read(checklistControllerProvider(10).notifier)
        .state = ChecklistLoaded(
      record: _record(attachments: [serverAttachment, placeholder]),
    );
    await cacheService.saveOutboxCommands(const []);

    await container
        .read(checklistControllerProvider(10).notifier)
        .reconcileAttachmentSyncState();

    final state = container.read(checklistControllerProvider(10));
    expect(state, isA<ChecklistLoaded>());
    final atts = (state as ChecklistLoaded).record.lines.single.attachments;
    expect(atts.map((a) => a.id), [55]);
  });

  test('failed command surfaces persistent error on the placeholder instead of only a SnackBar',
      () async {
    when(() => mockRepo.fetchMaintenanceRecord(10))
        .thenAnswer((_) async => _record(attachments: const []));

    container
        .read(checklistControllerProvider(10).notifier)
        .state = ChecklistLoaded(record: _record(attachments: [placeholder]));
    await cacheService.saveOutboxCommands([
      _attachCmd(
        key: 'key_reconcile_1',
        status: OutboxCommandStatus.failed,
        lastError: 'Failed (400): Only JPEG images are allowed.',
      ),
    ]);

    await container
        .read(checklistControllerProvider(10).notifier)
        .reconcileAttachmentSyncState();

    final state = container.read(checklistControllerProvider(10));
    expect(state, isA<ChecklistLoaded>());
    final atts = (state as ChecklistLoaded).record.lines.single.attachments;
    expect(atts.length, 1);
    expect(atts.single.syncStatus, OutboxCommandStatus.failed);
    expect(atts.single.syncError, contains('Only JPEG'));
  });
}
