import 'package:dio/dio.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
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
      final access = data['access'];
      if (access is! String || access.isEmpty) {
        throw const AuthException('Invalid access token in login response');
      }
      final refresh = data['refresh'];

      return AuthTokens(
        accessToken: access,
        refreshToken: refresh is String ? refresh : null,
      );
    } on DioException catch (e) {
      throw _parseDioError(e);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Invalid login response: $e');
    }
  }

  /// Request OTP for LOGIN or password_reset — POST /api/v1/auth/otp/request/
  Future<void> requestOtp({
    required String email,
    String purpose = 'LOGIN',
  }) async {
    try {
      await _dio.post(
        '/api/v1/auth/otp/request/',
        data: {
          'email': email.trim().toLowerCase(),
          'purpose': purpose,
        },
      );
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  /// Sign in with email OTP — POST /api/v1/auth/otp/login/
  Future<AuthTokens> loginWithOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/otp/login/',
        data: {
          'email': email.trim().toLowerCase(),
          'otp_code': otp.trim(),
          'purpose': 'LOGIN',
        },
      );
      final data = response.data;
      if (data == null || data['access'] == null) {
        throw const AuthException('Invalid OTP login response structure');
      }
      final access = data['access'];
      if (access is! String || access.isEmpty) {
        throw const AuthException('Invalid access token in OTP login response');
      }
      final refresh = data['refresh'];
      return AuthTokens(
        accessToken: access,
        refreshToken: refresh is String ? refresh : null,
      );
    } on DioException catch (e) {
      throw _parseDioError(e);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Invalid OTP login response: $e');
    }
  }

  /// Reset password with verified OTP — POST /api/v1/auth/reset-password/
  Future<void> resetPasswordWithOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      await _dio.post(
        '/api/v1/auth/reset-password/',
        data: {
          'email': email.trim().toLowerCase(),
          'otp_code': otp.trim(),
          'new_password': newPassword,
        },
      );
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
      final access = data['access'];
      if (access is! String || access.isEmpty) {
        throw const AuthException('Invalid access token in TOTP response');
      }
      final refresh = data['refresh'];
      return AuthTokens(accessToken: access, refreshToken: refresh is String ? refresh : null);
    } on DioException catch (e) {
      throw _parseDioError(e);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Invalid TOTP response: $e');
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

  /// PATCH /api/v1/users/{id}/ — update or clear profile picture.
  /// If filePath != null, sends multipart/form-data with profile_picture file.
  /// If filePath == null, sends JSON {'profile_picture': null} to remove the photo.
  Future<Map<String, dynamic>> updateUserPhoto(int userId, String? filePath) async {
    try {
      final dynamic data;
      if (filePath != null) {
        final filename = filePath.split(RegExp(r'[/\\]')).last;
        try {
          data = FormData.fromMap({
            'profile_picture': await MultipartFile.fromFile(
              filePath,
              filename: filename,
            ),
          });
        } catch (e) {
          throw AuthException('Unable to read photo file: $e');
        }
      } else {
        data = {'profile_picture': null};
      }

      final response = await _dio.patch('/api/v1/users/$userId/', data: data);
      final resData = response.data;
      if (resData == null) return {};
      if (resData is Map<String, dynamic>) return resData;
      if (resData is Map) return Map<String, dynamic>.from(resData);
      return {};
    } on DioException catch (e) {
      throw _parseDioError(e);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Unable to update photo: $e');
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
      final access = data['access'];
      if (access is! String || access.isEmpty) {
        throw const AuthException('Invalid access token in refresh response');
      }
      final refresh = data['refresh'];

      return AuthTokens(
        accessToken: access,
        refreshToken: refresh is String && refresh.isNotEmpty ? refresh : refreshToken,
      );
    } on DioException catch (e) {
      throw _parseDioError(e);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Invalid refresh response: $e');
    }
  }

  AuthException _parseDioError(DioException e) {
    if (e.response != null) {
      final statusCode = e.response?.statusCode;
      final data = e.response?.data;

      String detail = 'Authentication failed';
      String? code;
      int? attemptsRemaining;

      if (data is Map) {
        // serverMessage() filters HTML pages, oversized dumps and nested DRF
        // shapes — never surface a proxy error page on the login screen.
        detail = serverMessage(data) ?? detail;
        code = data['code']?.toString();
        if (data['attempts_remaining'] != null) {
          attemptsRemaining = int.tryParse(data['attempts_remaining'].toString());
        }
      } else if (data is String && data.isNotEmpty) {
        detail = serverMessage(data) ?? detail;
      }

      // Check specific error codes and messages
      if (code == '2FA_REQUIRED' || detail == '2FA_REQUIRED') {
        return const TwoFactorRequiredException();
      }
      final lowerDetail = detail.toLowerCase();
      if (code == 'OTP_LOCKED_OUT' ||
          (statusCode == 429 && lowerDetail.contains('locked out'))) {
        return OtpLockoutException(detail);
      }
      if (code == 'INVALID_OTP' ||
          lowerDetail.contains('invalid 2fa') ||
          lowerDetail.contains('invalid or expired otp') ||
          lowerDetail.contains('invalid otp')) {
        return InvalidOtpException(detail, attemptsRemaining);
      }
      if (code == 'RATE_LIMIT_EXCEEDED' || (statusCode == 429 && lowerDetail.contains('wait'))) {
        return RateLimitExceededException(detail);
      }
      // Map EMAIL_DELIVERY_FAILED only when the server says so — a bare 502
      // from a gateway has nothing to do with email delivery and telling the
      // user otherwise is misleading.
      if (code == 'EMAIL_DELIVERY_FAILED') {
        return AuthException(detail, code: 'EMAIL_DELIVERY_FAILED');
      }
      if (statusCode == 502) {
        return const AuthException(
          'The service is temporarily unavailable. Please try again.',
          code: 'SERVICE_UNAVAILABLE',
        );
      }
      if (code == 'GUEST_EXPIRED' ||
          lowerDetail.contains('demo access has expired') ||
          lowerDetail.contains('account access has expired')) {
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

    return const NetworkAuthException();
  }
}
