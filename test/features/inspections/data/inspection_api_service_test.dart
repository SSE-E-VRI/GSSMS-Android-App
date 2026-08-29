import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/inspections/data/inspection_api_service.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';

class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) => handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(dynamic data, int statusCode) => ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );

void main() {
  group('InspectionApiService REST Contract Tests', () {
    late Dio dio;
    late InspectionApiService apiService;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      apiService = InspectionApiService(dio);
    });

    test('getInspections calls GET /api/v1/inspections/ with filters', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/inspections/');
        expect(options.queryParameters['status'], 'PENDING');
        return _json([
          {'id': 10, 'title': 'Monthly Check', 'status': 'PENDING', 'priority': 'MEDIUM'}
        ], 200);
      });

      final inspections = await apiService.getInspections(status: 'PENDING');
      expect(inspections.length, 1);
      expect(inspections[0].id, 10);
      expect(inspections[0].status, InspectionStatus.pending);
    });

    test('getInspections handles paginated results envelope', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        return _json({
          'results': [
            {'id': 11, 'title': 'Paginated', 'status': 'COMPLETED'}
          ]
        }, 200);
      });

      final inspections = await apiService.getInspections();
      expect(inspections.length, 1);
      expect(inspections[0].id, 11);
    });

    test('createInspection calls POST /api/v1/inspections/', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/inspections/');
        expect(options.method, 'POST');
        final data = options.data as Map<String, dynamic>;
        expect(data['title'], 'New Inspection');
        return _json({'id': 12, 'title': 'New Inspection', 'status': 'PENDING', 'priority': 'HIGH'}, 201);
      });

      final created = await apiService.createInspection({'title': 'New Inspection', 'description': 'Desc', 'priority': 'HIGH'});
      expect(created.id, 12);
      expect(created.title, 'New Inspection');
    });

    test('convertToWorkOrder calls POST /api/v1/inspections/{id}/convert_to_work_order/', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/inspections/10/convert_to_work_order/');
        expect(options.method, 'POST');
        return _json({'work_order_id': 99}, 201);
      });

      final result = await apiService.convertToWorkOrder(10);
      expect(result['work_order_id'], 99);
    });
  });
}
