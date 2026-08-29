import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstract interface for secure credential storage.
abstract class ISecureStorageService {
  Future<String?> getRefreshToken();
  Future<void> saveRefreshToken(String token);
  Future<void> clearTokens();
}

/// Implementation using FlutterSecureStorage.
class SecureStorageService implements ISecureStorageService {
  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
            );

  final FlutterSecureStorage _storage;
  static const _refreshTokenKey = 'gssms_refresh_token';

  @override
  Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: _refreshTokenKey);
    } catch (_) {
      // If KeyStore or decryption fails on Android 12-14, safely reset and return null
      try {
        await _storage.delete(key: _refreshTokenKey);
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<void> saveRefreshToken(String token) async {
    try {
      await _storage.write(key: _refreshTokenKey, value: token);
    } catch (_) {
      try {
        await _storage.deleteAll();
        await _storage.write(key: _refreshTokenKey, value: token);
      } catch (_) {}
    }
  }

  @override
  Future<void> clearTokens() async {
    try {
      await _storage.delete(key: _refreshTokenKey);
    } catch (_) {
      try {
        await _storage.deleteAll();
      } catch (_) {}
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
