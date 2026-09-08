import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/data/auth_api_service.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  group('AuthApiService', () {
    late MockDio mockDio;
    late AuthApiService apiService;

    setUp(() {
      mockDio = MockDio();
      apiService = AuthApiService(mockDio);
    });

    test('login returns AuthTokens on 200 response', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/v1/auth/login/',
          data: {'username': 'test_user', 'password': 'password123'},
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
          statusCode: 200,
          data: {'access': 'jwt_access', 'refresh': 'jwt_refresh'},
        ),
      );

      final tokens = await apiService.login(
        username: 'test_user',
        password: 'password123',
      );

      expect(tokens.accessToken, 'jwt_access');
      expect(tokens.refreshToken, 'jwt_refresh');
    });

    test('login throws InvalidCredentialsException on 400 invalid password', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/v1/auth/login/',
          data: {'username': 'test_user', 'password': 'wrong_password'},
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
            statusCode: 400,
            data: {'detail': 'Invalid password'},
          ),
        ),
      );

      expect(
        () => apiService.login(username: 'test_user', password: 'wrong_password'),
        throwsA(isA<InvalidCredentialsException>()),
      );
    });

    test('login throws TwoFactorRequiredException on 2FA_REQUIRED error', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/v1/auth/login/',
          data: {'username': 'test_user', 'password': 'password123'},
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
            statusCode: 400,
            data: {'detail': '2FA_REQUIRED', 'code': '2FA_REQUIRED'},
          ),
        ),
      );

      expect(
        () => apiService.login(username: 'test_user', password: 'password123'),
        throwsA(isA<TwoFactorRequiredException>()),
      );
    });

    test('login throws InvalidOtpException on INVALID_OTP error', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/v1/auth/login/',
          data: {'username': 'test_user', 'password': 'password123', 'otp': '000000'},
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
            statusCode: 400,
            data: {'detail': 'Invalid 2FA Code', 'code': 'INVALID_OTP'},
          ),
        ),
      );

      expect(
        () => apiService.login(username: 'test_user', password: 'password123', otp: '000000'),
        throwsA(isA<InvalidOtpException>()),
      );
    });

    test('login throws RateLimitExceededException on RATE_LIMIT_EXCEEDED', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/v1/auth/login/',
          data: {'username': 'test_user', 'password': 'password123'},
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
            statusCode: 400,
            data: {'detail': 'Too many attempts', 'code': 'RATE_LIMIT_EXCEEDED'},
          ),
        ),
      );

      expect(
        () => apiService.login(username: 'test_user', password: 'password123'),
        throwsA(isA<RateLimitExceededException>()),
      );
    });

    test('login and refresh throw GuestExpiredException on 401 GUEST_EXPIRED', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/v1/auth/login/',
          data: {'username': 'guest_user', 'password': 'password123'},
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
            statusCode: 401,
            data: {'detail': 'Demo access has expired.', 'code': 'GUEST_EXPIRED'},
          ),
        ),
      );

      expect(
        () => apiService.login(username: 'guest_user', password: 'password123'),
        throwsA(isA<GuestExpiredException>()),
      );
    });

    test('refresh throws UnauthorizedException on generic 401 without GUEST_EXPIRED', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/v1/auth/refresh/',
          data: {'refresh': 'invalid_token'},
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/auth/refresh/'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/auth/refresh/'),
            statusCode: 401,
            data: {'detail': 'Token is invalid or expired'},
          ),
        ),
      );

      expect(
        () => apiService.refreshToken('invalid_token'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('throws ForbiddenException on HTTP 403', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/v1/auth/login/',
          data: {'username': 'forbidden_user', 'password': 'password123'},
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/auth/login/'),
            statusCode: 403,
            data: {'detail': 'Permission denied'},
          ),
        ),
      );

      expect(
        () => apiService.login(username: 'forbidden_user', password: 'password123'),
        throwsA(isA<ForbiddenException>()),
      );
    });

    test('refreshToken preserves existing refresh token if not returned by server', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/v1/auth/refresh/',
          data: {'refresh': 'existing_refresh_token'},
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/v1/auth/refresh/'),
          statusCode: 200,
          data: {'access': 'new_jwt_access'},
        ),
      );

      final tokens = await apiService.refreshToken('existing_refresh_token');
      expect(tokens.accessToken, 'new_jwt_access');
      expect(tokens.refreshToken, 'existing_refresh_token');
    });

    test('getUser calls GET /api/v1/users/{id}/', () async {
      when(() => mockDio.get('/api/v1/users/7/')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/v1/users/7/'),
          statusCode: 200,
          data: {
            'id': 7,
            'username': 'srdee',
            'email': 'srdee@example.com',
            'phone_number': '999',
            'designation': 'SrDEE',
          },
        ),
      );

      final data = await apiService.getUser(7);
      expect(data['username'], 'srdee');
      expect(data['designation'], 'SrDEE');
    });

    test('updateUser PATCHes personal fields to /api/v1/users/{id}/', () async {
      registerFallbackValue(<String, dynamic>{});
      when(
        () => mockDio.patch('/api/v1/users/7/', data: any(named: 'data')),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/v1/users/7/'),
          statusCode: 200,
          data: {'id': 7, 'email': 'new@example.com'},
        ),
      );

      await apiService.updateUser(7, {
        'email': 'new@example.com',
        'phone_number': '111',
        'designation': 'SrDEE',
      });

      verify(
        () => mockDio.patch(
          '/api/v1/users/7/',
          data: {
            'email': 'new@example.com',
            'phone_number': '111',
            'designation': 'SrDEE',
          },
        ),
      ).called(1);
    });
  });
}
