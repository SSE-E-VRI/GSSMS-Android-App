import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/storage/secure_storage_service.dart';
import 'package:gssms_mobile/features/auth/data/auth_api_service.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_tokens.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthApiService extends Mock implements AuthApiService {}
class MockSecureStorageService extends Mock implements ISecureStorageService {}
class MockLocalCacheService extends Mock implements ILocalCacheService {}

void main() {
  group('AuthRepository Unit Tests', () {
    late MockAuthApiService mockApiService;
    late MockSecureStorageService mockSecureStorage;
    late MockLocalCacheService mockCache;
    late AuthRepository repository;

    const dummyJwt = 'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VybmFtZSI6InRlc3RfdXNlciIsInJvbGUiOiJNQUlOVEVOQU5DRV9TVEFGRiIsInJvbGVzIjpbIk1BSU5URU5BTkNFX1NUQUZGIl0sInBlcm1pc3Npb25zIjpbIm1haW50ZW5hbmNlLnZpZXciXX0.';

    setUp(() {
      mockApiService = MockAuthApiService();
      mockSecureStorage = MockSecureStorageService();
      mockCache = MockLocalCacheService();
      when(() => mockCache.clearAllCache()).thenAnswer((_) async {});
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

    test('refreshToken clears cache when permissions or scope change', () async {
      String unsignedJwt(Map<String, dynamic> claims) {
        String enc(String raw) =>
            base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
        return '${enc('{"alg":"none","typ":"JWT"}')}.${enc(jsonEncode(claims))}.';
      }

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

      verify(() => mockCache.clearAllCache()).called(1);
      expect(repository.currentSession?.depotId, 99);
      expect(repository.currentSession?.permissions, ['maintenance.view']);
    });
  });
}
