import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/sync/mutation_outcome.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';

class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(dynamic data, int status) => ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

void main() {
  group('Work order API contract', () {
    late Dio dio;
    late WorkOrderApiService api;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      api = WorkOrderApiService(dio);
    });

    test('allowed-actions is read from the path Django registers', () async {
      // Payload copied from a live allowed-actions response.
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(
          options.path,
          '/api/v1/maintenance/work-orders/20/allowed-actions/',
        );
        return _json({
          'work_order': 20,
          'current_status': 'IN_PROGRESS',
          'allowed_actions': [
            {
              'target_status': 'TECH_COMPLETED',
              'label': 'Tech Completed',
              'enabled': true,
              'disabled_reason': null,
              'requires_reason': false,
              'guard_status': 'available',
              'requirements': {'remarks': false, 'failure_code': true},
            },
          ],
          'blocked_actions': [
            {
              'target_status': 'ON_HOLD',
              'label': 'On Hold',
              'enabled': false,
              'disabled_reason': 'Not authorized or conditions not met',
              'requires_reason': true,
              'guard_status': 'blocked',
              'requirements': {'remarks': true, 'failure_code': false},
            },
          ],
        }, 200);
      });

      final actions = await api.getAllowedActions(20);

      expect(actions.currentStatus, 'IN_PROGRESS');
      expect(actions.allowed.single.targetStatus, 'TECH_COMPLETED');
      expect(actions.allowed.single.requiresFailureCode, isTrue);
      expect(actions.blocked.single.targetStatus, 'ON_HOLD');
      expect(actions.blocked.single.requiresReason, isTrue);
    });

    test('audit history is parsed and ordered newest first', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/work-orders/20/audit/');
        return _json({
          'work_order_id': 20,
          'ticket_number': 'TLNR-202608-0015',
          'current_status': 'IN_PROGRESS',
          'return_count': 0,
          'events': [
            {
              'event_id': 'a',
              'event_type': 'STATUS_CHANGE',
              'from_state': 'NEW',
              'to_state': 'ASSIGNED',
              'actor': 'vri',
              'actor_role': 'DEPOT_INCHARGE',
              'reason': null,
              'timestamp': '2026-08-09T07:01:50.769974+05:30',
            },
            {
              'event_id': 'b',
              'event_type': 'STATUS_CHANGE',
              'from_state': 'ASSIGNED',
              'to_state': 'IN_PROGRESS',
              'actor': 'krishna',
              'actor_role': 'MAINTENANCE_STAFF',
              'reason': 'Execution started',
              'timestamp': '2026-08-09T09:18:35.700709+05:30',
            },
          ],
        }, 200);
      });

      final audit = await api.getAudit(20);

      expect(audit.ticketNumber, 'TLNR-202608-0015');
      expect(audit.events.length, 2);
      expect(audit.eventsNewestFirst.first.eventId, 'b');
      expect(audit.eventsNewestFirst.first.reason, 'Execution started');
    });

    test('staff-scoped list uses start_date/end_date (SSOT §20 FIX-007)', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/staff-workorders/');
        expect(options.queryParameters['start_date'], '2026-09-01');
        expect(options.queryParameters['end_date'], '2026-09-07');
        expect(options.queryParameters.containsKey('date_from'), isFalse);
        expect(options.queryParameters.containsKey('date_to'), isFalse);
        return _json([], 200);
      });

      await api.getWorkOrders(
        dateFrom: '2026-09-01',
        dateTo: '2026-09-07',
        assignedToMe: true,
      );
    });

    test('main register list keeps date_from/date_to', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/work-orders/');
        expect(options.queryParameters['date_from'], '2026-09-01');
        expect(options.queryParameters['date_to'], '2026-09-07');
        expect(options.queryParameters.containsKey('start_date'), isFalse);
        expect(options.queryParameters.containsKey('end_date'), isFalse);
        return _json([], 200);
      });

      await api.getWorkOrders(
        dateFrom: '2026-09-01',
        dateTo: '2026-09-07',
      );
    });
  });

  group('Checklist line submission payload', () {
    late MockWorkOrderRepository mockRepo;
    late ProviderContainer container;

    const record = MaintenanceRecord(
      id: 22,
      lines: [
        MaintenanceRecordLine(
          id: 1541,
          itemName: 'EB Bunk',
          valueType: MaintenanceValueType.status,
          statusOptionId: 2071,
          actionOptionId: 4204,
          statusOptions: [
            MaintenanceStatusOption(
              id: 2071,
              label: 'Dirty',
              actionOptions: [MaintenanceActionOption(id: 4204, label: 'Cleaned')],
            ),
            MaintenanceStatusOption(
              id: 2072,
              label: 'Clean',
              actionOptions: [
                MaintenanceActionOption(id: 4206, label: 'No Action Required'),
              ],
            ),
          ],
        ),
      ],
    );

    setUp(() {
      mockRepo = MockWorkOrderRepository();
      when(() => mockRepo.fetchMaintenanceRecord(22))
          .thenAnswer((_) async => record);
      when(() => mockRepo.submitChecklistLine(any(), any()))
          .thenAnswer((_) async => MutationOutcome.synced);
      container = ProviderContainer(
        overrides: [workOrderRepositoryProvider.overrideWithValue(mockRepo)],
      );
    });

    tearDown(() => container.dispose());

    Future<Map<String, dynamic>> submit({
      Object? value,
      int? statusOptionId,
      int? actionOptionId,
    }) async {
      final controller = container.read(checklistControllerProvider(22).notifier);
      await controller.loadRecord();
      await controller.submitLineObservation(
        lineId: 1541,
        value: value,
        statusOptionId: statusOptionId,
        actionOptionId: actionOptionId,
      );
      return verify(() => mockRepo.submitChecklistLine(22, captureAny()))
          .captured
          .last as Map<String, dynamic>;
    }

    test('always sends every field the server assigns unconditionally', () async {
      final payload = await submit(value: '230', statusOptionId: 2071, actionOptionId: 4204);

      // The backend writes recorded_value, status_option and action_option from
      // the request on every call, so a key left out silently wipes that column.
      for (final key in ['line_id', 'value', 'status', 'status_option', 'action_option', 'remarks']) {
        expect(payload.containsKey(key), isTrue, reason: '$key must always be sent');
      }
      expect(payload['line_id'], 1541);
      expect(payload['value'], '230');
      expect(payload['status_option'], 2071);
      expect(payload['action_option'], 4204);
    });

    test('drops an action that does not belong to the chosen status', () async {
      // 4206 belongs to status 2072; the server rejects it against 2071 with
      // "This action is not available for the selected status."
      final payload = await submit(statusOptionId: 2071, actionOptionId: 4206);

      expect(payload['status_option'], 2071);
      expect(
        payload['action_option'],
        isNull,
        reason: 'a mismatched action must never reach the server',
      );
    });

    test('sends three-phase readings as component maps', () async {
      final payload = await submit(
        value: const {'R': '240', 'Y': '238', 'B': '241'},
        statusOptionId: 2071,
        actionOptionId: 4204,
      );

      expect(payload['value'], {'R': '240', 'Y': '238', 'B': '241'});
    });
  });
}
