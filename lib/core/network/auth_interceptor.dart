import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

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
    final client = Dio(dio.options.copyWith())
      ..httpClientAdapter = dio.httpClientAdapter;
    _cachedRetryClient = client;
    return client;
  }

  bool _isAuthEndpoint(String path) {
    return path.contains('/auth/login/') ||
        path.contains('/auth/refresh/') ||
        path.contains('/auth/otp/') ||
        path.contains('/auth/totp/validate/');
  }

  /// `user_id` claim of a bearer token, or null when the token is not a
  /// decodable JWT (tests / opaque tokens) — identity checks are skipped then.
  int? _userIdClaim(String? token) {
    if (token == null || token.isEmpty) return null;
    final bearer = token.startsWith('Bearer ') ? token.substring(7) : token;
    try {
      final claims = JwtDecoder.decode(bearer);
      final raw = claims['user_id'] ?? claims['id'];
      if (raw is int) return raw;
      return int.tryParse('$raw');
    } catch (_) {
      return null;
    }
  }

  /// True when the failed request was issued under a *different* session than
  /// the one currently active (e.g. user B is signed in while user A's queued
  /// request arrives). Such a request must not be replayed with the new user's
  /// token, and its failure must not tear down the new session.
  bool _identitySuperseded(RequestOptions options) {
    final requestUser =
        _userIdClaim(options.headers['Authorization'] as String?);
    final current = tokenProvider();
    final currentUser = _userIdClaim(current);
    if (requestUser == null || currentUser == null) return false;
    return requestUser != currentUser;
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

  Future<void> _expireSession() async {
    try {
      await onSessionExpired();
    } catch (_) {
      debugPrint('Session cleanup failed; credentials require manual retry.');
    }
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    _logError(err);

    final isAuth = _isAuthEndpoint(err.requestOptions.path);
    final is401 = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra[kRetriedKey] == true;

    // Do not attempt token refresh for non-401, auth endpoints, or already retried requests
    if (!is401 || isAuth || alreadyRetried) {
      if (is401 && alreadyRetried) {
        // Check the identity first: a stale request from a superseded session
        // must not tear down the newer session.
        if (!_identitySuperseded(err.requestOptions)) {
          await _expireSession();
        }
        return handler.next(err);
      }
      return handler.next(err);
    }

    // Stale request from a superseded session: never replay it (it would run
    // as the *current* user) and never fire session-expired for it.
    if (_identitySuperseded(err.requestOptions)) {
      return handler.next(err);
    }

    // Check for GUEST_EXPIRED
    final responseData = err.response?.data;
    if (responseData is Map && responseData['code'] == 'GUEST_EXPIRED') {
      await _expireSession();
      return handler.next(
        DioException(
          requestOptions: err.requestOptions,
          response: err.response,
          error: const GuestExpiredException(),
        ),
      );
    }

    try {
      final requestToken =
          err.requestOptions.headers['Authorization'] as String?;
      final latestToken = tokenProvider();
      final latestBearer = (latestToken != null && latestToken.isNotEmpty)
          ? 'Bearer $latestToken'
          : null;

      String? targetAccessToken;

      // If token was already refreshed by another concurrent request, reuse the fresh token
      if (latestBearer != null &&
          requestToken != null &&
          requestToken != latestBearer) {
        targetAccessToken = latestToken;
      } else {
        // Coalesce concurrent refresh requests into a single in-flight Future
        _inFlightRefresh ??= refreshTokenHandler().whenComplete(() {
          _inFlightRefresh = null;
        });

        targetAccessToken = await _inFlightRefresh;
      }

      if (targetAccessToken == null || targetAccessToken.isEmpty) {
        await _expireSession();
        return handler.next(err);
      }

      // Prepare request options for single retry. A FormData has already been
      // finalized by the failed attempt (its body was fully sent before the
      // server could answer 401): re-sending it as-is throws
      // "FormData has already been finalized", so clone it for the replay.
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
      if (requestOptions.data is FormData) {
        try {
          requestOptions.data = (requestOptions.data as FormData).clone();
        } catch (e) {
          debugPrint('AuthInterceptor: unable to clone FormData for retry: $e');
        }
      }

      // Replay through a bare Dio that shares this client's adapter and options.
      // Re-enforce the HTTPS-only guard from DioClient: the retry client is
      // bare and would otherwise bypass prod TLS enforcement.
      final retryUri = requestOptions.uri;
      if (retryUri.scheme != 'https' &&
          !(retryUri.host == 'localhost' ||
              retryUri.host == '127.0.0.1' ||
              retryUri.host == '10.0.2.2')) {
        await _expireSession();
        return handler.next(err);
      }
      try {
        final response = await _retryClient.fetch<dynamic>(requestOptions);
        return handler.resolve(response);
      } on DioException catch (retryErr) {
        if (retryErr.response?.statusCode == 401) {
          await _expireSession();
        }
        return handler.reject(retryErr);
      }
    } catch (_) {
      // A failed network/storage refresh is not an invalid refresh token.
      // Preserve credentials and return the original request failure for retry.
      return handler.next(err);
    }
  }

  String _sanitizeUri(Uri uri) {
    if (!uri.hasQuery) return uri.toString();
    final sanitizedParams = Map<String, dynamic>.from(uri.queryParameters);
    const sensitiveKeys = {
      'token',
      'access',
      'refresh',
      'password',
      'otp',
      'code'
    };
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
      debugPrint(
          '[HTTP ERR] ${err.response?.statusCode} $sanitized (${err.type})');
      if (err.response?.statusCode == 403 &&
          err.requestOptions.path.endsWith('/attachments/')) {
        final reason = serverMessage(err.response?.data);
        debugPrint('[PHOTO DENIAL] ${reason ?? 'No readable server reason.'}');
      }
    }
  }
}
