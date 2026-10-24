import 'dart:async';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:gssms_mobile/core/storage/offline_session_store.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/storage/secure_storage_service.dart';
import 'package:gssms_mobile/features/auth/data/auth_api_service.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_profile.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';

typedef AuthSessionRefreshed = Future<void> Function(
  UserSession session,
  UserSession? previous,
);

abstract class IAuthRepository {
  UserSession? get currentSession;
  String? get currentAccessToken;

  Future<UserSession> login({
    required String username,
    required String password,
    String? otp,
  });

  Future<UserSession?> restoreSession();
  Future<String?> refreshToken();
  Future<void> logout();

  /// Session expired (refresh failed): drop credentials, in-memory session and
  /// stale read caches, but KEEP the offline outbox and cache owner so the
  /// same user can sign in again and sync queued work.
  Future<void> expireSession();

  // OTP / TOTP flows (§2.1) — exposed for Phase 2 UI
  Future<void> requestOtp({required String email, String purpose = 'LOGIN'});
  Future<UserSession> loginWithOtp(
      {required String email, required String otp});
  Future<void> resetPasswordWithOtp({
    required String email,
    required String otp,
    required String newPassword,
  });
  Future<Map<String, dynamic>> setupTotp();
  Future<void> verifyTotp(String code);

  Future<UserProfile> getProfile();
  Future<UserProfile> updateProfile({
    required String email,
    required String phoneNumber,
    required String designation,
  });
  Future<UserProfile> updateUserPhoto(String? filePath);
  Future<void> changePassword(String newPassword);
}

class AuthRepository implements IAuthRepository {
  AuthRepository({
    required AuthApiService apiService,
    required ISecureStorageService secureStorage,
    ILocalCacheService? cacheService,
    AuthSessionRefreshed? onSessionRefreshed,
    IOfflineSessionStore? offlineSessionStore,
    DateTime Function()? now,
  })  : _apiService = apiService,
        _secureStorage = secureStorage,
        _cacheService = cacheService,
        _onSessionRefreshed = onSessionRefreshed,
        _offlineSessionStore = offlineSessionStore,
        _now = now ?? DateTime.now;

  final AuthApiService _apiService;
  final ISecureStorageService _secureStorage;
  final ILocalCacheService? _cacheService;
  final AuthSessionRefreshed? _onSessionRefreshed;
  final IOfflineSessionStore? _offlineSessionStore;
  final DateTime Function() _now;
  static const offlineLifetime = Duration(hours: 8);

  UserSession? _currentSession;
  String? _currentAccessToken;

  @override
  UserSession? get currentSession => _currentSession;

  @override
  String? get currentAccessToken => _currentAccessToken;

  Future<String?>? _inFlightRefresh;
  int _opGeneration = 0;

  Future<void> _sessionTail = Future<void>.value();
  Future<T> _serializeSession<T>(Future<T> Function() action) async {
    final previous = _sessionTail;
    final done = Completer<void>();
    _sessionTail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<UserSession?> _commitSession(
          int generation, String accessToken, String? refreshToken,
          {bool replaceRefresh = false, bool notify = false}) =>
      _serializeSession(() async {
        if (generation != _opGeneration) return null;
        final verifiedAt = _now().toUtc();
        final session = UserSession.fromJwt(accessToken)
            .copyWith(offlineUntil: verifiedAt.add(offlineLifetime));
        final previous = _currentSession;
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await _secureStorage.saveRefreshToken(refreshToken);
        } else if (replaceRefresh) {
          await _secureStorage.clearTokens();
        }
        if (generation != _opGeneration) return null;
        await _bindCacheToSession(session, previous: previous);
        if (session.userId != null) {
          await _offlineSessionStore?.write(OfflineSessionSnapshot(
              accessToken, session.userId!, verifiedAt, verifiedAt));
        }
        if (generation != _opGeneration) return null;
        _currentAccessToken = accessToken;
        _currentSession = session;
        if (notify) await _onSessionRefreshed?.call(session, previous);
        return generation == _opGeneration ? session : null;
      });

  @override
  Future<UserSession> login({
    required String username,
    required String password,
    String? otp,
  }) async {
    final gen = ++_opGeneration;
    final tokens = await _apiService.login(
        username: username, password: password, otp: otp);
    final session = await _commitSession(
        gen, tokens.accessToken, tokens.refreshToken,
        replaceRefresh: true);
    if (session == null) {
      throw const UnauthorizedException(
          'Login superseded by another session operation.');
    }
    return session;
  }

  @override
  Future<UserSession?> restoreSession() async {
    final gen = _opGeneration;
    final storedRefreshToken = await _secureStorage.getRefreshToken();
    if (gen != _opGeneration) return null;
    if (storedRefreshToken == null || storedRefreshToken.isEmpty) return null;
    try {
      final tokens = await _apiService.refreshToken(storedRefreshToken);
      return await _commitSession(gen, tokens.accessToken, tokens.refreshToken);
    } on GuestExpiredException {
      if (gen != _opGeneration) return null;
      if (_currentSession?.isOffline == true) {
        await expireSession();
      } else {
        await logout();
      }
      rethrow;
    } on UnauthorizedException {
      if (gen == _opGeneration) await expireSession();
      return null;
    } on NetworkAuthException {
      return _restoreOfflineSession(gen);
    } on ForbiddenException {
      if (gen == _opGeneration) await expireSession();
      return null;
    } on AccountDisabledException {
      if (gen == _opGeneration) await expireSession();
      return null;
    } on InvalidCredentialsException {
      if (gen == _opGeneration) await expireSession();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<UserSession?> _restoreOfflineSession(int generation) =>
      _serializeSession(() async {
        if (generation != _opGeneration) return null;
        final snapshot = await _offlineSessionStore?.read();
        if (snapshot == null) return null;
        final now = _now().toUtc();
        final deadline = snapshot.verifiedAt.toUtc().add(offlineLifetime);
        if (now.isBefore(snapshot.verifiedAt.toUtc()) ||
            now.isBefore(snapshot.lastUsedAt.toUtc()) ||
            !now.isBefore(deadline)) {
          return null;
        }
        final owner = await _cacheService?.getCacheOwnerUserId();
        if (owner != snapshot.userId) return null;
        UserSession session;
        try {
          // Expired network tokens supply only their last verified identity.
          // They are never sent as credentials for this local-only session.
          final claims = JwtDecoder.decode(snapshot.accessToken);
          if (claims['exp'] is! num) return null;
          session = UserSession.fromClaims(claims, '')
              .copyWith(isOffline: true, offlineUntil: deadline);
        } catch (_) {
          return null;
        }
        final profileDeadline = session.validUntil?.toUtc();
        if (profileDeadline != null) {
          if (!now.isBefore(profileDeadline)) return null;
          if (profileDeadline.isBefore(deadline)) {
            session = session.copyWith(offlineUntil: profileDeadline);
          }
        }
        if (session.userId != owner ||
            !session.roles.contains(AuthRole.maintenanceStaff) ||
            !session.hasPermission('maintenance.view') ||
            !session.hasPermission('maintenance.edit')) {
          return null;
        }
        await _offlineSessionStore?.write(OfflineSessionSnapshot(
            snapshot.accessToken, snapshot.userId, snapshot.verifiedAt, now));
        if (generation != _opGeneration ||
            await _cacheService?.getCacheOwnerUserId() != owner) {
          return null;
        }
        _currentAccessToken = null;
        _currentSession = session;
        return session;
      });

  @override
  Future<String?> refreshToken() async {
    final existing = _inFlightRefresh;
    if (existing != null) return existing;

    final refreshFuture = _performRefreshToken();
    _inFlightRefresh = refreshFuture;
    try {
      return await refreshFuture;
    } finally {
      if (identical(_inFlightRefresh, refreshFuture)) _inFlightRefresh = null;
    }
  }

  Future<String?> _performRefreshToken() async {
    final gen = _opGeneration;
    final storedRefreshToken = await _secureStorage.getRefreshToken();
    if (gen != _opGeneration) return null;
    if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
      await expireSession();
      return null;
    }

    try {
      final tokens = await _apiService.refreshToken(storedRefreshToken);
      if (gen != _opGeneration) return null;
      final session = await _commitSession(
          gen, tokens.accessToken, tokens.refreshToken,
          notify: true);
      return session?.accessToken;
    } on UnauthorizedException {
      if (gen == _opGeneration) await expireSession();
      return null;
    } on GuestExpiredException {
      if (gen == _opGeneration) await logout();
      return null;
    } catch (_) {
      // Only explicit invalid credentials return null. A transient failure
      // must remain distinct so the interceptor preserves the saved session.
      rethrow;
    }
  }

  @override
  Future<void> requestOtp({required String email, String purpose = 'LOGIN'}) =>
      _apiService.requestOtp(email: email, purpose: purpose);

  @override
  Future<UserSession> loginWithOtp({
    required String email,
    required String otp,
  }) async {
    final gen = ++_opGeneration;
    final tokens = await _apiService.loginWithOtp(email: email, otp: otp);
    final session = await _commitSession(
        gen, tokens.accessToken, tokens.refreshToken,
        replaceRefresh: true);
    if (session == null) {
      throw const UnauthorizedException(
          'Login superseded by another session operation.');
    }
    return session;
  }

  @override
  Future<void> resetPasswordWithOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) =>
      _apiService.resetPasswordWithOtp(
        email: email,
        otp: otp,
        newPassword: newPassword,
      );

  @override
  Future<Map<String, dynamic>> setupTotp() => _apiService.setupTotp();

  @override
  Future<void> verifyTotp(String code) => _apiService.verifyTotp(code);

  int _requireUserId() {
    final id = _currentSession?.userId;
    if (id == null) {
      throw const AuthException('Unable to load profile: missing user id');
    }
    return id;
  }

  Future<void> _bindCacheToSession(
    UserSession session, {
    required UserSession? previous,
  }) async {
    final cache = _cacheService;
    if (cache == null) return;

    // Fail closed if a previous user's cache cannot be cleared.
    {
      final owner = await cache.getCacheOwnerUserId();
      final userChanged = session.userId != null && owner != session.userId;
      final authChanged =
          previous != null && session.authorizationChangedFrom(previous);

      if (userChanged) {
        await cache.clearAllCache();
      } else if (authChanged) {
        // Same user, changed permissions/scope: drop stale read caches but
        // keep the offline outbox.
        await cache.clearReadCache();
      }
      if (session.userId != null) {
        await cache.setCacheOwnerUserId(session.userId!);
      }
    }
  }

  @override
  Future<UserProfile> getProfile() async {
    final data = await _apiService.getUser(_requireUserId());
    return UserProfile.fromJson(data);
  }

  @override
  Future<UserProfile> updateProfile({
    required String email,
    required String phoneNumber,
    required String designation,
  }) async {
    final data = await _apiService.updateUser(_requireUserId(), {
      'email': email,
      'phone_number': phoneNumber,
      'designation': designation,
    });
    if (data.isEmpty) {
      return UserProfile(
        id: _requireUserId(),
        username: _currentSession?.username ?? '',
        email: email,
        phoneNumber: phoneNumber,
        designation: designation,
      );
    }
    return UserProfile.fromJson(data);
  }

  @override
  Future<UserProfile> updateUserPhoto(String? filePath) async {
    final data = await _apiService.updateUserPhoto(_requireUserId(), filePath);
    if (data.isEmpty) {
      final current = await getProfile();
      return current.copyWith(
        profilePicture: filePath == null ? null : current.profilePicture,
        clearProfilePicture: filePath == null,
      );
    }
    return UserProfile.fromJson(data);
  }

  @override
  Future<void> changePassword(String newPassword) async {
    await _apiService.updateUser(_requireUserId(), {'password': newPassword});
  }

  @override
  Future<void> logout() async {
    // Bump generation so an in-flight refresh/login can no longer
    // repopulate the session after this clear.
    _opGeneration++;
    _inFlightRefresh = null;
    _currentSession = null;
    _currentAccessToken = null;
    await _serializeSession(() async {
      try {
        await _secureStorage.clearTokens();
        await _offlineSessionStore?.clear();
      } finally {
        await _cacheService?.clearAllCache();
      }
    });
  }

  @override
  Future<void> expireSession() async {
    _opGeneration++;
    _inFlightRefresh = null;
    _currentSession = null;
    _currentAccessToken = null;
    await _serializeSession(() async {
      try {
        await _secureStorage.clearTokens();
        await _offlineSessionStore?.clear();
      } finally {
        // Keep the outbox and cache owner: only the same user signing in again
        // can reach (and sync) the queued work.
        await _cacheService?.clearReadCache();
      }
    });
  }
}
