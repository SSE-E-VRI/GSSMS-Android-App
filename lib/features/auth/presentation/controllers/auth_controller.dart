import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/auth/session_cleanup.dart';
import 'package:gssms_mobile/core/config/app_config.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/storage/secure_storage_service.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/auth/data/auth_api_service.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';

// Top-level Providers
final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final secureStorageServiceProvider = Provider<ISecureStorageService>((ref) {
  return SecureStorageService();
});

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  final storage = ref.watch(secureStorageServiceProvider);

  // Circular reference breaking: Provide callback implementations
  late final AuthRepository repository;
  late final AuthApiService apiService;

  final dio = DioClient.create(
    config: config,
    tokenProvider: () => repository.currentAccessToken,
    refreshTokenHandler: () => repository.refreshToken(),
    onSessionExpired: () async {
      var cleared = true;
      try {
        await repository.expireSession();
      } catch (_) {
        cleared = false;
      }
      await ref
          .read(authControllerProvider.notifier)
          .handleSessionExpired(null, cleared);
    },
  );

  apiService = AuthApiService(dio);
  repository = AuthRepository(
    apiService: apiService,
    secureStorage: storage,
    cacheService: ref.watch(localCacheServiceProvider),
    onSessionRefreshed: (session, previous) {
      return ref
          .read(authControllerProvider.notifier)
          .onAccessTokenRefreshed(session, previous);
    },
  );
  return repository;
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(() {
  return AuthController();
});

class AuthController extends Notifier<AuthState> {
  String? _pendingPassword;

  // Boxed generation token so stale async completions can be ignored
  // (last-writer-wins would let a stale login overwrite a logout).
  Object _opGenBox = Object();

  @override
  AuthState build() {
    ref.onDispose(() {
      _pendingPassword = null;
    });
    return const AuthInitial();
  }

  IAuthRepository get _repository => ref.read(authRepositoryProvider);

  /// Restore existing session on app launch
  Future<void> restoreSession() async {
    final op = _opGenBox = Object();
    state = const AuthLoading('Restoring session...');
    try {
      final session = await _repository.restoreSession();
      if (!identical(op, _opGenBox)) return;
      if (session != null) {
        state = Authenticated(session);
      } else {
        state = const Unauthenticated();
      }
    } on GuestExpiredException catch (e) {
      if (!identical(op, _opGenBox)) return;
      state = AuthError(e.message, code: e.code);
    } catch (_) {
      if (!identical(op, _opGenBox)) return;
      state = const Unauthenticated();
    }
  }

  /// Perform initial login with username & password
  Future<void> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      state = const AuthError('Please enter username and password');
      return;
    }

    final op = _opGenBox = Object();
    state = const AuthLoading('Signing in...');
    try {
      final session = await _repository.login(
        username: username,
        password: password,
      );
      if (!identical(op, _opGenBox)) return;
      _pendingPassword = null;
      state = Authenticated(session);
    } on TwoFactorRequiredException {
      if (!identical(op, _opGenBox)) return;
      _pendingPassword = password;
      state = OtpRequired(username: username);
    } on AuthException catch (e) {
      if (!identical(op, _opGenBox)) return;
      _pendingPassword = null;
      state = AuthError(e.message, code: e.code);
    } catch (_) {
      if (!identical(op, _opGenBox)) return;
      _pendingPassword = null;
      state = const AuthError(
          'An unexpected authentication error occurred. Please try again.');
    }
  }

  /// Perform login with email and OTP code
  Future<void> loginWithOtp(String email, String otp) async {
    if (email.trim().isEmpty || otp.trim().isEmpty) {
      state = const AuthError('Please enter email and OTP code');
      return;
    }

    final op = _opGenBox = Object();
    state = const AuthLoading('Signing in with OTP...');
    try {
      final session = await _repository.loginWithOtp(
        email: email.trim().toLowerCase(),
        otp: otp.trim(),
      );
      if (!identical(op, _opGenBox)) return;
      _pendingPassword = null;
      state = Authenticated(session);
    } on UnauthorizedException catch (e) {
      // Stale login that a concurrent logout superseded — do not surface
      // "expired" to a user who is not logging in anymore.
      if (!identical(op, _opGenBox)) return;
      _pendingPassword = null;
      state = AuthError(e.message, code: e.code);
      rethrow;
    } on AuthException catch (e) {
      if (!identical(op, _opGenBox)) return;
      _pendingPassword = null;
      state = AuthError(e.message, code: e.code);
      rethrow;
    } catch (_) {
      if (!identical(op, _opGenBox)) return;
      _pendingPassword = null;
      const err = AuthError(
          'An unexpected authentication error occurred. Please try again.');
      state = err;
      throw const AuthException(
          'An unexpected authentication error occurred. Please try again.');
    }
  }

  /// Submit OTP code when challenge is requested
  Future<void> submitOtp(String otp) async {
    final currentState = state;
    final pendingPassword = _pendingPassword;
    if (currentState is! OtpRequired || pendingPassword == null) {
      state = const AuthError(
          'No active 2FA challenge found. Please sign in again.');
      return;
    }

    if (otp.trim().isEmpty) {
      state = OtpRequired(
        username: currentState.username,
        errorMessage: 'Please enter the 6-digit 2FA code',
      );
      return;
    }

    final op = _opGenBox = Object();
    // Retain OtpRequired view while verifying to prevent flickering
    state = OtpRequired(
      username: currentState.username,
      isSubmitting: true,
    );

    try {
      final session = await _repository.login(
        username: currentState.username,
        password: pendingPassword,
        otp: otp.trim(),
      );
      if (!identical(op, _opGenBox)) return;
      _pendingPassword = null;
      state = Authenticated(session);
    } on InvalidOtpException catch (e) {
      if (!identical(op, _opGenBox)) return;
      state = OtpRequired(
        username: currentState.username,
        errorMessage: e.message,
        isSubmitting: false,
      );
    } on AuthException catch (e) {
      if (!identical(op, _opGenBox)) return;
      _pendingPassword = null;
      state = AuthError(e.message, code: e.code);
    } catch (_) {
      if (!identical(op, _opGenBox)) return;
      _pendingPassword = null;
      state = const AuthError('Failed to verify 2FA code. Please try again.');
    }
  }

  /// Cancel OTP challenge and return to standard login
  void cancelOtp() {
    _pendingPassword = null;
    state = const Unauthenticated();
  }

  /// Clear error state
  void clearError() {
    if (state is AuthError) {
      state = const Unauthenticated();
    }
  }

  /// Silent token refresh: push the new JWT claims into UI gates, and drop
  /// cached operational data when identity, permissions, or org scope changed.
  Future<void> onAccessTokenRefreshed(
    UserSession session,
    UserSession? previous,
  ) async {
    final authChanged =
        previous != null && session.authorizationChangedFrom(previous);
    if (authChanged) {
      // Different user: full wipe. Same user with changed permissions/scope:
      // drop read caches only and keep the offline queue.
      final userChanged = session.userId != previous.userId;
      await clearOperationalSession(ref, preserveOfflineQueue: !userChanged);
    }
    if (state is Authenticated) {
      state = Authenticated(session);
    }
  }

  /// Triggered by interceptor when token refresh fails or guest access expires
  Future<void> handleSessionExpired(
      [String? reason, bool credentialsCleared = true]) async {
    _opGenBox = Object();
    _pendingPassword = null;
    try {
      ref.read(syncManagerProvider.notifier).invalidateSessionBoundWork();
    } catch (_) {}
    // Surface a failed wipe (contract of clearOperationalSession): the user
    // must be able to see that prior offline data may still be on the device.
    final wiped = await clearOperationalSession(ref, preserveOfflineQueue: true);
    state = AuthError(
      (reason ?? 'Your session has expired. Please log in again.') +
          (wiped && credentialsCleared
              ? ''
              : ' Saved credentials or offline data could not be cleared. Retry sign-out before sharing this device.'),
      code: wiped && credentialsCleared ? 'SESSION_EXPIRED' : 'SIGN_OUT_FAILED',
    );
  }

  /// Update profile picture in current session
  void updateSessionProfilePicture(String? newUrl) {
    if (state is Authenticated) {
      final currentSession = (state as Authenticated).session;
      final updatedSession = currentSession.copyWith(
        profilePicture: newUrl,
        clearProfilePicture: newUrl == null,
      );
      state = Authenticated(updatedSession);
    }
  }

  /// Log out user and clear stored credentials
  Future<void> logout() async {
    _opGenBox = Object();
    _pendingPassword = null;
    state = const AuthLoading('Signing out...');
    var credentialsCleared = true;
    try {
      await _repository.logout();
    } catch (_) {
      credentialsCleared = false;
    }
    final wiped = await clearOperationalSession(ref);
    state = credentialsCleared && wiped
        ? const Unauthenticated()
        : const AuthError(
            'Sign-out could not clear saved credentials or offline data. Please retry before sharing this device.',
            code: 'SIGN_OUT_FAILED');
  }
}
