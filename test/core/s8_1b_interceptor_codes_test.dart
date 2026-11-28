import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gssms_mobile/app/app.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/network/auth_interceptor.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/screens/change_password_screen.dart';
import 'package:gssms_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Map<String, dynamic> body, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('S8-1b HTTP Error Codes & AuthInterceptor', () {
    testWidgets(
      '1. 403 PASSWORD_CHANGE_REQUIRED on restored session flips mustChangePassword=true and shows ChangePasswordScreen',
      (tester) async {
        final mockRepo = MockAuthRepository();
        const restoredSession = UserSession(
          accessToken: 'tok_restored',
          username: 'amc_tech_1',
          userId: 42,
          primaryRole: AuthRole.maintenanceStaff,
          roles: [AuthRole.maintenanceStaff],
          permissions: ['maintenance.view'],
          isContractStaff: true,
          mustChangePassword: false,
        );
        when(() => mockRepo.currentAccessToken).thenReturn('tok_restored');
        when(() => mockRepo.currentSession).thenReturn(restoredSession);
        when(() => mockRepo.restoreSession()).thenAnswer((_) async => restoredSession);
        when(() => mockRepo.logout()).thenAnswer((_) async {});

        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const GssmsApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(ChangePasswordScreen), findsNothing);

        final dio = container.read(authenticatedDioProvider);
        dio.httpClientAdapter = _StubAdapter((options) async {
          return _jsonBody(
            {
              'code': 'PASSWORD_CHANGE_REQUIRED',
              'detail': 'Password change required before continuing.',
            },
            403,
          );
        });

        await tester.runAsync(() async {
          await expectLater(
            dio.get('/api/v1/staff-workorders/'),
            throwsA(isA<DioException>()),
          );
        });
        await tester.pumpAndSettle();

        expect(find.byType(ChangePasswordScreen), findsOneWidget);
        expect(find.byType(HomeScreen), findsNothing);
      },
    );

    for (final entry in <String, String>{
      'SESSION_REVOKED': 'Your session has been revoked. Please sign in again.',
      'user_inactive': 'Your account has been deactivated. Please contact your administrator.',
      'no_active_account': 'Your account is no longer active. Please contact your administrator.',
      'CONTRACT_EXPIRED': 'Your contract has expired. Please contact your Divisional Admin.',
    }.entries) {
      test(
        '2. 401 ${entry.key} clears session without refresh retry and passes distinct notice',
        () async {
          var refreshCalls = 0;
          String? capturedReason;
          String? capturedCode;
          final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
          dio.httpClientAdapter = _StubAdapter(
            (options) async => _jsonBody({'code': entry.key, 'detail': 'Server detail'}, 401),
          );
          dio.interceptors.add(
            AuthInterceptor(
              dio: dio,
              tokenProvider: () => 'tok_1',
              refreshTokenHandler: () async {
                refreshCalls++;
                return 'tok_2';
              },
              onSessionExpired: () async {},
              onSessionInvalidated: (reason, code) async {
                capturedReason = reason;
                capturedCode = code;
              },
            ),
          );

          await expectLater(
            dio.get('/api/v1/staff-workorders/'),
            throwsA(isA<DioException>()),
          );

          expect(refreshCalls, 0);
          expect(capturedReason, entry.value);
          expect(capturedCode, entry.key);
        },
      );
    }

    test(
      '2b. refresh 401 without code key (D108 no_active_account) invalidates session with notice',
      () async {
        String? capturedReason;
        String? capturedCode;
        final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
        dio.httpClientAdapter = _StubAdapter(
          (options) async => _jsonBody(
            {'detail': 'Given token not valid for any token type', 'code': 'token_not_valid'},
            401,
          ),
        );
        dio.interceptors.add(
          AuthInterceptor(
            dio: dio,
            tokenProvider: () => 'tok_1',
            refreshTokenHandler: () async {
              throw const InvalidCredentialsException(
                'No active account found for the given token.',
              );
            },
            onSessionExpired: () async {},
            onSessionInvalidated: (reason, code) async {
              capturedReason = reason;
              capturedCode = code;
            },
          ),
        );

        await expectLater(
          dio.get('/api/v1/staff-workorders/'),
          throwsA(isA<DioException>()),
        );

        expect(
          capturedReason,
          'Your account is no longer active. Please contact your administrator.',
        );
        expect(capturedCode, 'no_active_account');
      },
    );

    test(
      '2c. departmental (cs=false) 401 token_not_valid still refreshes and retries once',
      () async {
        var refreshCalls = 0;
        var expiredCalls = 0;
        var attempt = 0;
        final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
        dio.httpClientAdapter = _StubAdapter((options) async {
          attempt++;
          if (attempt == 1) {
            return _jsonBody({'code': 'token_not_valid', 'detail': 'Expired'}, 401);
          }
          return _jsonBody({'ok': true}, 200);
        });
        dio.interceptors.add(
          AuthInterceptor(
            dio: dio,
            tokenProvider: () => 'tok_1',
            refreshTokenHandler: () async {
              refreshCalls++;
              return 'tok_2';
            },
            onSessionExpired: () async {
              expiredCalls++;
            },
            onSessionInvalidated: (reason, code) async {
              expiredCalls++;
            },
          ),
        );

        final res = await dio.get('/api/v1/maintenance/work-orders/');
        expect(res.statusCode, 200);
        expect(refreshCalls, 1);
        expect(expiredCalls, 0);
      },
    );

    test(
      '3. 403 CONTRACT_STAFF_FORBIDDEN and AMC_EXECUTION_NOT_ALLOWED surface detail without logout',
      () async {
        var expiredCalls = 0;
        final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
        dio.interceptors.add(
          AuthInterceptor(
            dio: dio,
            tokenProvider: () => 'tok_1',
            refreshTokenHandler: () async => 'tok_2',
            onSessionExpired: () async => expiredCalls++,
            onSessionInvalidated: (_, __) async => expiredCalls++,
          ),
        );

        for (final pair in [
          ('CONTRACT_STAFF_FORBIDDEN', 'Contract staff cannot access this resource.'),
          ('AMC_EXECUTION_NOT_ALLOWED', 'Job work is outside the assigned contract scope.'),
        ]) {
          dio.httpClientAdapter = _StubAdapter(
            (options) async => _jsonBody({'code': pair.$1, 'detail': pair.$2}, 403),
          );
          try {
            await dio.get('/api/v1/complaints/');
            fail('Expected DioException');
          } on DioException catch (e) {
            expect(userFacingError(e), pair.$2);
          }
        }
        expect(expiredCalls, 0);
      },
    );

    test('4. 409 CONCURRENT_UPDATE returns exact required message', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/api/v1/maintenance/records/1/submit_line/'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/maintenance/records/1/submit_line/'),
          statusCode: 409,
          data: {
            'code': 'CONCURRENT_UPDATE',
            'detail': 'A concurrent update prevented this operation.',
          },
        ),
      );
      expect(
        userFacingError(err),
        'Someone else changed this job work at the same time. Reload and try again.',
      );
    });

    testWidgets('5. ChangePasswordScreen Sign Out button uses readable AppBar foreground colour',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ChangePasswordScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<TextButton>(
        find.byKey(const Key('change_pw_sign_out_button')),
      );
      final fg = btn.style?.foregroundColor?.resolve({});
      expect(fg, AppTheme.lightTheme.appBarTheme.foregroundColor);
    });
  });
}
