import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';

final profilePhotoCacheProvider = Provider<ProfilePhotoCache>((ref) {
  final config = ref.watch(appConfigProvider);
  return ProfilePhotoCache(
    baseUrl: config.baseUrl,
  );
});

/// Handles disk caching of user profile pictures so they render offline.
class ProfilePhotoCache {
  ProfilePhotoCache({
    required this.baseUrl,
    Dio? dio,
    Directory? storageDir,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 4),
                sendTimeout: const Duration(seconds: 4),
              ),
            ),
        _storageDir = storageDir;

  final String baseUrl;
  final Dio _dio;
  final Directory? _storageDir;

  static const String _subDirName = 'gssms_profiles';

  Future<Directory> _getDirectory() async {
    final storage = _storageDir;
    if (storage != null) {
      if (!storage.existsSync()) {
        storage.createSync(recursive: true);
      }
      return storage;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$_subDirName');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Get the cached file for a user if it exists on disk.
  Future<File?> getCachedPhoto(int userId) async {
    try {
      final dir = await _getDirectory();
      for (final ext in ['jpg', 'png', 'jpeg']) {
        final file = File('${dir.path}${Platform.pathSeparator}profile_$userId.$ext');
        if (file.existsSync() && file.lengthSync() > 0) {
          return file;
        }
      }
    } catch (e) {
      debugPrint('ProfilePhotoCache: error getting cached photo: $e');
    }
    return null;
  }

  /// Save raw image bytes to disk for a user.
  Future<File> savePhotoBytes(int userId, List<int> bytes, {String ext = 'jpg'}) async {
    final dir = await _getDirectory();
    final cleanExt = ext.replaceAll('.', '');
    await _clearOtherExtensions(dir, userId, keepExt: cleanExt);
    final file = File('${dir.path}${Platform.pathSeparator}profile_$userId.$cleanExt');
    file.writeAsBytesSync(bytes, flush: true);
    return file;
  }

  /// Copy an existing local file into the profile cache.
  Future<File> cacheLocalFile(int userId, String sourcePath) async {
    final source = File(sourcePath);
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
    final dir = await _getDirectory();
    final cleanExt = ext.replaceAll('.', '');
    await _clearOtherExtensions(dir, userId, keepExt: cleanExt);
    final file = File('${dir.path}${Platform.pathSeparator}profile_$userId.$cleanExt');
    source.copySync(file.path);
    return file;
  }

  /// Remove cached variants with a different extension so a replaced photo
  /// (jpg -> png) can never leave a stale file that wins the lookup order.
  Future<void> _clearOtherExtensions(Directory dir, int userId, {required String keepExt}) async {
    for (final ext in ['jpg', 'png', 'jpeg']) {
      if (ext == keepExt) continue;
      try {
        final file = File('${dir.path}${Platform.pathSeparator}profile_$userId.$ext');
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  /// Download from network and cache locally.
  Future<File?> downloadAndCache(int userId, String photoUrl) async {
    try {
      final fullUrl = resolveUrl(photoUrl);
      final response = await _dio.get<List<int>>(
        fullUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      // Never cache error pages: a 403/404 HTML body must not poison the
      // cache as a fake photo.
      final contentType =
          response.headers.value('content-type')?.toLowerCase() ?? '';
      if (!contentType.startsWith('image/')) {
        debugPrint('ProfilePhotoCache: refusing non-image response ($contentType)');
        return null;
      }
      if (response.data != null && response.data!.isNotEmpty) {
        final ext = photoUrl.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
        return await savePhotoBytes(userId, response.data!, ext: ext);
      }
    } catch (e) {
      debugPrint('ProfilePhotoCache: download failed ($e)');
    }
    return null;
  }

  /// Delete cached profile photo for a user.
  Future<void> clearCachedPhoto(int userId) async {
    try {
      final dir = await _getDirectory();
      for (final ext in ['jpg', 'png', 'jpeg']) {
        final file = File('${dir.path}${Platform.pathSeparator}profile_$userId.$ext');
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    } catch (e) {
      debugPrint('ProfilePhotoCache: error clearing cached photo: $e');
    }
  }

  /// Resolve absolute URL against [baseUrl] if relative.
  String resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final normalizedPath = url.startsWith('/') ? url : '/$url';
    return '$normalizedBase$normalizedPath';
  }
}
