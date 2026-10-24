import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gssms_mobile/core/storage/secure_storage_service.dart';

class OfflineSessionSnapshot {
  const OfflineSessionSnapshot(
      this.accessToken, this.userId, this.verifiedAt, this.lastUsedAt);
  final String accessToken;
  final int userId;
  final DateTime verifiedAt;
  final DateTime lastUsedAt;
}

abstract class IOfflineSessionStore {
  Future<OfflineSessionSnapshot?> read();
  Future<void> write(OfflineSessionSnapshot snapshot);
  Future<void> clear();
}

/// Last server-verified identity, protected by platform credential storage.
class SecureOfflineSessionStore implements IOfflineSessionStore {
  SecureOfflineSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
                aOptions: SecureStorageService.defaultAndroidOptions);
  final FlutterSecureStorage _storage;
  static const _key = 'gssms_offline_session_v1';

  @override
  Future<OfflineSessionSnapshot?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      return OfflineSessionSnapshot(
          value['access_token'] as String,
          value['user_id'] as int,
          DateTime.parse(value['verified_at'] as String),
          DateTime.parse(value['last_used_at'] as String));
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> write(OfflineSessionSnapshot snapshot) => _storage.write(
      key: _key,
      value: jsonEncode({
        'access_token': snapshot.accessToken,
        'user_id': snapshot.userId,
        'verified_at': snapshot.verifiedAt.toUtc().toIso8601String(),
        'last_used_at': snapshot.lastUsedAt.toUtc().toIso8601String(),
      }));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
