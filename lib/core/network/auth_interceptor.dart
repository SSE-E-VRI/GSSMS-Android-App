import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';

typedef TokenProvider = String? Function();
typedef RefreshTokenHandler = Future<String?> Function();
typedef LogoutHandler = Future<void> Function();

/// Interceptor that:
/// 1. Attaches Bearer authorization token to outgoing API requests (except auth endpoints).
/// 2. Handles 401 responses by triggering a synchronized, coalesced token refresh and retrying the request once.
/// 3. Redacts tokens, passwords, and sensitive query keys from debug logs.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.dio,
    required this.tokenProvider,
    required this.refreshTokenHandler,
    required this.onSessionExpired,
  });

  final Dio dio;
  final TokenProvider tokenProvider;
  final RefreshTokenHandler refreshTokenHandler;
  final LogoutHandler onSessionExpired;

  static const String kRetriedKey = 'k_auth_retried';

  // Shared in-flight Future to coalesce concurrent 401 refresh requests
  Future<String?>? _inFlightRefresh;

  // Interceptor-free client used to replay a request after a token refresh.
  Dio? _cachedRetryClient;

  /// A Dio with no interceptors that shares this client's adapter and options,
  /// rebuilt if the adapter is swapped (as tests and runtime reconfiguration do).
  Dio get _retryClient {
    final cached = _cachedRetryClient;
    if (cached != null &&
        identical(cached.httpClientAdapter, dio.httpClientAdapter)) {
      return cached;
    }
    final client = Dio(dio.options)
      ..httpClientAdapter = dio.httpClientAdapter;
    _cachedRetryClient = client;
    return client;
  }

  bool _isAuthEndpoint(String path) {
    return path.contains('/auth/login/') ||
        path.contains('/auth/refresh/') ||
        path.contains('/auth/otp/');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logRequest(options);

    // Bypass adding auth header for unauthenticated auth endpoints
    if (_isAuthEndpoint(options.path)) {
      return handler.next(options);
    }

    final token = tokenProvider();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    return handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _logResponse(response);
    return handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    _logError(err);

    final isAuth = _isAuthEndpoint(err.requestOptions.path);
    final is401 = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra[kRetriedKey] == true;

    // Do not attempt token refresh for non-401, auth endpoints, or already retried requests
    if (!is401 || isAuth || alreadyRetried) {
      if (is401 && alreadyRetried) {
        await onSessionExpired();
      }
      return handler.next(err);
    }

    // Check for GUEST_EXPIRED
    final responseData = err.response?.data;
    if (responseData is Map && responseData['code'] == 'GUEST_EXPIRED') {
      await onSessionExpired();
      return handler.next(
        DioException(
          requestOptions: err.requestOptions,
          response: err.response,
          error: const GuestExpiredException(),
        ),
      );
    }

    try {
      final requestToken = err.requestOptions.headers['Authorization'] as String?;
      final latestToken = tokenProvider();
      final latestBearer = (latestToken != null && latestToken.isNotEmpty) ? 'Bearer $latestToken' : null;

      String? targetAccessToken;

      // If token was already refreshed by another concurrent request, reuse the fresh token
      if (latestBearer != null && requestToken != null && requestToken != latestBearer) {
        targetAccessToken = latestToken;
      } else {
        // Coalesce concurrent refresh requests into a single in-flight Future
        _inFlightRefresh ??= refreshTokenHandler().whenComplete(() {
          _inFlightRefresh = null;
        });

        targetAccessToken = await _inFlightRefresh;
      }

      if (targetAccessToken == null || targetAccessToken.isEmpty) {
        await onSessionExpired();
        return handler.next(err);
      }

      // Prepare request options for single retry
      final requestOptions = err.requestOptions.copyWith(
        headers: {
          ...err.requestOptions.headers,
          'Authorization': 'Bearer $targetAccessToken',
        },
        extra: {
          ...err.requestOptions.extra,
          kRetriedKey: true,
        },
      );

      // Replay through a bare Dio that shares this client's adapter and options.
      // Going through Dio rather than calling the adapter directly preserves the
      // request body, its encoding and the response parsing, while the empty
      // interceptor list avoids re-locking this QueuedInterceptor.
      try {
        final response = await _retryClient.fetch<dynamic>(requestOptions);
        return handler.resolve(response);
      } on DioException catch (retryErr) {
        if (retryErr.response?.statusCode == 401) {
          await onSessionExpired();
        }
        return handler.reject(retryErr);
      }
    } catch (_) {
      await onSessionExpired();
      return handler.next(err);
    }
  }

  String _sanitizeUri(Uri uri) {
    if (!uri.hasQuery) return uri.toString();
    final sanitizedParams = Map<String, dynamic>.from(uri.queryParameters);
    const sensitiveKeys = {'token', 'access', 'refresh', 'password', 'otp', 'code'};
    for (final key in sensitiveKeys) {
      if (sanitizedParams.containsKey(key)) {
        sanitizedParams[key] = '[REDACTED]';
      }
    }
    return uri.replace(queryParameters: sanitizedParams).toString();
  }

  void _logRequest(RequestOptions options) {
    if (kDebugMode) {
      final sanitized = _sanitizeUri(options.uri);
      debugPrint('[HTTP REQ] ${options.method} $sanitized');
    }
  }

  void _logResponse(Response response) {
    if (kDebugMode) {
      final sanitized = _sanitizeUri(response.requestOptions.uri);
      debugPrint('[HTTP RES] ${response.statusCode} $sanitized');
    }
  }

  void _logError(DioException err) {
    if (kDebugMode) {
      final sanitized = _sanitizeUri(err.requestOptions.uri);
      debugPrint('[HTTP ERR] ${err.response?.statusCode} $sanitized (${err.type})');
    }
  }
}
