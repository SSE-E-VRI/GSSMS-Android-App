import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// The kind/category of evidence photo being captured.
enum EvidenceKind {
  proof('PROOF'),
  before('BEFORE'),
  during('DURING'),
  after('AFTER');

  const EvidenceKind(this.code);
  final String code;

  static EvidenceKind fromCode(String? code) {
    if (code == null) return EvidenceKind.proof;
    final upper = code.trim().toUpperCase();
    for (final k in EvidenceKind.values) {
      if (k.code == upper) return k;
    }
    return EvidenceKind.proof;
  }
}

/// Long edge, in pixels, that a stored evidence photo is scaled down to.
const int kEvidenceMaxEdge = 1600;

/// JPEG quality used for the re-encode.
const int kEvidenceJpegQuality = 80;

/// Bakes EXIF orientation into pixels, strips every other EXIF tag (GPS
/// included — MOBILE_APP_SSOT.md §12 keeps location in columns, never in the
/// image), scales the long edge to [kEvidenceMaxEdge] and re-encodes as JPEG.
///
/// Returns null when the bytes cannot be decoded, so the caller can fall back
/// to storing the original.
///
/// Top-level and synchronous so it can be handed to `compute`.
Uint8List? normalizeEvidenceJpeg(Uint8List rawBytes) {
  final decoded = img.decodeImage(rawBytes);
  if (decoded == null) return null;

  final oriented = img.bakeOrientation(decoded);

  img.Image resized = oriented;
  final maxEdge =
      oriented.width > oriented.height ? oriented.width : oriented.height;
  if (maxEdge > kEvidenceMaxEdge) {
    if (oriented.width >= oriented.height) {
      resized = img.copyResize(oriented, width: kEvidenceMaxEdge);
    } else {
      resized = img.copyResize(oriented, height: kEvidenceMaxEdge);
    }
  }

  return img.encodeJpg(resized, quality: kEvidenceJpegQuality);
}

/// Constraints enforced by the backend's `validate_jpeg` on
/// `MaintenanceRecord.proof_of_execution` and `LineAttachment.image`.
class EvidenceLimits {
  const EvidenceLimits._();

  /// The server rejects anything that is not `image/jpeg`.
  static const String requiredMimeType = 'image/jpeg';

  /// Server-side maximum is 5 MB.
  static const int maxBytes = 5 * 1024 * 1024;
}

/// A captured photo, already copied somewhere durable.
class EvidenceFile {
  const EvidenceFile({
    required this.path,
    required this.sizeBytes,
    required this.kind,
  });

  final String path;
  final int sizeBytes;
  final EvidenceKind kind;

  String get fileName => path.split(Platform.pathSeparator).last;

  bool get isWithinSizeLimit => sizeBytes <= EvidenceLimits.maxBytes;
}

/// Captures proof-of-execution and line-scoped photos and keeps them somewhere
/// the outbox can still find them later.
///
/// The picker hands back a file in a OS cache directory that may be reclaimed
/// at any time. A queued upload can outlive that, so every capture is copied
/// into the app's documents directory and referenced from there.
class EvidenceService {
  EvidenceService({
    ImagePicker? picker,
    this.retentionPeriod = const Duration(hours: 48),
  }) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final Duration retentionPeriod;

  static const String _evidenceDirName = 'gssms_evidence';

  /// Warning threshold for pending local evidence: 200 MB (MOBILE_APP_SSOT.md §12 / line 483).
  static const int warningThresholdBytes = 200 * 1024 * 1024;

  /// Captures from the camera (or gallery) and returns a durable copy.
  /// Returns null when the user cancels.
  ///
  /// Downscales to 1600px long edge at JPEG quality 80 and strips EXIF except
  /// orientation (baked into pixel data) per MOBILE_APP_SSOT.md §12.
  Future<EvidenceFile?> capture({
    required EvidenceKind kind,
    ImageSource source = ImageSource.camera,
    int imageQuality = 80,
    double maxWidth = 1600,
    double maxHeight = 1600,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    return persist(picked.path, kind: kind);
  }

  /// Copies and normalizes [sourcePath] into the app's evidence directory:
  /// - Bakes EXIF orientation into pixels so orientation is preserved.
  /// - Strips all other EXIF (GPS, device metadata).
  /// - Scales long edge to at most 1600px.
  /// - Re-encodes as JPEG at quality 80.
  ///
  /// The durable copy survives the OS clearing its caches.
  Future<EvidenceFile> persist(
    String sourcePath, {
    required EvidenceKind kind,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Source photo not found', sourcePath);
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$_evidenceDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target = '${dir.path}${Platform.pathSeparator}${kind.name}_$stamp.jpg';

    try {
      final rawBytes = await source.readAsBytes();

      // decode/bake/resize/encode are pure Dart and would otherwise run on the
      // UI isolate, freezing the checklist for the whole of a multi-hundred-ms
      // encode — on the interaction a technician repeats most. The picker's
      // maxWidth/maxHeight is best-effort per platform, so an unresized
      // full-resolution pick can also mean a ~48 MB RGBA decode; neither
      // belongs on the main isolate.
      final processedBytes = await _runImageProcessing(rawBytes);

      if (processedBytes != null) {
        final targetFile = File(target);
        await targetFile.writeAsBytes(processedBytes);
        return EvidenceFile(
          path: targetFile.path,
          sizeBytes: processedBytes.length,
          kind: kind,
        );
      } else {
        // Fallback to direct copy if image decode fails
        final copied = await source.copy(target);
        return EvidenceFile(
          path: copied.path,
          sizeBytes: await copied.length(),
          kind: kind,
        );
      }
    } on FileSystemException catch (e) {
      throw FileSystemException('Could not save proof photo: ${e.message}', target);
    }
  }

  /// Hook so tests can run the transform inline instead of paying for an
  /// isolate spawn per capture.
  @visibleForTesting
  Future<Uint8List?> Function(Uint8List bytes)? processImageOverride;

  Future<Uint8List?> _runImageProcessing(Uint8List rawBytes) {
    final override = processImageOverride;
    if (override != null) return override(rawBytes);
    return compute(normalizeEvidenceJpeg, rawBytes);
  }

  /// Returns total bytes occupied by local evidence photos in the app's evidence directory.
  Future<int> getTotalPendingEvidenceBytes() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}$_evidenceDirName');
      if (!await dir.exists()) return 0;
      int total = 0;
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Returns true if local evidence storage is at or above the 200 MB warning cap.
  Future<bool> isStorageNearCap() async {
    final total = await getTotalPendingEvidenceBytes();
    return total >= warningThresholdBytes;
  }

  /// Removes a stored evidence file once its upload has been accepted.
  Future<void> discard(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Deletes local evidence copies older than [maxAge] (defaults to
  /// [retentionPeriod], 48h). Files still referenced by the outbox
  /// ([excludePaths]) are never deleted, so a long-offline queued photo
  /// cannot be removed before its upload succeeds.
  Future<void> cleanupExpiredEvidence({
    Duration? maxAge,
    Set<String>? excludePaths,
  }) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}$_evidenceDirName');
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(maxAge ?? retentionPeriod);
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          if (excludePaths != null && excludePaths.contains(entity.path)) {
            continue;
          }
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
}

final evidenceServiceProvider = Provider<EvidenceService>((ref) {
  return EvidenceService();
});
