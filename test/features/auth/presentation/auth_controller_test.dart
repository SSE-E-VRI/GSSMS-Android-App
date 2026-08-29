import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  group('AuthController', () {
    late MockAuthRepository mockRepository;
    late ProviderContainer container;

    const testSession = UserSession(
      accessToken: 'dummy_access_token',
      username: 'maintenance_user',
      primaryRole: AuthRole.maintenanceStaff,
      roles: [AuthRole.maintenanceStaff],
      permissions: ['maintenance.view'],
    );

    setUp(() {
      mockRepository = MockAuthRepository();
      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockRepository),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is AuthInitial', () {
      final state = container.read(authControllerProvider);
      expect(state, isA<AuthInitial>());
    });

    test('login success sets Authenticated state', () async {
      when(
        () => mockRepository.login(
          username: 'maintenance_user',
          password: 'password123',
        ),
      ).thenAnswer((_) async => testSession);

      final controller = container.read(authControllerProvider.notifier);
      await controller.login('maintenance_user', 'password123');

      final state = container.read(authControllerProvider);
      expect(state, isA<Authenticated>());
      expect((state as Authenticated).session.username, 'maintenance_user');
    });

    test('login with 2FA requirement sets OtpRequired state and excludes password from props and toString', () async {
      when(
        () => mockRepository.login(
          username: 'admin_user',
          password: 'secret_password',
        ),
      ).thenThrow(const TwoFactorRequiredException());

      final controller = container.read(authControllerProvider.notifier);
      await controller.login('admin_user', 'secret_password');

      final state = container.read(authControllerProvider);
      expect(state, isA<OtpRequired>());

      final otpState = state as OtpRequired;
      expect(otpState.username, 'admin_user');
      // Verify security boundary: password is never in state props or string representations
      expect(otpState.props.contains('secret_password'), isFalse);
      expect(otpState.toString().contains('secret_password'), isFalse);
    });

    test('submitOtp success sets Authenticated state without state drop', () async {
      when(
        () => mockRepository.login(
          username: 'admin_user',
          password: 'secret_password',
        ),
      ).thenThrow(const TwoFactorRequiredException());

      when(
        () => mockRepository.login(
          username: 'admin_user',
          password: 'secret_password',
          otp: '123456',
        ),
      ).thenAnswer((_) async => testSession);

      final controller = container.read(authControllerProvider.notifier);
      await controller.login('admin_user', 'secret_password');
      await controller.submitOtp('123456');

      final state = container.read(authControllerProvider);
      expect(state, isA<Authenticated>());
    });

    test('login with unknown exception maps to sanitized generic message without leaking internals', () async {
      when(
        () => mockRepository.login(
          username: 'error_user',
          password: 'password123',
        ),
      ).thenThrow(Exception('Internal database socket timeout at 192.168.1.100'));

      final controller = container.read(authControllerProvider.notifier);
      await controller.login('error_user', 'password123');

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthError>());
      final errorState = state as AuthError;
      expect(errorState.message, 'An unexpected authentication error occurred. Please try again.');
      expect(errorState.message.contains('192.168.1.100'), isFalse);
    });

    test('restoreSession restores Authenticated when session available', () async {
      when(() => mockRepository.restoreSession()).thenAnswer((_) async => testSession);

      final controller = container.read(authControllerProvider.notifier);
      await controller.restoreSession();

      final state = container.read(authControllerProvider);
      expect(state, isA<Authenticated>());
    });

    test('logout clears session and sets Unauthenticated', () async {
      when(() => mockRepository.logout()).thenAnswer((_) async {});

      final controller = container.read(authControllerProvider.notifier);
      await controller.logout();

      final state = container.read(authControllerProvider);
      expect(state, isA<Unauthenticated>());
    });
  });
}
