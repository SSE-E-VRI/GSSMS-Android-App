import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  group('LoginScreen Widget Tests', () {
    late MockAuthRepository mockRepository;

    setUp(() {
      mockRepository = MockAuthRepository();
    });

    Widget createTestWidget() {
      return ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockRepository),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      );
    }

    testWidgets('renders username, password, and sign in button with autofill hints', (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(find.byKey(const Key('login_username_field')), findsOneWidget);
      expect(find.byKey(const Key('login_password_field')), findsOneWidget);
      expect(find.byKey(const Key('login_submit_button')), findsOneWidget);
      expect(find.text('GSSMS Mobile'), findsOneWidget);
    });

    testWidgets('shows validation errors when submitting empty form', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Enter your username'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('switches to OTP challenge view on TwoFactorRequiredException and stays on OTP view during submission', (tester) async {
      when(
        () => mockRepository.login(
          username: 'admin',
          password: 'password',
        ),
      ).thenThrow(const TwoFactorRequiredException());

      await tester.pumpWidget(createTestWidget());

      await tester.enterText(find.byKey(const Key('login_username_field')), 'admin');
      await tester.enterText(find.byKey(const Key('login_password_field')), 'password');
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      // Verify OTP screen is displayed
      expect(find.byKey(const Key('login_otp_field')), findsOneWidget);
      expect(find.byKey(const Key('login_otp_submit_button')), findsOneWidget);
      expect(find.text('Two-Factor Authentication required. Enter the 6-digit code from your authenticator app.'), findsOneWidget);

      // Enter 6-digit OTP code
      await tester.enterText(find.byKey(const Key('login_otp_field')), '123456');

      // Submit OTP with delayed repository response
      when(
        () => mockRepository.login(
          username: 'admin',
          password: 'password',
          otp: '123456',
        ),
      ).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 100));
        throw const InvalidOtpException('Invalid 2FA Code');
      });

      await tester.tap(find.byKey(const Key('login_otp_submit_button')));
      await tester.pump(); // Pump the in-progress submission frame

      // CRITICAL: The OTP challenge input must still be on screen while submitting (no drop back to username/password form)
      expect(find.byKey(const Key('login_otp_field')), findsOneWidget);
      expect(find.byKey(const Key('login_username_field')), findsNothing);

      await tester.pumpAndSettle(); // Settle error response
      expect(find.text('Invalid 2FA Code'), findsOneWidget);
    });

    testWidgets('renders Forgot Password and Sign in with Email OTP buttons', (tester) async {
      await tester.pumpWidget(createTestWidget());

      expect(find.byKey(const Key('login_forgot_password_button')), findsOneWidget);
      expect(find.byKey(const Key('login_sign_in_with_otp_button')), findsOneWidget);
    });

    testWidgets('tapping Forgot Password button navigates to OtpEmailScreen in forgotPassword mode', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.tap(find.byKey(const Key('login_forgot_password_button')));
      await tester.pumpAndSettle();

      expect(find.text('Forgot Password'), findsWidgets);
      expect(find.byKey(const Key('otp_email_field')), findsOneWidget);
      expect(find.byKey(const Key('otp_send_code_button')), findsOneWidget);
    });

    testWidgets('tapping Sign in with Email OTP button navigates to OtpEmailScreen in login mode', (tester) async {
      await tester.pumpWidget(createTestWidget());

      await tester.tap(find.byKey(const Key('login_sign_in_with_otp_button')));
      await tester.pumpAndSettle();

      expect(find.text('Sign in with OTP'), findsWidgets);
      expect(find.byKey(const Key('otp_email_field')), findsOneWidget);
      expect(find.byKey(const Key('otp_send_code_button')), findsOneWidget);
    });
  });
}
