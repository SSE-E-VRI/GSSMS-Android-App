import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/network/auth_interceptor.dart';

/// Adapter that records the body actually transmitted for each request.
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String?> sentBodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream == null) {
      sentBodies.add(null);
    } else {
      final bytes = await requestStream.fold<List<int>>(
        <int>[],
        (prev, element) => prev..addAll(element),
      );
      sentBodies.add(utf8.decode(bytes));
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(dynamic data, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  group('AuthInterceptor retry payload', () {
    test('replays the request body when retrying a POST after refresh', () async {
      String? currentToken = 'old_token';

      final dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      final adapter = RecordingAdapter((options) {
        if (options.headers['Authorization'] == 'Bearer new_token') {
          return _jsonResponse({'id': 7, 'status': 'IN_PROGRESS'}, 200);
        }
        return _jsonResponse({'detail': 'Token expired'}, 401);
      });
      dio.httpClientAdapter = adapter;

      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          tokenProvider: () => currentToken,
          refreshTokenHandler: () async {
            currentToken = 'new_token';
            return currentToken;
          },
          onSessionExpired: () async {},
        ),
      );

      const payload = {'status': 'IN_PROGRESS', 'remarks': 'Started on site'};
      final response = await dio.post(
        '/api/v1/work-orders/7/change-status/',
        data: payload,
      );

      expect(response.statusCode, 200);
      expect(adapter.sentBodies.length, 2);
      expect(
        adapter.sentBodies[1],
        jsonEncode(payload),
        reason: 'the retried request must carry the original body, not an empty one',
      );
    });

    test('surfaces a non-401 failure from the retried request', () async {
      String? currentToken = 'old_token';
      var sessionExpiredCount = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      dio.httpClientAdapter = RecordingAdapter((options) {
        if (options.headers['Authorization'] == 'Bearer new_token') {
          return _jsonResponse({'detail': 'Invalid transition'}, 400);
        }
        return _jsonResponse({'detail': 'Token expired'}, 401);
      });

      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          tokenProvider: () => currentToken,
          refreshTokenHandler: () async {
            currentToken = 'new_token';
            return currentToken;
          },
          onSessionExpired: () async => sessionExpiredCount++,
        ),
      );

      await expectLater(
        dio.post('/api/v1/work-orders/7/change-status/', data: const {'status': 'CLOSED'}),
        throwsA(
          isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 400),
        ),
      );
      expect(sessionExpiredCount, 0, reason: 'a 400 is not an expired session');
    });
  });
}
