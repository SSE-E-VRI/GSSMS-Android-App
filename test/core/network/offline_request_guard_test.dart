import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/config/app_config.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:mocktail/mocktail.dart';

class _Adapter extends Mock implements HttpClientAdapter {}

void main() {
  test('restricted offline session sends no authenticated API request',
      () async {
    var expired = false;
    var refreshed = false;
    final client = DioClient.create(
      config: const AppConfig(
          baseUrl: 'http://127.0.0.1:8765', environment: AppEnvironment.dev),
      tokenProvider: () => null,
      refreshTokenHandler: () async {
        refreshed = true;
        return null;
      },
      onSessionExpired: () async {
        expired = true;
      },
      offlineOnly: () => true,
    );
    final adapter = _Adapter();
    client.httpClientAdapter = adapter;
    await expectLater(
        client.post<void>('/api/v1/maintenance/work-orders/1/change-status/',
            data: {'status': 'CLOSED'}),
        throwsA(isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)));
    verifyZeroInteractions(adapter);
    expect(refreshed, isFalse);
    expect(expired, isFalse);
    client.close();
  });
}
