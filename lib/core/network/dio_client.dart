import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/config/app_config.dart';
import 'package:gssms_mobile/core/network/auth_interceptor.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';

final authenticatedDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final authRepo = ref.watch(authRepositoryProvider);

  return DioClient.create(
    config: config,
    tokenProvider: () => authRepo.currentAccessToken,
    refreshTokenHandler: () => authRepo.refreshToken(),
    onSessionExpired: () async {
      await authRepo.logout();
      ref.read(authControllerProvider.notifier).handleSessionExpired();
    },
  );
});

/// Factory for creating configured Dio instances.
class DioClient {
  static Dio create({
    required AppConfig config,
    required TokenProvider tokenProvider,
    required RefreshTokenHandler refreshTokenHandler,
    required LogoutHandler onSessionExpired,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration receiveTimeout = const Duration(seconds: 15),
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      AuthInterceptor(
        dio: dio,
        tokenProvider: tokenProvider,
        refreshTokenHandler: refreshTokenHandler,
        onSessionExpired: onSessionExpired,
      ),
    );

    // HTTPS-only guard for prod flavour (§15.1 prep).
    // This is TLS-enforcement only — it guarantees prod never falls back to
    // plain HTTP. True SPKI certificate pinning (§15.1, §23) is still open:
    // it requires a pinned SPKI hash set + rotation runbook to defend against
    // a rogue/compromised CA, which plain HTTPS enforcement does not cover.
    if (config.environment.enableCertPinning) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final uri = options.uri;
            if (uri.scheme != 'https') {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  error: 'HTTPS required in prod (SPKI pinning not yet configured)',
                  type: DioExceptionType.badResponse,
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );
    }

    return dio;
  }
}
