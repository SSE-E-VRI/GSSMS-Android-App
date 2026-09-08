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

  // OTP / TOTP flows (§2.1) — exposed for Phase 2 UI
  Future<void> requestOtp(String username);
  Future<UserSession> verifyOtp({required String username, required String otp});
  Future<Map<String, dynamic>> setupTotp();
  Future<void> verifyTotp(String code);

  Future<UserProfile> getProfile();
  Future<UserProfile> updateProfile({
    required String email,
    required String phoneNumber,
    required String designation,
  });
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

  @override
  Future<UserSession> login({
    required String username,
    required String password,
    String? otp,
  }) async {
    final tokens = await _apiService.login(
      username: username,
      password: password,
      otp: otp,
    );

    final newSession = UserSession.fromJwt(tokens.accessToken);
    if (tokens.refreshToken != null && tokens.refreshToken!.isNotEmpty) {
      await _secureStorage.saveRefreshToken(tokens.refreshToken!);
    } else {
      await _secureStorage.clearTokens();
    }

    _currentAccessToken = tokens.accessToken;
    _currentSession = newSession;
    await _bindCacheToSession(newSession, previous: null);
    return _currentSession!;
  }

  @override
  Future<UserSession?> restoreSession() async {
    final storedRefreshToken = await _secureStorage.getRefreshToken();
    if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
      _currentSession = null;
      _currentAccessToken = null;
      return null;
    }

    try {
      final tokens = await _apiService.refreshToken(storedRefreshToken);
      final newSession = UserSession.fromJwt(tokens.accessToken);

      if (tokens.refreshToken != null && tokens.refreshToken != storedRefreshToken) {
        await _secureStorage.saveRefreshToken(tokens.refreshToken!);
      }

      _currentAccessToken = tokens.accessToken;
      _currentSession = newSession;
      await _bindCacheToSession(newSession, previous: null);
      return _currentSession;
    } on GuestExpiredException {
      await logout();
      rethrow;
    } on UnauthorizedException {
      await logout();
      return null;
    } catch (_) {
      // Network/IO transient failure: do NOT erase credentials or call logout.
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
      _inFlightRefresh = null;
    }
  }

  Future<String?> _performRefreshToken() async {
    final storedRefreshToken = await _secureStorage.getRefreshToken();
    if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
      await logout();
      return null;
    }

    try {
      final tokens = await _apiService.refreshToken(storedRefreshToken);
      final newSession = UserSession.fromJwt(tokens.accessToken);

      if (tokens.refreshToken != null && tokens.refreshToken != storedRefreshToken) {
        await _secureStorage.saveRefreshToken(tokens.refreshToken!);
      }

      final previous = _currentSession;
      _currentAccessToken = tokens.accessToken;
      _currentSession = newSession;
      await _bindCacheToSession(newSession, previous: previous);
      await _onSessionRefreshed?.call(newSession, previous);
      return _currentAccessToken;
    } on UnauthorizedException {
      await logout();
      return null;
    } on GuestExpiredException {
      await logout();
      return null;
    } catch (_) {
      // Transient error: do NOT logout. Return null so request retry can handle standard error.
      return null;
    }
  }

  @override
  Future<void> requestOtp(String username) => _apiService.requestOtp(username);

  @override
  Future<UserSession> verifyOtp({required String username, required String otp}) async {
    final tokens = await _apiService.verifyOtp(username: username, otp: otp);
    if (tokens.refreshToken != null && tokens.refreshToken!.isNotEmpty) {
      await _secureStorage.saveRefreshToken(tokens.refreshToken!);
    }
    _currentAccessToken = tokens.accessToken;
    _currentSession = UserSession.fromJwt(tokens.accessToken);
    await _bindCacheToSession(_currentSession!, previous: null);
    return _currentSession!;
  }

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

    final owner = await cache.getCacheOwnerUserId();
    final userChanged = session.userId != null &&
        owner != null &&
        owner != session.userId;
    final authChanged =
        previous != null && session.authorizationChangedFrom(previous);

    if (userChanged || authChanged) {
      await cache.clearAllCache();
    }
    if (session.userId != null) {
      await cache.setCacheOwnerUserId(session.userId!);
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
  Future<void> changePassword(String newPassword) async {
    await _apiService.updateUser(_requireUserId(), {'password': newPassword});
  }

  @override
  Future<void> logout() async {
    _currentSession = null;
    _currentAccessToken = null;
    await _secureStorage.clearTokens();
    try {
      await _cacheService?.clearAllCache();
    } catch (_) {}
  }
}
