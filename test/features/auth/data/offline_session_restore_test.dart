import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/storage/offline_session_store.dart';
import 'package:gssms_mobile/core/storage/secure_storage_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/features/auth/data/auth_api_service.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_tokens.dart';
import 'package:mocktail/mocktail.dart';

class _Api extends Mock implements AuthApiService {}

class _Credentials extends Mock implements ISecureStorageService {}

class _Snapshots implements IOfflineSessionStore {
  OfflineSessionSnapshot? value;
  @override
  Future<OfflineSessionSnapshot?> read() async => value;
  @override
  Future<void> write(OfflineSessionSnapshot snapshot) async {
    value = snapshot;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

String token(DateTime now,
    {String role = 'MAINTENANCE_STAFF', DateTime? validUntil}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none'})}.${encode({
        'user_id': 1,
        'username': 'test_technician',
        'role': role,
        'roles': [role],
        'permissions': ['maintenance.view', 'maintenance.edit'],
        'exp':
            now.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
        if (validUntil != null) 'valid_until': validUntil.toIso8601String(),
      })}.test';
}

void main() {
  late _Api api;
  late _Credentials credentials;
  late _Snapshots snapshots;
  late InMemoryLocalCacheService cache;
  late DateTime clock;
  late DateTime verified;
  AuthRepository repository() => AuthRepository(
      apiService: api,
      secureStorage: credentials,
      cacheService: cache,
      offlineSessionStore: snapshots,
      now: () => clock);

  setUp(() {
    clock = verified = DateTime.now().toUtc();
    api = _Api();
    credentials = _Credentials();
    snapshots = _Snapshots();
    cache = InMemoryLocalCacheService();
    when(() => credentials.getRefreshToken())
        .thenAnswer((_) async => 'test-refresh');
    when(() => credentials.saveRefreshToken(any())).thenAnswer((_) async {});
    when(() => credentials.clearTokens()).thenAnswer((_) async {});
    when(() => api.login(username: 'tech', password: 'test', otp: null))
        .thenAnswer((_) async => AuthTokens(
            accessToken: token(verified), refreshToken: 'test-refresh'));
    when(() => api.refreshToken(any()))
        .thenAnswer((_) async => throw const NetworkAuthException());
  });

  Future<void> signIn() async {
    await repository().login(username: 'tech', password: 'test');
  }

  test(
      'cold restore within eight hours uses owned identity without network token',
      () async {
    await signIn();
    clock = clock.add(const Duration(hours: 7, minutes: 59));
    final restarted = repository();
    final session = await restarted.restoreSession();
    expect(session?.isOffline, isTrue);
    expect(session?.userId, 1);
    expect(session?.accessToken, isEmpty);
    expect(restarted.currentAccessToken, isNull);
    expect(session?.offlineUntil, verified.add(const Duration(hours: 8)));
    expect(snapshots.value?.verifiedAt, verified,
        reason: 'offline use must not extend the shift');
  });

  test('eight-hour boundary denies restore', () async {
    await signIn();
    clock = clock.add(const Duration(hours: 8));
    expect(await repository().restoreSession(), isNull);
  });

  test('clock rollback after offline use denies restore', () async {
    await signIn();
    clock = clock.add(const Duration(hours: 2));
    expect(await repository().restoreSession(), isNotNull);
    clock = clock.subtract(const Duration(minutes: 1));
    expect(await repository().restoreSession(), isNull);
  });

  test('foreign cache owner or mismatched protected profile denies restore',
      () async {
    await signIn();
    await cache.setCacheOwnerUserId(2);
    expect(await repository().restoreSession(), isNull);
    await cache.setCacheOwnerUserId(1);
    final saved = snapshots.value!;
    snapshots.value = OfflineSessionSnapshot(
        saved.accessToken, 2, saved.verifiedAt, saved.lastUsedAt);
    expect(await repository().restoreSession(), isNull);
  });

  test('server refusal ends offline access but preserves owned queue',
      () async {
    await signIn();
    await cache.saveOutboxCommands([
      OutboxCommand(
          idempotencyKey: 'pending',
          type: OutboxCommandType.submitLine,
          entityId: 55,
          payload: const {'line_id': 1, 'value': '12.5'},
          ownerUserId: 1,
          createdAt: clock)
    ]);
    final restarted = repository();
    expect((await restarted.restoreSession())?.isOffline, isTrue);
    when(() => api.refreshToken(any()))
        .thenAnswer((_) async => throw const UnauthorizedException());
    expect(await restarted.restoreSession(), isNull);
    expect(restarted.currentSession, isNull);
    expect(snapshots.value, isNull);
    expect((await cache.getOutboxCommands()).single.payload['value'], '12.5');
    expect(await cache.getCacheOwnerUserId(), 1);
  });

  test('logout removes protected snapshot', () async {
    await signIn();
    await repository().logout();
    expect(snapshots.value, isNull);
    expect(await repository().restoreSession(), isNull);
  });

  test('server profile validity can shorten the eight-hour window', () async {
    when(() => api.login(username: 'tech', password: 'test', otp: null))
        .thenAnswer((_) async => AuthTokens(
            accessToken: token(verified,
                validUntil: verified.add(const Duration(hours: 1))),
            refreshToken: 'test-refresh'));
    await signIn();
    expect((await repository().restoreSession())?.offlineUntil,
        verified.add(const Duration(hours: 1)));
    clock = verified.add(const Duration(hours: 2));
    expect(await repository().restoreSession(), isNull);
  });
}
