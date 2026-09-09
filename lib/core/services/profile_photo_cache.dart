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
///
/// Cache entries are keyed on **both** the user id and the photo URL, not the
/// user id alone. Django appends a uniquifying suffix whenever an upload would
/// collide, so a replaced photo always arrives under a new URL; keying on the
/// URL means a photo changed on the web (or by an admin) invalidates the
/// device's copy instead of being masked by it forever.
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
  static const List<String> _extensions = ['jpg', 'png', 'jpeg'];

  /// Tag used for a photo cached from a local pick, before the server has
  /// given it a URL.
  static const String _localTag = 'local';

  /// FNV-1a over the URL. Deterministic across runs and platforms, which
  /// `String.hashCode` is not guaranteed to be.
  static String _tagFor(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) return _localTag;
    var hash = 0x811c9dc5;
    for (final unit in photoUrl.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  // File operations here are deliberately synchronous. getCachedPhoto runs on
  // the widget-render path, and `testWidgets` drives that inside a FakeAsync
  // zone where real stream-based directory I/O never completes. The files are
  // a handful of small avatars, so the sync cost is negligible.
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

  String _pathFor(Directory dir, int userId, String tag, String ext) =>
      '${dir.path}${Platform.pathSeparator}profile_${userId}_$tag.$ext';

  /// Returns the cached file for this user *and this photo URL*, if present.
  ///
  /// A different URL is a miss by design — the caller then re-downloads and the
  /// stale entry is purged on write.
  Future<File?> getCachedPhoto(int userId, {String? photoUrl}) async {
    try {
      final dir = await _getDirectory();
      final tag = _tagFor(photoUrl);
      for (final ext in _extensions) {
        final file = File(_pathFor(dir, userId, tag, ext));
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
  Future<File> savePhotoBytes(
    int userId,
    List<int> bytes, {
    String ext = 'jpg',
    String? photoUrl,
  }) async {
    final dir = await _getDirectory();
    final cleanExt = ext.replaceAll('.', '');
    final tag = _tagFor(photoUrl);
    await _purgeOtherEntries(dir, userId, keepTag: tag, keepExt: cleanExt);
    final file = File(_pathFor(dir, userId, tag, cleanExt));
    file.writeAsBytesSync(bytes, flush: true);
    return file;
  }

  /// Copy an existing local file into the profile cache.
  Future<File> cacheLocalFile(
    int userId,
    String sourcePath, {
    String? photoUrl,
  }) async {
    final source = File(sourcePath);
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
    final dir = await _getDirectory();
    final cleanExt = ext.replaceAll('.', '');
    final tag = _tagFor(photoUrl);
    await _purgeOtherEntries(dir, userId, keepTag: tag, keepExt: cleanExt);
    final file = File(_pathFor(dir, userId, tag, cleanExt));
    source.copySync(file.path);
    return file;
  }

  /// Removes every other cached entry for this user — other extensions and,
  /// critically, entries for superseded photo URLs — so a replaced photo can
  /// never leave a stale file behind that wins a later lookup.
  Future<void> _purgeOtherEntries(
    Directory dir,
    int userId, {
    required String keepTag,
    required String keepExt,
  }) async {
    final keepPath = _pathFor(dir, userId, keepTag, keepExt);
    try {
      for (final entity in _entriesFor(dir, userId)) {
        if (entity.path == keepPath) continue;
        try {
          entity.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Every cached file belonging to [userId], listed before any deletion so we
  /// never mutate a directory mid-enumeration.
  List<File> _entriesFor(Directory dir, int userId) {
    final prefix = 'profile_${userId}_';
    return dir
        .listSync(recursive: false)
        .whereType<File>()
        .where((f) => f.path.split(Platform.pathSeparator).last.startsWith(prefix))
        .toList();
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
        return await savePhotoBytes(
          userId,
          response.data!,
          ext: ext,
          photoUrl: photoUrl,
        );
      }
    } catch (e) {
      debugPrint('ProfilePhotoCache: download failed ($e)');
    }
    return null;
  }

  /// Delete every cached profile photo for a user, whatever URL it came from.
  Future<void> clearCachedPhoto(int userId) async {
    try {
      final dir = await _getDirectory();
      for (final entity in _entriesFor(dir, userId)) {
        try {
          entity.deleteSync();
        } catch (_) {}
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
