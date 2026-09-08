import 'package:dio/dio.dart';
import '../domain/models/auth_exceptions.dart';
import '../domain/models/auth_tokens.dart';

/// Service responsible for raw HTTP calls to the Django backend authentication endpoints.
class AuthApiService {
  const AuthApiService(this._dio);

  final Dio _dio;

  /// Call POST /api/v1/auth/login/
  Future<AuthTokens> login({
    required String username,
    required String password,
    String? otp,
  }) async {
    try {
      final payload = <String, dynamic>{
        'username': username.trim(),
        'password': password,
      };
      if (otp != null && otp.trim().isNotEmpty) {
        payload['otp'] = otp.trim();
      }

      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/login/',
        data: payload,
      );

      final data = response.data;
      if (data == null || data['access'] == null) {
        throw const AuthException('Invalid response structure from login endpoint');
      }

      return AuthTokens(
        accessToken: data['access'] as String,
        refreshToken: data['refresh'] as String?,
      );
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  /// OTP request/verify — POST /api/v1/auth/otp/request/ & /verify/
  Future<void> requestOtp(String username) async {
    try {
      await _dio.post('/api/v1/auth/otp/request/', data: {'username': username.trim()});
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  Future<AuthTokens> verifyOtp({required String username, required String otp}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/otp/verify/',
        data: {'username': username.trim(), 'otp': otp.trim()},
      );
      final data = response.data;
      if (data == null || data['access'] == null) throw const AuthException('Invalid OTP verify response');
      return AuthTokens(accessToken: data['access'] as String, refreshToken: data['refresh'] as String?);
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  /// TOTP setup/verify — POST /api/v1/auth/totp/setup/ etc.
  Future<Map<String, dynamic>> setupTotp() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>('/api/v1/auth/totp/setup/');
      return response.data ?? {};
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  Future<void> verifyTotp(String code) async {
    try {
      await _dio.post('/api/v1/auth/totp/verify/', data: {'code': code.trim()});
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  Future<AuthTokens> validateTotp({required String username, required String password, required String code}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/totp/validate/',
        data: {'username': username.trim(), 'password': password, 'code': code.trim()},
      );
      final data = response.data;
      if (data == null || data['access'] == null) throw const AuthException('Invalid TOTP validate response');
      return AuthTokens(accessToken: data['access'] as String, refreshToken: data['refresh'] as String?);
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  /// GET /api/v1/users/{id}/ — same payload the web profile screen loads.
  Future<Map<String, dynamic>> getUser(int userId) async {
    try {
      final response = await _dio.get('/api/v1/users/$userId/');
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const AuthException('Invalid user profile response');
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  /// PATCH /api/v1/users/{id}/ — personal fields or `{password: …}`.
  Future<Map<String, dynamic>> updateUser(int userId, Map<String, dynamic> payload) async {
    try {
      final response = await _dio.patch('/api/v1/users/$userId/', data: payload);
      final data = response.data;
      if (data == null) return {};
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {};
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  /// Call POST /api/v1/auth/refresh/
  Future<AuthTokens> refreshToken(String refreshToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh/',
        data: {'refresh': refreshToken},
      );

      final data = response.data;
      if (data == null || data['access'] == null) {
        throw const AuthException('Invalid response structure from refresh endpoint');
      }

      return AuthTokens(
        accessToken: data['access'] as String,
        refreshToken: data['refresh'] as String? ?? refreshToken,
      );
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  AuthException _parseDioError(DioException e) {
    if (e.response != null) {
      final statusCode = e.response?.statusCode;
      final data = e.response?.data;

      String detail = 'Authentication failed';
      String? code;

      if (data is Map) {
        detail = data['detail']?.toString() ?? data['message']?.toString() ?? detail;
        code = data['code']?.toString();
        if (data['detail'] == null && data['message'] == null) {
          final parts = <String>[];
          for (final value in data.values) {
            if (value is List) {
              parts.addAll(value.map((e) => e.toString()));
            } else if (value is String && value.isNotEmpty) {
              parts.add(value);
            }
          }
          if (parts.isNotEmpty) detail = parts.join(' ');
        }
      } else if (data is String && data.isNotEmpty) {
        detail = data;
      }

      // Check specific error codes and messages
      if (code == '2FA_REQUIRED' || detail == '2FA_REQUIRED') {
        return const TwoFactorRequiredException();
      }
      final lowerDetail = detail.toLowerCase();
      if (code == 'INVALID_OTP' || lowerDetail.contains('invalid 2fa') || lowerDetail.contains('invalid otp')) {
        return InvalidOtpException(detail);
      }
      if (code == 'RATE_LIMIT_EXCEEDED' || lowerDetail.contains('too many')) {
        return RateLimitExceededException(detail);
      }
      if (code == 'GUEST_EXPIRED' || lowerDetail.contains('demo access has expired')) {
        return GuestExpiredException(detail);
      }
      if (lowerDetail.contains('account is disabled')) {
        return AccountDisabledException(detail);
      }
      if ((statusCode == 400 || statusCode == 401) &&
          (lowerDetail.contains('user not found') ||
           lowerDetail.contains('invalid password') ||
           lowerDetail.contains('no active account') ||
           lowerDetail.contains('invalid credentials'))) {
        return InvalidCredentialsException(detail);
      }
      if (statusCode == 401) {
        return UnauthorizedException(detail);
      }
      if (statusCode == 403) {
        return ForbiddenException(detail);
      }

      return AuthException(detail, code: code);
    }

    return NetworkAuthException(e.message ?? 'Network error during authentication');
  }
}
