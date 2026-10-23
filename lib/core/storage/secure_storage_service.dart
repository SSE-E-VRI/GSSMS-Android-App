import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Temporary credential I/O failure; callers must preserve the saved session.
class CredentialStorageException implements Exception {
  const CredentialStorageException();
  @override
  String toString() =>
      'Saved credentials are temporarily unavailable. Unlock the device and retry.';
}

/// Abstract interface for secure credential storage.
abstract class ISecureStorageService {
  Future<String?> getRefreshToken();
  Future<void> saveRefreshToken(String token);
  Future<void> clearTokens();
}

/// Implementation using FlutterSecureStorage.
class SecureStorageService implements ISecureStorageService {
  /// Android storage options for the default [FlutterSecureStorage].
  ///
  /// `resetOnError` must stay false: with true, flutter_secure_storage wipes
  /// all stored data when a read/decryption fails. Transient Keystore failures
  /// (right after boot, while the device is locked) would then erase a
  /// possibly-valid refresh token. Reads fail with an exception instead, which
  /// [getRefreshToken] maps to [CredentialStorageException] so the session is
  /// preserved and the caller can retry.
  static const AndroidOptions defaultAndroidOptions =
      AndroidOptions(resetOnError: false);

  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // v11 dropped the encryptedSharedPreferences flag: AES-GCM +
              // RSA OAEP key wrapping is now the only (and default) Android
              // storage mode, so there's nothing left to opt into here.
              aOptions: defaultAndroidOptions,
            );

  final FlutterSecureStorage _storage;
  static const _refreshTokenKey = 'gssms_refresh_token';
  static const _revokedKey = 'gssms_credentials_revoked';

  @override
  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_revokedKey) == true) return null;
    try {
      return await _storage.read(key: _refreshTokenKey);
    } catch (_) {
      // KeyStore/decryption can fail transiently (e.g. right after boot while
      // the device is locked). Deleting here would irrecoverably destroy a
      // possibly-valid session. Distinguish a read failure from an absent
      // token so refresh does not turn a temporary storage error into logout.
      throw const CredentialStorageException();
    }
  }

  Future<void> _setRevoked(bool revoked) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_revokedKey, revoked)) {
      throw StateError(
          'Could not persist credential safety state. Please retry.');
    }
  }

  @override
  Future<void> saveRefreshToken(String token) async {
    await _setRevoked(true);
    try {
      await _storage.write(key: _refreshTokenKey, value: token);
    } catch (_) {
      await _storage.delete(key: _refreshTokenKey);
      await _storage.write(key: _refreshTokenKey, value: token);
    }
    await _setRevoked(false);
  }

  @override
  Future<void> clearTokens() async {
    // Independent marker blocks stale credentials after failed Keystore deletion.
    // Even when the marker cannot be saved, still attempt physical deletion.
    try {
      await _setRevoked(true);
    } catch (_) {}
    try {
      await _storage.delete(key: _refreshTokenKey);
    } catch (_) {
      await _storage.deleteAll();
    }
  }
}

/// In-memory mock implementation for testing and environments without hardware storage.
class InMemorySecureStorageService implements ISecureStorageService {
  final Map<String, String> _storage = {};
  static const _refreshTokenKey = 'gssms_refresh_token';

  @override
  Future<String?> getRefreshToken() async {
    return _storage[_refreshTokenKey];
  }

  @override
  Future<void> saveRefreshToken(String token) async {
    _storage[_refreshTokenKey] = token;
  }

  @override
  Future<void> clearTokens() async {
    _storage.remove(_refreshTokenKey);
  }
}
