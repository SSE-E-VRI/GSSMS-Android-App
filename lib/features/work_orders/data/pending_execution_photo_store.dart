import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// A Breakdown execution photo captured on the phone and not yet uploaded.
/// It stays local until Save Progress or Sign & Submit uploads it.
class PendingExecutionPhoto {
  const PendingExecutionPhoto({required this.kind, required this.localPath});

  /// 'BEFORE' | 'AFTER'
  final String kind;
  final String localPath;
}

/// Durable index of [PendingExecutionPhoto]s, one SharedPreferences entry
/// per Job Work.
///
/// Each photo records the user who took it, so a Job Work reassigned on a
/// shared phone never shows or uploads the previous technician's photos
/// under the new user's name. Their photos are kept, not deleted.
///
/// [allReferencedPaths] lets the evidence retention sweep skip these files:
/// they are not in the sync outbox, and deleting them would silently lose
/// photos the technician has not saved yet.
class PendingExecutionPhotoStore {
  const PendingExecutionPhotoStore();

  static const String keyPrefix = 'complaint_execution_pending_photos_';

  static String keyFor(int workOrderId) => '$keyPrefix$workOrderId';

  /// This user's pending photos for [workOrderId] whose file still exists.
  /// Entries saved before owners were recorded have none and are adopted
  /// by whoever opens the Job Work next.
  Future<List<PendingExecutionPhoto>> load(
    int workOrderId, {
    required int? ownerUserId,
  }) async {
    final photos = <PendingExecutionPhoto>[];
    for (final entry in await _entries(keyFor(workOrderId))) {
      final owner = entry['ownerUserId'];
      if (owner != null && owner != ownerUserId) continue;
      final kind = entry['kind'];
      final localPath = entry['localPath'];
      if (kind is! String || localPath is! String) continue;
      if (!await File(localPath).exists()) continue;
      photos.add(PendingExecutionPhoto(kind: kind, localPath: localPath));
    }
    return photos;
  }

  /// Replaces this user's pending photos for [workOrderId] with [photos],
  /// keeping any other user's entries untouched.
  Future<void> save(
    int workOrderId,
    List<PendingExecutionPhoto> photos, {
    required int? ownerUserId,
  }) async {
    final key = keyFor(workOrderId);
    final others = (await _entries(key)).where((entry) {
      final owner = entry['ownerUserId'];
      return owner != null && owner != ownerUserId;
    });
    final next = [
      ...others,
      for (final photo in photos)
        {
          'kind': photo.kind,
          'localPath': photo.localPath,
          if (ownerUserId != null) 'ownerUserId': ownerUserId,
        },
    ];
    final prefs = await SharedPreferences.getInstance();
    if (next.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(next));
    }
  }

  /// Every local file referenced by any Job Work's pending photos, for any
  /// user.
  static Future<Set<String>> allReferencedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = <String>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(keyPrefix)) continue;
      for (final entry in _decode(prefs.getString(key))) {
        final localPath = entry['localPath'];
        if (localPath is String && localPath.isNotEmpty) paths.add(localPath);
      }
    }
    return paths;
  }

  static Future<List<Map<String, dynamic>>> _entries(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(key));
  }

  static List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map) Map<String, dynamic>.from(entry),
      ];
    } catch (_) {
      return const [];
    }
  }
}
