import 'package:gssms_mobile/core/storage/secure_storage_service.dart';
import 'package:gssms_mobile/features/auth/data/auth_api_service.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';

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
}

class AuthRepository implements IAuthRepository {
  AuthRepository({
    required AuthApiService apiService,
    required ISecureStorageService secureStorage,
  })  : _apiService = apiService,
        _secureStorage = secureStorage;

  final AuthApiService _apiService;
  final ISecureStorageService _secureStorage;

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

      _currentAccessToken = tokens.accessToken;
      _currentSession = newSession;
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
    return _currentSession!;
  }

  @override
  Future<Map<String, dynamic>> setupTotp() => _apiService.setupTotp();

  @override
  Future<void> verifyTotp(String code) => _apiService.verifyTotp(code);

  @override
  Future<void> logout() async {
    _currentSession = null;
    _currentAccessToken = null;
    await _secureStorage.clearTokens();
  }
}
