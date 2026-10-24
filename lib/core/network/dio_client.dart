import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/config/app_config.dart';
import 'package:gssms_mobile/core/network/auth_interceptor.dart';
import 'package:gssms_mobile/core/network/certificate_pinning.dart';
import 'package:gssms_mobile/core/network/encoded_upload_interceptor.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';

final authenticatedDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final authRepo = ref.watch(authRepositoryProvider);

  return DioClient.create(
    config: config,
    tokenProvider: () => authRepo.currentAccessToken,
    refreshTokenHandler: () => authRepo.refreshToken(),
    onSessionExpired: () async {
      var cleared = true;
      try {
        await authRepo.expireSession();
      } catch (_) {
        cleared = false;
      }
      await ref
          .read(authControllerProvider.notifier)
          .handleSessionExpired(null, cleared);
    },
    offlineOnly: () => authRepo.currentSession?.isOffline == true,
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
    bool Function()? offlineOnly,
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

    // Optional SPKI pinning, enabled only when GSSMS_SPKI_PINS is supplied at
    // build time. Installed before interceptors are attached so the auth
    // retry client (which copies this adapter) is pinned as well.
    if (config.spkiPins.isNotEmpty) {
      dio.httpClientAdapter = buildPinnedAdapter(config.spkiPins.toSet());
    }

    if (offlineOnly != null) {
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (offlineOnly()) {
          return handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
              error:
                  'Offline access: reconnect before using online operations.'));
        }
        handler.next(options);
      }));
    }
    dio.interceptors.add(EncodedUploadInterceptor());
    dio.interceptors.add(
      AuthInterceptor(
        dio: dio,
        tokenProvider: tokenProvider,
        refreshTokenHandler: refreshTokenHandler,
        onSessionExpired: onSessionExpired,
      ),
    );

    // HTTPS-only guard for the prod flavour (§15.1).
    // This is TLS enforcement only: prod never falls back to plain HTTP.
    // SPKI pinning is optional and active only when GSSMS_SPKI_PINS is
    // supplied (see above); without pins, trust is the system CA store.
    if (config.environment.enableCertPinning) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final uri = options.uri;
            if (uri.scheme != 'https') {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  error: 'HTTPS required in prod',
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
