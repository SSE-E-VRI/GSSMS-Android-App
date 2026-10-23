import 'dart:async';
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
  })  : _apiService = apiService,
        _secureStorage = secureStorage,
        _cacheService = cacheService,
        _onSessionRefreshed = onSessionRefreshed;

  final AuthApiService _apiService;
  final ISecureStorageService _secureStorage;
  final ILocalCacheService? _cacheService;
  final AuthSessionRefreshed? _onSessionRefreshed;

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
        final session = UserSession.fromJwt(accessToken);
        final previous = _currentSession;
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await _secureStorage.saveRefreshToken(refreshToken);
        } else if (replaceRefresh) {
          await _secureStorage.clearTokens();
        }
        if (generation != _opGeneration) return null;
        await _bindCacheToSession(session, previous: previous);
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
      await logout();
      rethrow;
    } on UnauthorizedException {
      if (gen == _opGeneration) await expireSession();
      return null;
    } catch (_) {
      return null;
    }
  }

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
      } finally {
        // Keep the outbox and cache owner: only the same user signing in again
        // can reach (and sync) the queued work.
        await _cacheService?.clearReadCache();
      }
    });
  }
}
