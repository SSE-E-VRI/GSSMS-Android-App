import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(dynamic data, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  group('WorkOrderApiService REST Contract Tests', () {
    late Dio dio;
    late WorkOrderApiService apiService;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      apiService = WorkOrderApiService(dio);
    });

    test('getWorkOrders calls GET /api/v1/maintenance/work-orders/ with correct query params', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/work-orders/');
        expect(options.queryParameters['status'], 'ASSIGNED');
        expect(options.queryParameters['type'], 'PREVENTIVE');
        expect(options.queryParameters['date_from'], '2026-09-01');
        expect(options.queryParameters['date_to'], '2026-09-07');

        return _json([
          {
            'id': 101,
            'status': 'ASSIGNED',
            'type': 'PREVENTIVE',
            'title': 'Test WO',
          }
        ], 200);
      });

      final orders = await apiService.getWorkOrders(
        status: 'ASSIGNED',
        type: 'PREVENTIVE',
        dateFrom: '2026-09-01',
        dateTo: '2026-09-07',
      );
      expect(orders.length, 1);
      expect(orders[0].id, 101);
      expect(orders[0].status, WorkOrderStatus.assigned);
    });

    test('startExecution calls POST /api/v1/staff-workorders/{id}/execute/ and returns record_id', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/staff-workorders/101/execute/');
        expect(options.method, 'POST');
        return _json({'record_id': 55}, 200);
      });

      final recordId = await apiService.startExecution(101);
      expect(recordId, 55);
    });

    test('changeStatus calls POST /api/v1/maintenance/work-orders/{id}/change-status/', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/work-orders/101/change-status/');
        final data = options.data as Map<String, dynamic>;
        expect(data['status'], 'IN_PROGRESS');
        expect(data['remarks'], 'Starting execution');

        return _json({
          'id': 101,
          'status': 'IN_PROGRESS',
          'type': 'PREVENTIVE',
        }, 200);
      });

      final updated = await apiService.changeStatus(
        101,
        status: 'IN_PROGRESS',
        remarks: 'Starting execution',
      );
      expect(updated.status, WorkOrderStatus.inProgress);
    });

    test('assignTechnician PATCHes assigned_to on the work order', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/work-orders/101/');
        expect(options.method, 'PATCH');
        expect(options.data['assigned_to'], 4);
        return _json({
          'id': 101,
          'status': 'NEW',
          'type': 'PREVENTIVE',
          'assigned_to': 4,
          'assigned_to_name': 'tech_ramesh',
        }, 200);
      });

      final updated = await apiService.assignTechnician(101, 4);
      expect(updated.assignedToId, 4);
    });

    test('getAssignableTechnicians GETs /api/v1/users/?role=MAINTENANCE_STAFF', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/users/');
        expect(options.queryParameters['role'], 'MAINTENANCE_STAFF');
        return _json({
          'results': [
            {'id': 4, 'username': 'tech_ramesh', 'first_name': 'Ramesh'},
          ],
        }, 200);
      });

      final techs = await apiService.getAssignableTechnicians();
      expect(techs.single.id, 4);
      expect(techs.single.name, 'Ramesh');
    });

    test('verifyWorkOrder POSTs /work-orders/{id}/verify/', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/work-orders/101/verify/');
        expect(options.method, 'POST');
        expect(options.data['remarks'], 'Looks good');
        return _json({
          'id': 101,
          'status': 'VERIFIED',
          'type': 'PREVENTIVE',
          'verified_by_name': 'incharge_kumar',
        }, 200);
      });

      final updated = await apiService.verifyWorkOrder(101, remarks: 'Looks good');
      expect(updated.status, WorkOrderStatus.verified);
      expect(updated.verifiedByName, 'incharge_kumar');
    });

    test('getVerificationWorkspace GETs verification-workspace', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(
          options.path,
          '/api/v1/maintenance/work-orders/101/verification-workspace/',
        );
        return _json({
          'can_verify': true,
          'disabled_reasons': <String>[],
          'deficiencies': <dynamic>[],
          'record': {'id': 55, 'work_order': 101, 'lines': <dynamic>[]},
        }, 200);
      });

      final workspace = await apiService.getVerificationWorkspace(101);
      expect(workspace.canVerify, isTrue);
      expect(workspace.record?.id, 55);
    });

    test('submitLine calls POST /api/v1/maintenance/records/{id}/submit_line/', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/records/55/submit_line/');
        final data = options.data as Map<String, dynamic>;
        expect(data['line_id'], 12);
        expect(data['value'], '230V');

        return _json({'status': 'updated'}, 200);
      });

      await apiService.submitLine(55, {'line_id': 12, 'value': '230V'});
    });
  });
}
