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

        return _json([
          {
            'id': 101,
            'status': 'ASSIGNED',
            'type': 'PREVENTIVE',
            'title': 'Test WO',
          }
        ], 200);
      });

      final orders = await apiService.getWorkOrders(status: 'ASSIGNED', type: 'PREVENTIVE');
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
