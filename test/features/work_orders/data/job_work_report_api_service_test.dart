import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/data/job_work_report_api_service.dart';

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

ResponseBody _json(dynamic data, [int statusCode = 200]) =>
    ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );

void main() {
  late Dio dio;
  late JobWorkReportApiService api;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
    api = JobWorkReportApiService(dio);
  });

  group('fetchChecklistRecord', () {
    test('uses work_order and takes the first result', () async {
      final calls = <RequestOptions>[];
      dio.httpClientAdapter = MockAdapter((o) async {
        calls.add(o);
        return _json({
          'results': [
            {'id': 7},
            {'id': 8},
          ]
        });
      });
      final rec = await api.fetchChecklistRecord(101, scheduleId: 5);
      expect(rec!['id'], 7);
      expect(calls, hasLength(1));
      expect(calls.single.path, '/api/v1/maintenance/records/');
      expect(calls.single.queryParameters, {'work_order': 101});
    });

    test('falls back to schedule on an empty result (bare list)', () async {
      final calls = <RequestOptions>[];
      dio.httpClientAdapter = MockAdapter((o) async {
        calls.add(o);
        return o.queryParameters.containsKey('schedule')
            ? _json([
                {'id': 9}
              ])
            : _json([]);
      });
      final rec = await api.fetchChecklistRecord(101, scheduleId: 5);
      expect(rec!['id'], 9);
      expect(calls, hasLength(2));
      expect(calls[1].queryParameters, {'schedule': 5});
    });

    test('returns null when both are empty or no schedule', () async {
      var n = 0;
      dio.httpClientAdapter = MockAdapter((o) async {
        n++;
        return _json({'results': []});
      });
      expect(await api.fetchChecklistRecord(101, scheduleId: 5), isNull);
      expect(n, 2);
      n = 0;
      expect(await api.fetchChecklistRecord(101), isNull);
      expect(n, 1);
    });

    test('non-list payload throws', () async {
      dio.httpClientAdapter = MockAdapter((o) async => _json('nope'));
      expect(api.fetchChecklistRecord(1), throwsA(isA<DioException>()));
    });
  });

  test('execution / work order endpoints', () async {
    final paths = <String>[];
    dio.httpClientAdapter = MockAdapter((o) async {
      expect(o.method, 'GET');
      paths.add(o.path);
      return _json({'id': 1});
    });
    await api.fetchWorkOrder(10);
    await api.fetchComplaintExecution(10);
    await api.fetchInspectionExecution(10);
    await api.fetchRectification(10);
    expect(paths, [
      '/api/v1/maintenance/work-orders/10/',
      '/api/v1/staff-workorders/10/complaint-execution/',
      '/api/v1/staff-workorders/10/inspection-execution/',
      '/api/v1/staff-workorders/10/rectification/',
    ]);
  });

  test('bad object payload throws DioException', () async {
    dio.httpClientAdapter = MockAdapter((o) async => _json([1, 2]));
    expect(api.fetchRectification(1), throwsA(isA<DioException>()));
  });

  group('photos', () {
    test('mediaFetchUrl rewrite', () {
      expect(
          JobWorkReportApiService.mediaFetchUrl(
              'http://internal:8000/media/x.jpg?a=1'),
          '/media/x.jpg?a=1');
      expect(
          JobWorkReportApiService.mediaFetchUrl(
              'http://internal:8000/media/x.jpg'),
          '/media/x.jpg');
      expect(JobWorkReportApiService.mediaFetchUrl('/media/y.jpg'),
          '/media/y.jpg');
      expect(
          JobWorkReportApiService.mediaFetchUrl('https://cdn.example/a.jpg'),
          'https://cdn.example/a.jpg');
    });

    test('fetchPhotoBytes rewrites the URL and requests bytes', () async {
      RequestOptions? seen;
      dio.httpClientAdapter = MockAdapter((o) async {
        seen = o;
        return ResponseBody.fromBytes([1, 2, 3], 200, headers: {
          Headers.contentTypeHeader: ['image/jpeg']
        });
      });
      final bytes =
          await api.fetchPhotoBytes('http://internal:8000/media/x.jpg?a=1');
      expect(bytes, [1, 2, 3]);
      expect(seen!.path, '/media/x.jpg?a=1');
      expect(seen!.responseType, ResponseType.bytes);
      // `image/*` alone is answered 406 by the server's DRF media view, which
      // left every report photo blank; the header must also accept `*/*`.
      expect(seen!.headers['Accept'], JobWorkReportApiService.photoAccept);
      expect(seen!.headers['Accept'], contains('*/*'));
    });
  });
}
