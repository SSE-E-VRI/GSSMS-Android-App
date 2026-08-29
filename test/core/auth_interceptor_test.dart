import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/network/auth_interceptor.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  MockHttpClientAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(dynamic data, int statusCode) {
  final jsonString = jsonEncode(data);
  return ResponseBody.fromString(
    jsonString,
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  group('AuthInterceptor Wire & Adapter Tests', () {
    test('intercepts 401, refreshes token once, and successfully retries request', () async {
      int requestCount = 0;
      int refreshCount = 0;
      String? currentToken = 'old_token';

      final dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        requestCount++;
        if (options.headers['Authorization'] == 'Bearer new_token') {
          return _jsonResponse({'status': 'ok'}, 200);
        }
        return _jsonResponse({'detail': 'Token expired'}, 401);
      });

      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          tokenProvider: () => currentToken,
          refreshTokenHandler: () async {
            refreshCount++;
            currentToken = 'new_token';
            return currentToken;
          },
          onSessionExpired: () async {},
        ),
      );

      final response = await dio.get('/api/v1/work-orders/');
      expect(response.statusCode, 200);
      expect(response.data, {'status': 'ok'});
      expect(refreshCount, 1);
      expect(requestCount, 2); // Initial 401 + retry 200
    });

    test('retries only once on second 401 and calls onSessionExpired without loop', () async {
      int requestCount = 0;
      int refreshCount = 0;
      int sessionExpiredCount = 0;
      String? currentToken = 'old_token';

      final dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        requestCount++;
        // Always return 401
        return _jsonResponse({'detail': 'Still unauthorized'}, 401);
      });

      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          tokenProvider: () => currentToken,
          refreshTokenHandler: () async {
            refreshCount++;
            return 'still_invalid_token';
          },
          onSessionExpired: () async {
            sessionExpiredCount++;
          },
        ),
      );

      try {
        await dio.get('/api/v1/work-orders/');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 401);
      }

      expect(refreshCount, 1);
      expect(requestCount, 2); // Initial 401 + 1 retry 401 -> terminates
      expect(sessionExpiredCount, 1);
    });

    test('does not attempt token refresh for auth endpoints on 401', () async {
      int refreshCount = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        return _jsonResponse({'detail': 'Invalid refresh token'}, 401);
      });

      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          tokenProvider: () => null,
          refreshTokenHandler: () async {
            refreshCount++;
            return 'new_token';
          },
          onSessionExpired: () async {},
        ),
      );

      try {
        await dio.post('/api/v1/auth/refresh/', data: {'refresh': 'bad_token'});
      } on DioException catch (e) {
        expect(e.response?.statusCode, 401);
      }

      expect(refreshCount, 0);
    });

    test('coalesces multiple concurrent 401 requests to a single refresh call', () async {
      int refreshCount = 0;
      String? currentToken = 'stale_token';

      final dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        if (options.headers['Authorization'] == 'Bearer coalesced_token') {
          return _jsonResponse({'data': 'success for ${options.path}'}, 200);
        }
        return _jsonResponse({'detail': 'Token expired'}, 401);
      });

      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          tokenProvider: () => currentToken,
          refreshTokenHandler: () async {
            refreshCount++;
            await Future.delayed(const Duration(milliseconds: 50));
            currentToken = 'coalesced_token';
            return 'coalesced_token';
          },
          onSessionExpired: () async {},
        ),
      );

      final future1 = dio.get('/api/v1/work-orders/1');
      final future2 = dio.get('/api/v1/work-orders/2');

      final responses = await Future.wait([future1, future2]);

      expect(responses[0].statusCode, 200);
      expect(responses[1].statusCode, 200);
      expect(refreshCount, 1); // Exact single refresh call shared across both
    });
  });
}
