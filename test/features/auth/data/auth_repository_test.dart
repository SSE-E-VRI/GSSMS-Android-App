import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/storage/secure_storage_service.dart';
import 'package:gssms_mobile/features/auth/data/auth_api_service.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_tokens.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthApiService extends Mock implements AuthApiService {}
class MockSecureStorageService extends Mock implements ISecureStorageService {}
class MockLocalCacheService extends Mock implements ILocalCacheService {}

String unsignedJwt(Map<String, dynamic> claims) {
  String enc(String raw) =>
      base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
  // exp far in the future (2100) — fromJwt fails closed without it.
  return '${enc('{"alg":"none","typ":"JWT"}')}.${enc(jsonEncode({
        'exp': 4102444800,
        ...claims,
      }))}.';
}

String userJwt(int userId, {List<String> permissions = const ['maintenance.view']}) =>
    unsignedJwt({
      'username': 'user_$userId',
      'user_id': userId,
      'role': 'DEPOT_USER',
      'roles': ['DEPOT_USER'],
      'permissions': permissions,
      'depot_id': 10,
    });

void main() {
  group('AuthRepository Unit Tests', () {
    late MockAuthApiService mockApiService;
    late MockSecureStorageService mockSecureStorage;
    late MockLocalCacheService mockCache;
    late AuthRepository repository;

    // JWT with user_id and a far-future `exp` (2100). M5 fail-closed:
    // UserSession.fromJwt throws UnauthorizedException when exp is missing.
    const dummyJwt = 'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VybmFtZSI6InRlc3RfdXNlciIsInJvbGUiOiJNQUlOVEVOQU5DRV9TVEFGRiIsInJvbGVzIjpbIk1BSU5URU5BTkNFX1NUQUZGIl0sInBlcm1pc3Npb25zIjpbIm1haW50ZW5hbmNlLnZpZXciXSwidXNlcl9pZCI6MSwiZXhwIjo0MTAyNDQ0ODAwfQ.';

    setUp(() {
      mockApiService = MockAuthApiService();
      mockSecureStorage = MockSecureStorageService();
      mockCache = MockLocalCacheService();
      when(() => mockCache.clearAllCache()).thenAnswer((_) async {});
      when(() => mockCache.clearReadCache()).thenAnswer((_) async {});
      when(() => mockCache.getCacheOwnerUserId()).thenAnswer((_) async => null);
      when(() => mockCache.setCacheOwnerUserId(any())).thenAnswer((_) async {});
      repository = AuthRepository(
        apiService: mockApiService,
        secureStorage: mockSecureStorage,
        cacheService: mockCache,
      );
    });

    test('login saves refresh token and initializes user session in memory', () async {
      when(
        () => mockApiService.login(
          username: 'test_user',
          password: 'password123',
        ),
      ).thenAnswer(
        (_) async => const AuthTokens(
          accessToken: dummyJwt,
          refreshToken: 'refresh_token_xyz',
        ),
      );

      when(() => mockSecureStorage.saveRefreshToken('refresh_token_xyz'))
          .thenAnswer((_) async {});

      final session = await repository.login(
        username: 'test_user',
        password: 'password123',
      );

      expect(session.username, 'test_user');
      expect(repository.currentAccessToken, dummyJwt);
      expect(repository.currentSession, session);
      verify(() => mockSecureStorage.saveRefreshToken('refresh_token_xyz')).called(1);
    });

    test('restoreSession restores session when refresh token exists in secure storage', () async {
      when(() => mockSecureStorage.getRefreshToken())
          .thenAnswer((_) async => 'stored_refresh_token');

      when(() => mockApiService.refreshToken('stored_refresh_token'))
          .thenAnswer((_) async => const AuthTokens(accessToken: dummyJwt));

      final session = await repository.restoreSession();

      expect(session, isNotNull);
      expect(session?.username, 'test_user');
      expect(repository.currentAccessToken, dummyJwt);
    });

    test('restoreSession returns null if no stored refresh token', () async {
      when(() => mockSecureStorage.getRefreshToken()).thenAnswer((_) async => null);

      final session = await repository.restoreSession();

      expect(session, isNull);
      expect(repository.currentAccessToken, isNull);
      expect(repository.currentSession, isNull);
    });

    test('restoreSession clears credentials and rethrows on GuestExpiredException', () async {
      when(() => mockSecureStorage.getRefreshToken())
          .thenAnswer((_) async => 'expired_guest_token');

      when(() => mockApiService.refreshToken('expired_guest_token'))
          .thenThrow(const GuestExpiredException('Demo access has expired.'));

      when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});

      await expectLater(
        repository.restoreSession(),
        throwsA(isA<GuestExpiredException>()),
      );

      verify(() => mockSecureStorage.clearTokens()).called(1);
      expect(repository.currentAccessToken, isNull);
      expect(repository.currentSession, isNull);
    });

    test('logout clears secure storage, cache, and nullifies in-memory session and token', () async {
      when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});

      await repository.logout();

      verify(() => mockSecureStorage.clearTokens()).called(1);
      verify(() => mockCache.clearAllCache()).called(1);
      expect(repository.currentAccessToken, isNull);
      expect(repository.currentSession, isNull);
    });

    test('getProfile throws when session has no user id', () async {
      expect(
        () => repository.getProfile(),
        throwsA(isA<AuthException>()),
      );
    });

    test('refreshToken drops read caches but keeps outbox when permissions or scope change', () async {
      final originalJwt = unsignedJwt({
        'username': 'test_user',
        'user_id': 1,
        'role': 'DEPOT_USER',
        'roles': ['DEPOT_USER'],
        'permissions': ['maintenance.view', 'maintenance.edit'],
        'depot_id': 10,
      });
      final narrowedJwt = unsignedJwt({
        'username': 'test_user',
        'user_id': 1,
        'role': 'DEPOT_USER',
        'roles': ['DEPOT_USER'],
        'permissions': ['maintenance.view'],
        'depot_id': 99,
      });

      when(() => mockApiService.login(
            username: 'test_user',
            password: 'password123',
          )).thenAnswer(
        (_) async => AuthTokens(accessToken: originalJwt, refreshToken: 'refresh'),
      );
      when(() => mockSecureStorage.saveRefreshToken('refresh'))
          .thenAnswer((_) async {});
      await repository.login(username: 'test_user', password: 'password123');

      when(() => mockSecureStorage.getRefreshToken())
          .thenAnswer((_) async => 'refresh');
      when(() => mockApiService.refreshToken('refresh'))
          .thenAnswer((_) async => AuthTokens(accessToken: narrowedJwt));
      when(() => mockCache.getCacheOwnerUserId()).thenAnswer((_) async => 1);

      await repository.refreshToken();

      // Initial login (null owner) wipes once; the same-user refresh must only
      // drop read caches so queued offline work survives.
      verify(() => mockCache.clearAllCache()).called(1);
      verify(() => mockCache.clearReadCache()).called(1);
      expect(repository.currentSession?.depotId, 99);
      expect(repository.currentSession?.permissions, ['maintenance.view']);
    });

    test('refreshToken wipes everything when the user id changes', () async {
      when(() => mockApiService.login(username: 'a', password: 'p'))
          .thenAnswer((_) async =>
              AuthTokens(accessToken: userJwt(1), refreshToken: 'refresh'));
      when(() => mockSecureStorage.saveRefreshToken('refresh'))
          .thenAnswer((_) async {});
      await repository.login(username: 'a', password: 'p');
      clearInteractions(mockCache);

      when(() => mockSecureStorage.getRefreshToken())
          .thenAnswer((_) async => 'refresh');
      when(() => mockApiService.refreshToken('refresh'))
          .thenAnswer((_) async => AuthTokens(accessToken: userJwt(2)));
      when(() => mockCache.getCacheOwnerUserId()).thenAnswer((_) async => 1);

      await repository.refreshToken();

      verify(() => mockCache.clearAllCache()).called(1);
      verifyNever(() => mockCache.clearReadCache());
      verify(() => mockCache.setCacheOwnerUserId(2)).called(1);
    });

    test('expireSession clears tokens and session, drops read cache only', () async {
      when(() => mockApiService.login(username: 'a', password: 'p'))
          .thenAnswer((_) async =>
              AuthTokens(accessToken: userJwt(1), refreshToken: 'refresh'));
      when(() => mockSecureStorage.saveRefreshToken('refresh'))
          .thenAnswer((_) async {});
      when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});
      await repository.login(username: 'a', password: 'p');
      clearInteractions(mockCache);
      clearInteractions(mockSecureStorage);

      await repository.expireSession();

      verify(() => mockSecureStorage.clearTokens()).called(1);
      verify(() => mockCache.clearReadCache()).called(1);
      verifyNever(() => mockCache.clearAllCache());
      verifyNever(() => mockCache.setCacheOwnerUserId(any()));
      expect(repository.currentSession, isNull);
      expect(repository.currentAccessToken, isNull);
    });

    test('expireSession still drops read cache if clearing tokens fails', () async {
      when(() => mockSecureStorage.clearTokens()).thenThrow(StateError('boom'));

      await expectLater(repository.expireSession(), throwsStateError);

      verify(() => mockCache.clearReadCache()).called(1);
      verifyNever(() => mockCache.clearAllCache());
    });

    test('restoreSession on UnauthorizedException expires session without full wipe', () async {
      when(() => mockSecureStorage.getRefreshToken())
          .thenAnswer((_) async => 'bad_refresh');
      when(() => mockApiService.refreshToken('bad_refresh'))
          .thenThrow(const UnauthorizedException('nope'));
      when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});

      final session = await repository.restoreSession();

      expect(session, isNull);
      verify(() => mockSecureStorage.clearTokens()).called(1);
      verify(() => mockCache.clearReadCache()).called(1);
      verifyNever(() => mockCache.clearAllCache());
    });

    test('restoreSession on GuestExpiredException still performs full wipe', () async {
      when(() => mockSecureStorage.getRefreshToken())
          .thenAnswer((_) async => 'guest');
      when(() => mockApiService.refreshToken('guest'))
          .thenThrow(const GuestExpiredException('Demo access has expired.'));
      when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});

      await expectLater(
          repository.restoreSession(), throwsA(isA<GuestExpiredException>()));

      verify(() => mockCache.clearAllCache()).called(1);
      verifyNever(() => mockCache.clearReadCache());
    });

    test('refreshToken with missing stored token expires session without full wipe', () async {
      when(() => mockSecureStorage.getRefreshToken()).thenAnswer((_) async => null);
      when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});

      expect(await repository.refreshToken(), isNull);

      verify(() => mockCache.clearReadCache()).called(1);
      verifyNever(() => mockCache.clearAllCache());
    });

    test('refreshToken on UnauthorizedException expires session without full wipe', () async {
      when(() => mockSecureStorage.getRefreshToken())
          .thenAnswer((_) async => 'bad');
      when(() => mockApiService.refreshToken('bad'))
          .thenThrow(const UnauthorizedException('nope'));
      when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});

      expect(await repository.refreshToken(), isNull);

      verify(() => mockCache.clearReadCache()).called(1);
      verifyNever(() => mockCache.clearAllCache());
    });

    test('different-user login after expiry wipes everything', () async {
      when(() => mockSecureStorage.saveRefreshToken(any()))
          .thenAnswer((_) async {});
      when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});
      when(() => mockCache.getCacheOwnerUserId()).thenAnswer((_) async => 1);
      when(() => mockApiService.login(username: 'b', password: 'p'))
          .thenAnswer((_) async =>
              AuthTokens(accessToken: userJwt(2), refreshToken: 'r2'));

      await repository.expireSession();
      clearInteractions(mockCache);
      when(() => mockCache.getCacheOwnerUserId()).thenAnswer((_) async => 1);
      when(() => mockCache.setCacheOwnerUserId(any())).thenAnswer((_) async {});
      await repository.login(username: 'b', password: 'p');

      verify(() => mockCache.clearAllCache()).called(1);
      verify(() => mockCache.setCacheOwnerUserId(2)).called(1);
    });

    test('same-user login after expiry keeps the cache', () async {
      when(() => mockSecureStorage.saveRefreshToken(any()))
          .thenAnswer((_) async {});
      when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});
      when(() => mockCache.getCacheOwnerUserId()).thenAnswer((_) async => 1);
      when(() => mockApiService.login(username: 'a', password: 'p'))
          .thenAnswer((_) async =>
              AuthTokens(accessToken: userJwt(1), refreshToken: 'r1'));

      await repository.expireSession();
      clearInteractions(mockCache);
      when(() => mockCache.getCacheOwnerUserId()).thenAnswer((_) async => 1);
      when(() => mockCache.setCacheOwnerUserId(any())).thenAnswer((_) async {});
      await repository.login(username: 'a', password: 'p');

      verifyNever(() => mockCache.clearAllCache());
      verifyNever(() => mockCache.clearReadCache());
    });

    group('with real LocalCacheService', () {
      late LocalCacheService realCache;
      late AuthRepository realRepo;

      OutboxCommand queued(int owner) => OutboxCommand(
            idempotencyKey: 'key-$owner',
            type: OutboxCommandType.submitLine,
            entityId: 5,
            payload: const {'v': 1},
            createdAt: DateTime.utc(2026, 1, 1),
            ownerUserId: owner,
          );

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        realCache = LocalCacheService(await SharedPreferences.getInstance());
        realRepo = AuthRepository(
          apiService: mockApiService,
          secureStorage: mockSecureStorage,
          cacheService: realCache,
        );
        when(() => mockSecureStorage.saveRefreshToken(any()))
            .thenAnswer((_) async {});
        when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});
        when(() => mockApiService.login(username: 'u7', password: 'p'))
            .thenAnswer((_) async =>
                AuthTokens(accessToken: userJwt(7), refreshToken: 'r7'));
        when(() => mockApiService.login(username: 'u8', password: 'p'))
            .thenAnswer((_) async =>
                AuthTokens(accessToken: userJwt(8), refreshToken: 'r8'));
      });

      test('queued command survives expiry + same-user login, not a different user', () async {
        await realRepo.login(username: 'u7', password: 'p');
        await realCache.saveOutboxCommands([queued(7)]);

        await realRepo.expireSession();
        expect(await realCache.getOutboxCommands(), hasLength(1));
        expect(await realCache.getCacheOwnerUserId(), 7);

        await realRepo.login(username: 'u7', password: 'p');
        expect(await realCache.getOutboxCommands(), hasLength(1));

        await realRepo.expireSession();
        await realRepo.login(username: 'u8', password: 'p');
        expect(await realCache.getOutboxCommands(), isEmpty);
        expect(await realCache.getCacheOwnerUserId(), 8);
      });

      test('explicit logout wipes the queued command', () async {
        await realRepo.login(username: 'u7', password: 'p');
        await realCache.saveOutboxCommands([queued(7)]);

        await realRepo.logout();

        expect(await realCache.getOutboxCommands(), isEmpty);
        expect(await realCache.getCacheOwnerUserId(), isNull);
      });
    });

    test('login started before a logout later persists nothing (H2)', () async {
      const tokens = AuthTokens(
        accessToken: dummyJwt,
        refreshToken: 'user_a_refresh',
      );
      when(
        () => mockApiService.login(
          username: 'test_user',
          password: 'password123',
        ),
      ).thenAnswer((_) async {
        // A concurrent logout(…) fires while the network call is finishing.
        await repository.logout();
        return tokens;
      });
      when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});
      when(() => mockSecureStorage.saveRefreshToken(any()))
          .thenAnswer((_) async {});

      await expectLater(
        repository.login(username: 'test_user', password: 'password123'),
        throwsA(isA<UnauthorizedException>()),
      );

      // The superseded login must not repopulate state or storage.
      verifyNever(() => mockSecureStorage.saveRefreshToken(any()));
      expect(repository.currentAccessToken, isNull);
      expect(repository.currentSession, isNull);
    });

    test('loginWithOtp started before a logout later persists nothing (H2)',
        () async {
      const tokens = AuthTokens(
        accessToken: dummyJwt,
        refreshToken: 'user_a_refresh',
      );
      when(
        () => mockApiService.loginWithOtp(
          email: 'a@example.com',
          otp: '123456',
        ),
      ).thenAnswer((_) async {
        await repository.logout();
        return tokens;
      });
      when(() => mockSecureStorage.clearTokens()).thenAnswer((_) async {});
      when(() => mockSecureStorage.saveRefreshToken(any()))
          .thenAnswer((_) async {});

      await expectLater(
        repository.loginWithOtp(email: 'a@example.com', otp: '123456'),
        throwsA(isA<UnauthorizedException>()),
      );

      verifyNever(() => mockSecureStorage.saveRefreshToken(any()));
      expect(repository.currentAccessToken, isNull);
      expect(repository.currentSession, isNull);
    });
  });
}
