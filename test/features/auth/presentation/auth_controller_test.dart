import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
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
          localCacheServiceProvider.overrideWithValue(InMemoryLocalCacheService()),
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

    group('offline queue retention', () {
      late InMemoryLocalCacheService cache;
      late ProviderContainer c;

      setUp(() async {
        cache = InMemoryLocalCacheService();
        await cache.setCacheOwnerUserId(7);
        await cache.saveOutboxCommands([
          OutboxCommand(
            idempotencyKey: 'k1',
            type: OutboxCommandType.submitLine,
            entityId: 1,
            payload: const {},
            createdAt: DateTime.utc(2026, 1, 1),
            ownerUserId: 7,
          ),
        ]);
        c = ProviderContainer(overrides: [
          authRepositoryProvider.overrideWithValue(mockRepository),
          localCacheServiceProvider.overrideWithValue(cache),
        ]);
      });

      tearDown(() => c.dispose());

      test('handleSessionExpired preserves the outbox and owner', () async {
        await c.read(authControllerProvider.notifier).handleSessionExpired();

        expect(await cache.getOutboxCommands(), hasLength(1));
        expect(await cache.getCacheOwnerUserId(), 7);
        expect((c.read(authControllerProvider) as AuthError).code,
            'SESSION_EXPIRED');
      });

      test('logout wipes the outbox', () async {
        when(() => mockRepository.logout()).thenAnswer((_) async {});

        await c.read(authControllerProvider.notifier).logout();

        expect(await cache.getOutboxCommands(), isEmpty);
        expect(await cache.getCacheOwnerUserId(), isNull);
      });

      test('onAccessTokenRefreshed keeps outbox for same user, wipes for different user', () async {
        const before = UserSession(
          accessToken: 'a',
          username: 'u',
          userId: 7,
          primaryRole: AuthRole.maintenanceStaff,
          roles: [AuthRole.maintenanceStaff],
          permissions: ['maintenance.view'],
        );
        final sameUser = before.copyWith(
            permissions: const ['maintenance.view', 'maintenance.edit']);
        final controller = c.read(authControllerProvider.notifier);

        await controller.onAccessTokenRefreshed(sameUser, before);
        expect(await cache.getOutboxCommands(), hasLength(1));

        final otherUser = UserSession(
          accessToken: 'b',
          username: 'v',
          userId: 8,
          primaryRole: AuthRole.maintenanceStaff,
          roles: const [AuthRole.maintenanceStaff],
          permissions: const ['maintenance.view'],
        );
        await controller.onAccessTokenRefreshed(otherUser, before);
        expect(await cache.getOutboxCommands(), isEmpty);
      });
    });

    test('failed logout exposes retryable cleanup error', () async {
      when(() => mockRepository.logout()).thenThrow(StateError('storage unavailable'));
      await container.read(authControllerProvider.notifier).logout();
      final state = container.read(authControllerProvider) as AuthError;
      expect(state.code, 'SIGN_OUT_FAILED');
      expect(state.message, contains('retry'));
    });

    test('onAccessTokenRefreshed updates Authenticated session claims', () async {
      when(
        () => mockRepository.login(
          username: 'maintenance_user',
          password: 'password123',
        ),
      ).thenAnswer((_) async => testSession);

      final controller = container.read(authControllerProvider.notifier);
      await controller.login('maintenance_user', 'password123');

      const refreshed = UserSession(
        accessToken: 'new_access_token',
        username: 'maintenance_user',
        userId: 7,
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view', 'maintenance.edit'],
      );

      await controller.onAccessTokenRefreshed(refreshed, testSession);

      final state = container.read(authControllerProvider);
      expect(state, isA<Authenticated>());
      expect((state as Authenticated).session.permissions, contains('maintenance.edit'));
      expect(state.session.accessToken, 'new_access_token');
    });
  });
}
