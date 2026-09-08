import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/complaints/data/complaint_api_service.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';

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
  group('ComplaintApiService REST Contract Tests', () {
    late Dio dio;
    late ComplaintApiService apiService;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      apiService = ComplaintApiService(dio);
    });

    test('getComplaints calls GET /api/v1/complaints/ with query filters', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/complaints/');
        expect(options.queryParameters['status'], 'OPEN');
        expect(options.queryParameters['start_date'], '2026-09-01');
        expect(options.queryParameters['end_date'], '2026-09-07');
        return _json([
          {
            'id': 10,
            'title': 'Test Issue',
            'status': 'OPEN',
            'severity': 'MEDIUM',
          }
        ], 200);
      });

      final complaints = await apiService.getComplaints(
        status: 'OPEN',
        dateFrom: '2026-09-01',
        dateTo: '2026-09-07',
      );
      expect(complaints.length, 1);
      expect(complaints[0].id, 10);
      expect(complaints[0].status, ComplaintStatus.open);
    });

    test('createComplaint calls POST /api/v1/complaints/ and returns created record', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/complaints/');
        expect(options.method, 'POST');
        final data = options.data as Map<String, dynamic>;
        expect(data['title'], 'New Failure');

        return _json({
          'id': 11,
          'title': 'New Failure',
          'status': 'OPEN',
          'severity': 'HIGH',
        }, 201);
      });

      final created = await apiService.createComplaint({
        'title': 'New Failure',
        'description': 'Description',
        'department': 'ELECTRICAL',
      });

      expect(created.id, 11);
      expect(created.title, 'New Failure');
    });
  });
}
