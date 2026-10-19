import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/data/execution_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';

class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<List<int>>? requestStream, Future<void>? cancelFuture) =>
      handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(dynamic data, int statusCode) => ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );

void main() {
  group('ExecutionApiService REST Contract Tests', () {
    late Dio dio;
    late ExecutionApiService api;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      api = ExecutionApiService(dio);
    });

    test('get/save complaint execution hit complaint-execution/', () async {
      var calls = 0;
      dio.httpClientAdapter = MockAdapter((options) async {
        calls++;
        if (options.method == 'GET') {
          expect(options.path,
              '/api/v1/staff-workorders/10/complaint-execution/');
          return _json({'id': 1, 'photos': []}, 200);
        }
        expect(options.method, 'PATCH');
        return _json({'id': 1, 'initial_findings': 'x', 'photos': []}, 200);
      });

      final got = await api.getComplaintExecution(10);
      expect(got, isA<ComplaintExecution>());
      final saved = await api.saveComplaintDraft(10, {'initial_findings': 'x'});
      expect(saved.initialFindings, 'x');
      expect(calls, 2);
    });

    test('submit complaint execution posts to submit/', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path,
            '/api/v1/staff-workorders/10/complaint-execution/submit/');
        expect(options.method, 'POST');
        return _json({'id': 1, 'photos': []}, 200);
      });

      final result = await api.submitComplaintExecution(10, {
        'remarks': 'Done well done',
        'technician_signature': 'SIGNED_DIGITALLY',
      });
      expect(result.id, 1);
    });

    test('rectification get/submit hit rectification endpoints', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        if (options.path.endsWith('rectification/')) {
          return _json({'items': [], 'editable': true}, 200);
        }
        expect(options.path.endsWith('rectification/submit/'), isTrue);
        return _json({'items': [], 'editable': false}, 200);
      });

      final payload = await api.getRectification(20);
      expect(payload.items, isEmpty);
      final submitted = await api.submitRectification(20, {
        'remarks': 'All good here',
        'technician_signature': 'SIGNED_DIGITALLY',
      });
      expect(submitted.editable, isFalse);
    });

    test('inspection initialize/save/submit hit inspection-execution/', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        if (options.path.endsWith('initialize/')) {
          expect(options.method, 'POST');
          return _json({'points': [], 'is_pointwise': true}, 200);
        }
        if (options.method == 'PATCH') {
          return _json({'points': []}, 200);
        }
        expect(options.path.endsWith('inspection-execution/submit/'), isTrue);
        return _json({'points': []}, 200);
      });

      final init = await api.initializeInspectionExecution(30);
      expect(init.points, isEmpty);
      final saved = await api.saveInspectionDraft(30, {
        'point_executions': [],
        'points': [],
      });
      expect(saved, isA<PointwiseInspectionExecution>());
      final submitted = await api.submitInspectionExecution(30, {
        'is_pointwise': true,
        'point_executions': [],
        'points': [],
      });
      expect(submitted.points, isEmpty);
    });

    test('photo deletes hit nested delete routes', () async {
      final paths = <String>[];
      dio.httpClientAdapter = MockAdapter((options) async {
        paths.add('${options.method} ${options.path}');
        return _json(null, 204);
      });

      await api.deleteComplaintPhoto(10, 1);
      await api.deleteRectificationPhoto(20, 31, 2);
      await api.deleteInspectionPhoto(30, 3);
      expect(paths, [
        'DELETE /api/v1/staff-workorders/10/complaint-execution/photos/1/',
        'DELETE /api/v1/staff-workorders/20/rectification/items/31/photos/2/',
        'DELETE /api/v1/staff-workorders/30/inspection-execution/photos/3/',
      ]);
    });
  });
}
