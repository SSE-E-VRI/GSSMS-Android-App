import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/screens/otp_email_screen.dart';
import 'package:gssms_mobile/features/auth/presentation/screens/otp_flow_mode.dart';
import 'package:gssms_mobile/features/auth/presentation/screens/otp_verification_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

String _createFakeJwt({
  String username = 'otp_user',
  String role = 'MAINTENANCE_STAFF',
  int userId = 1,
}) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
  final payload = base64Url.encode(utf8.encode(jsonEncode({
    'user_id': userId,
    'username': username,
    'role': role,
    'roles': [role],
    'permissions': ['maintenance.view'],
    'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
  })));
  return '$header.$payload.fakesignature';
}

void main() {
  group('OTP Flow Tests', () {
    late MockAuthRepository mockRepository;

    setUp(() {
      mockRepository = MockAuthRepository();
    });

    Widget createTestWidget(Widget child) {
      return ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockRepository),
        ],
        child: MaterialApp(
          home: child,
        ),
      );
    }

    group('OtpEmailScreen', () {
      testWidgets('validates email field on submit', (tester) async {
        await tester.pumpWidget(
          createTestWidget(const OtpEmailScreen(mode: OtpFlowMode.login)),
        );

        // Submit empty
        await tester.tap(find.byKey(const Key('otp_send_code_button')));
        await tester.pumpAndSettle();
        expect(find.text('Please enter your email'), findsOneWidget);

        // Enter invalid email
        await tester.enterText(
          find.byKey(const Key('otp_email_field')),
          'notanemail',
        );
        await tester.tap(find.byKey(const Key('otp_send_code_button')));
        await tester.pumpAndSettle();
        expect(find.text('Please enter a valid email address'), findsOneWidget);
      });

      testWidgets('requests OTP for login and navigates to verification screen', (tester) async {
        when(
          () => mockRepository.requestOtp(
            email: 'tech@example.com',
            purpose: 'LOGIN',
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(
          createTestWidget(const OtpEmailScreen(mode: OtpFlowMode.login)),
        );

        await tester.enterText(
          find.byKey(const Key('otp_email_field')),
          'tech@example.com',
        );
        await tester.tap(find.byKey(const Key('otp_send_code_button')));
        await tester.pumpAndSettle();

        verify(
          () => mockRepository.requestOtp(
            email: 'tech@example.com',
            purpose: 'LOGIN',
          ),
        ).called(1);

        // Verification screen should now be displayed
        expect(find.text('Verify Sign-In Code'), findsWidgets);
        expect(find.byKey(const Key('otp_code_field')), findsOneWidget);
      });

      testWidgets('requests OTP for password_reset and navigates to verification screen', (tester) async {
        when(
          () => mockRepository.requestOtp(
            email: 'tech@example.com',
            purpose: 'password_reset',
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(
          createTestWidget(const OtpEmailScreen(mode: OtpFlowMode.forgotPassword)),
        );

        await tester.enterText(
          find.byKey(const Key('otp_email_field')),
          'tech@example.com',
        );
        await tester.tap(find.byKey(const Key('otp_send_code_button')));
        await tester.pumpAndSettle();

        verify(
          () => mockRepository.requestOtp(
            email: 'tech@example.com',
            purpose: 'password_reset',
          ),
        ).called(1);

        expect(find.text('Reset Password'), findsWidgets);
        expect(find.byKey(const Key('otp_new_password_field')), findsOneWidget);
      });

      testWidgets('displays error banner if requestOtp throws AuthException', (tester) async {
        when(
          () => mockRepository.requestOtp(
            email: 'tech@example.com',
            purpose: 'LOGIN',
          ),
        ).thenThrow(const RateLimitExceededException('Please wait before requesting another OTP.'));

        await tester.pumpWidget(
          createTestWidget(const OtpEmailScreen(mode: OtpFlowMode.login)),
        );

        await tester.enterText(
          find.byKey(const Key('otp_email_field')),
          'tech@example.com',
        );
        await tester.tap(find.byKey(const Key('otp_send_code_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('otp_email_error_banner')), findsOneWidget);
        expect(find.text('Please wait before requesting another OTP.'), findsOneWidget);
      });
    });

    group('OtpVerificationScreen', () {
      testWidgets('displays 10-minute expiry notice and 60s countdown', (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            const OtpVerificationScreen(
              mode: OtpFlowMode.login,
              email: 'tech@example.com',
            ),
          ),
        );

        expect(find.byKey(const Key('otp_expiry_notice')), findsOneWidget);
        expect(find.text('Expires in 10 minutes'), findsOneWidget);
        expect(find.byKey(const Key('otp_resend_countdown_text')), findsOneWidget);
        expect(find.text('Resend code in 60s'), findsOneWidget);
        expect(find.byKey(const Key('otp_resend_button')), findsNothing);

        // Advance timer by 5 seconds
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('Resend code in 55s'), findsOneWidget);

        // Advance past 60s
        await tester.pump(const Duration(seconds: 56));
        expect(find.byKey(const Key('otp_resend_countdown_text')), findsNothing);
        expect(find.byKey(const Key('otp_resend_button')), findsOneWidget);
      });

      testWidgets('resend button calls requestOtp, shows snackbar, and resets 60s timer', (tester) async {
        when(
          () => mockRepository.requestOtp(
            email: 'tech@example.com',
            purpose: 'LOGIN',
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(
          createTestWidget(
            const OtpVerificationScreen(
              mode: OtpFlowMode.login,
              email: 'tech@example.com',
            ),
          ),
        );

        // Advance 60 seconds to enable resend
        await tester.pump(const Duration(seconds: 60));
        expect(find.byKey(const Key('otp_resend_button')), findsOneWidget);

        await tester.tap(find.byKey(const Key('otp_resend_button')));
        await tester.pumpAndSettle();

        verify(
          () => mockRepository.requestOtp(
            email: 'tech@example.com',
            purpose: 'LOGIN',
          ),
        ).called(1);

        expect(find.text('Verification code resent to your email.'), findsOneWidget);
        expect(find.text('Resend code in 60s'), findsOneWidget);
      });

      testWidgets('validates 6-digit code format', (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            const OtpVerificationScreen(
              mode: OtpFlowMode.login,
              email: 'tech@example.com',
            ),
          ),
        );

        // Empty code
        await tester.tap(find.byKey(const Key('otp_verify_submit_button')));
        await tester.pumpAndSettle();
        expect(find.text('Enter the 6-digit verification code'), findsOneWidget);

        // Incomplete code
        await tester.enterText(find.byKey(const Key('otp_code_field')), '123');
        await tester.tap(find.byKey(const Key('otp_verify_submit_button')));
        await tester.pumpAndSettle();
        expect(find.text('Code must be exactly 6 digits'), findsOneWidget);
      });

      testWidgets('shows attempts remaining feedback on InvalidOtpException', (tester) async {
        when(
          () => mockRepository.loginWithOtp(
            email: 'tech@example.com',
            otp: '123456',
          ),
        ).thenThrow(const InvalidOtpException('Invalid or expired OTP. 4 attempts remaining.', 4));

        await tester.pumpWidget(
          createTestWidget(
            const OtpVerificationScreen(
              mode: OtpFlowMode.login,
              email: 'tech@example.com',
            ),
          ),
        );

        await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
        await tester.tap(find.byKey(const Key('otp_verify_submit_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('otp_error_banner')), findsOneWidget);
        expect(find.text('Invalid or expired OTP. 4 attempts remaining.'), findsOneWidget);
        expect(find.byKey(const Key('otp_attempts_remaining_text')), findsOneWidget);
        expect(find.text('4 attempts remaining before lockout.'), findsOneWidget);
      });

      testWidgets('shows lockout feedback and disables submit on OtpLockoutException', (tester) async {
        when(
          () => mockRepository.loginWithOtp(
            email: 'tech@example.com',
            otp: '123456',
          ),
        ).thenThrow(const OtpLockoutException());

        await tester.pumpWidget(
          createTestWidget(
            const OtpVerificationScreen(
              mode: OtpFlowMode.login,
              email: 'tech@example.com',
            ),
          ),
        );

        await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
        await tester.tap(find.byKey(const Key('otp_verify_submit_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('otp_error_banner')), findsOneWidget);
        expect(
          find.text('Too many incorrect attempts. Please request a new OTP and try again later.'),
          findsOneWidget,
        );

        // Submit button should now be disabled
        final submitButton = tester.widget<ElevatedButton>(
          find.byKey(const Key('otp_verify_submit_button')),
        );
        expect(submitButton.onPressed, isNull);
      });

      testWidgets('successful OTP login completes and pops to root', (tester) async {
        final fakeJwt = _createFakeJwt();
        final fakeSession = UserSession.fromJwt(fakeJwt);

        when(
          () => mockRepository.loginWithOtp(
            email: 'tech@example.com',
            otp: '123456',
          ),
        ).thenAnswer((_) async => fakeSession);

        await tester.pumpWidget(
          createTestWidget(
            const OtpVerificationScreen(
              mode: OtpFlowMode.login,
              email: 'tech@example.com',
            ),
          ),
        );

        await tester.enterText(find.byKey(const Key('otp_code_field')), '123456');
        await tester.tap(find.byKey(const Key('otp_verify_submit_button')));
        await tester.pumpAndSettle();

        verify(
          () => mockRepository.loginWithOtp(
            email: 'tech@example.com',
            otp: '123456',
          ),
        ).called(1);
      });

      testWidgets('forgot password flow validates password match and calls resetPasswordWithOtp', (tester) async {
        when(
          () => mockRepository.resetPasswordWithOtp(
            email: 'tech@example.com',
            otp: '654321',
            newPassword: 'NewSecurePassword123!',
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(
          createTestWidget(
            const OtpVerificationScreen(
              mode: OtpFlowMode.forgotPassword,
              email: 'tech@example.com',
            ),
          ),
        );

        await tester.enterText(find.byKey(const Key('otp_code_field')), '654321');
        await tester.enterText(find.byKey(const Key('otp_new_password_field')), 'NewSecurePassword123!');
        await tester.enterText(find.byKey(const Key('otp_confirm_password_field')), 'DifferentPassword!');
        await tester.tap(find.byKey(const Key('otp_verify_submit_button')));
        await tester.pumpAndSettle();

        // Passwords do not match validation error
        expect(find.text('Passwords do not match'), findsOneWidget);

        // Fix confirmation password
        await tester.enterText(find.byKey(const Key('otp_confirm_password_field')), 'NewSecurePassword123!');
        await tester.tap(find.byKey(const Key('otp_verify_submit_button')));
        await tester.pumpAndSettle();

        verify(
          () => mockRepository.resetPasswordWithOtp(
            email: 'tech@example.com',
            otp: '654321',
            newPassword: 'NewSecurePassword123!',
          ),
        ).called(1);

        expect(
          find.text('Password reset successfully. Please sign in with your new password.'),
          findsOneWidget,
        );
      });
    });
  });
}
