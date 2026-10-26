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
  /// Legacy ownerless entries are held back (see [legacy]); their files are
  /// kept.
  Future<List<PendingExecutionPhoto>> load(
    int workOrderId, {
    required int? ownerUserId,
  }) async {
    final photos = <PendingExecutionPhoto>[];
    for (final entry in await _entries(keyFor(workOrderId))) {
      final owner = entry['ownerUserId'];
      if (ownerUserId == null || owner != ownerUserId) continue;
      final kind = entry['kind'];
      final localPath = entry['localPath'];
      if (kind is! String || localPath is! String) continue;
      if (!await File(localPath).exists()) continue;
      photos.add(PendingExecutionPhoto(kind: kind, localPath: localPath));
    }
    return photos;
  }

  /// Replaces this user's pending photos for [workOrderId] with [photos],
  /// keeping any other user's entries untouched. Without a signed-in user
  /// nothing is written, so no new ownerless entries are ever created.
  Future<void> save(
    int workOrderId,
    List<PendingExecutionPhoto> photos, {
    required int? ownerUserId,
  }) async {
    if (ownerUserId == null) return;
    final key = keyFor(workOrderId);
    final others = (await _entries(key))
        .where((entry) => entry['ownerUserId'] != ownerUserId);
    await _write(key, [
      ...others,
      for (final photo in photos)
        {
          'kind': photo.kind,
          'localPath': photo.localPath,
          'ownerUserId': ownerUserId,
        },
    ]);
  }

  /// Photos saved before owners were recorded (app 0.3.9 and earlier) whose
  /// file still exists. Nobody sees them until [claimLegacy] or
  /// [discardLegacy] is called for them.
  Future<List<PendingExecutionPhoto>> legacy(int workOrderId) async {
    final photos = <PendingExecutionPhoto>[];
    for (final entry in await _entries(keyFor(workOrderId))) {
      if (entry['ownerUserId'] != null) continue;
      final kind = entry['kind'];
      final localPath = entry['localPath'];
      if (kind is! String || localPath is! String) continue;
      if (!await File(localPath).exists()) continue;
      photos.add(PendingExecutionPhoto(kind: kind, localPath: localPath));
    }
    return photos;
  }

  /// Gives every ownerless photo of [workOrderId] to [ownerUserId]. The
  /// caller must first confirm with the server that this user is the Job
  /// Work's assigned technician.
  Future<void> claimLegacy(int workOrderId, {required int ownerUserId}) async {
    final key = keyFor(workOrderId);
    await _write(key, [
      for (final entry in await _entries(key))
        if (entry['ownerUserId'] == null)
          {...entry, 'ownerUserId': ownerUserId}
        else
          entry,
    ]);
  }

  /// Drops every ownerless entry of [workOrderId] and returns the local
  /// paths it referenced, for the caller to delete.
  Future<List<String>> discardLegacy(int workOrderId) async {
    final key = keyFor(workOrderId);
    final entries = await _entries(key);
    await _write(key, [
      for (final entry in entries)
        if (entry['ownerUserId'] != null) entry,
    ]);
    return [
      for (final entry in entries)
        if (entry['ownerUserId'] == null && entry['localPath'] is String)
          entry['localPath'] as String,
    ];
  }

  static Future<void> _write(
      String key, List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    if (entries.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(entries));
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
