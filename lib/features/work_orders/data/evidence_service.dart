import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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

/// Source reported to the server for a line attachment (audit §9.2 ME-01).
/// Never inferred from filename or timestamp; camera/gallery distinction is
/// chosen by the user flow that produced the capture.
enum EvidenceSource {
  camera('CAMERA'),
  gallery('GALLERY'),
  unknown('UNKNOWN');

  const EvidenceSource(this.code);
  final String code;

  static EvidenceSource fromCode(String? code) {
    final upper = code?.trim().toUpperCase();
    for (final s in EvidenceSource.values) {
      if (s.code == upper) return s;
    }
    return EvidenceSource.unknown;
  }
}

/// Bounded wait for the one fresh camera-photo location fix (ME-02/ME-03).
const Duration kEvidenceLocationTimeout = Duration(seconds: 8);

/// One fresh foreground location fix, stored as attachment columns — never
/// inside the image (the normalizer strips EXIF GPS, audit §9.1).
class EvidenceLocation {
  const EvidenceLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.recordedAt,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in meters (non-negative, finite).
  final double accuracyM;
  final DateTime recordedAt;

  /// ME-05 validation: all four fields required together (no partial
  /// location), coordinates finite and ranged, accuracy non-negative finite
  /// and a valid fix timestamp. Returns null instead of throwing so callers
  /// can simply keep the photo without GPS.
  static EvidenceLocation? validated(
    double? latitude,
    double? longitude,
    double? accuracyM,
    DateTime? recordedAt,
  ) {
    if (latitude == null ||
        longitude == null ||
        accuracyM == null ||
        recordedAt == null) {
      return null;
    }
    final valid = latitude.isFinite &&
        longitude.isFinite &&
        accuracyM.isFinite &&
        accuracyM >= 0 &&
        !recordedAt.isBefore(DateTime(2000)) &&
        !recordedAt.isAfter(DateTime.now().add(const Duration(minutes: 5)));
    if (!valid) return null;
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return EvidenceLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyM: accuracyM,
      recordedAt: recordedAt,
    );
  }
}

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
    this.source = EvidenceSource.unknown,
    this.capturedAt,
    this.location,
  });

  final String path;
  final int sizeBytes;
  final EvidenceKind kind;

  /// CAMERA for camera captures, GALLERY for gallery picks (ME-01).
  final EvidenceSource source;

  /// App-recorded capture-flow time — set for camera captures only; gallery
  /// picks carry no invented `captured_at` (ME-04).
  final DateTime? capturedAt;

  /// Fresh GPS fix taken at capture time for camera evidence only (ME-02).
  /// Null when the user denied the permission, location was off, or the fix
  /// timed out — the photo is kept without GPS (ME-03).
  final EvidenceLocation? location;

  String get fileName => path.split(Platform.pathSeparator).last;

  bool get isWithinSizeLimit => sizeBytes <= EvidenceLimits.maxBytes;

  /// Attaches capture-flow provenance. Skips location on non-camera sources
  /// even if a fix slipped in, and drops a partial/invalid location.
  EvidenceFile withCapture({
    required EvidenceSource source,
    DateTime? capturedAt,
    EvidenceLocation? location,
  }) {
    final isCamera = source == EvidenceSource.camera;
    return EvidenceFile(
      path: path,
      sizeBytes: sizeBytes,
      kind: kind,
      source: source,
      capturedAt: isCamera ? capturedAt : null,
      location: isCamera ? location : null,
    );
  }
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
    EvidenceLocationResolver? locationResolver,
  })  : _picker = picker ?? ImagePicker(),
        _locationResolver =
            locationResolver ?? _resolveCameraLocationFromDevice;

  final ImagePicker _picker;
  final Duration retentionPeriod;

  /// Supplies the one fresh foreground fix for camera captures. Injectable
  /// so tests can fake success/failure/timeout without device GPS.
  final EvidenceLocationResolver _locationResolver;

  static const String _evidenceDirName = 'gssms_evidence';

  /// Warning threshold for pending local evidence: 200 MB (MOBILE_APP_SSOT.md §12 / line 483).
  static const int warningThresholdBytes = 200 * 1024 * 1024;

  /// Captures from the camera (or gallery) and returns a durable copy.
  /// Returns null when the user cancels.
  ///
  /// Downscales to 1600px long edge at JPEG quality 80 and strips EXIF except
  /// orientation (baked into pixel data) per MOBILE_APP_SSOT.md §12.
  ///
  /// ME-01/ME-02/ME-04: the returned [EvidenceFile] carries the
  /// CAMERA/GALLERY distinction, an app-recorded capture-flow time for
  /// camera-only, and — when [captureLocation] is true — at most one fresh
  /// foreground GPS fix attempted near capture time. Gallery picks never get
  /// a fix or a `captured_at`. ME-03: permission denial, location disabled
  /// or the bounded timeout keep the photo, just without coordinates.
  Future<EvidenceFile?> capture({
    required EvidenceKind kind,
    ImageSource source = ImageSource.camera,
    bool captureLocation = false,
    int imageQuality = 80,
    double maxWidth = 1600,
    double maxHeight = 1600,
  }) async {
    final evidenceSource = source == ImageSource.camera
        ? EvidenceSource.camera
        : EvidenceSource.gallery;
    // App-recorded capture-flow time (not a shutter timestamp — ME-04).
    // Recorded before the camera hand-off so a slow camera session still
    // reflects when the capture was requested, and gallery picks get none.
    final capturedAt =
        evidenceSource == EvidenceSource.camera ? DateTime.now() : null;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    final stored = await persist(picked.path, kind: kind);

    EvidenceLocation? location;
    if (captureLocation && evidenceSource == EvidenceSource.camera) {
      location = await _locationResolver();
    }
    return stored.withCapture(
      source: evidenceSource,
      capturedAt: capturedAt,
      location: location,
    );
  }

  /// One fresh foreground fix with a bounded timeout (ME-02/ME-03):
  /// - asks for the runtime permission when needed,
  /// - refuses to substitute a last-known position or track in background,
  /// - returns null (photo kept without GPS) on denial, disabled services or
  ///   timeout.
  static Future<EvidenceLocation?> _resolveCameraLocationFromDevice() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Foreground runtime prompt — the only permission interaction here.
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!servicesEnabled) return null;

      // getCurrentPosition — never getLastKnownPosition: no cached fix may
      // stand in for a capture-time fix (ME-03).
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: kEvidenceLocationTimeout,
        ),
      ).timeout(kEvidenceLocationTimeout);

      return EvidenceLocation.validated(
        position.latitude,
        position.longitude,
        position.accuracy,
        position.timestamp.toUtc(),
      );
    } on TimeoutException {
      return null;
    } catch (_) {
      // Unsupported platform, plugin failure, etc. — photo without GPS.
      return null;
    }
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
    final dir =
        Directory('${docs.path}${Platform.pathSeparator}$_evidenceDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target =
        '${dir.path}${Platform.pathSeparator}${kind.name}_$stamp.jpg';

    try {
      final sourceLen = await source.length();
      // Picker maxWidth is best-effort: a full-res pick decodes to ~48 MB
      // RGBA. Refuse absurdly large files before paying for the read.
      const maxSourceBytes = 30 * 1024 * 1024;
      if (sourceLen > maxSourceBytes) {
        throw FileSystemException(
            'Photo is too large (${(sourceLen / 1048576).toStringAsFixed(1)} MB)',
            sourcePath);
      }
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
      throw FileSystemException(
          'Could not save proof photo: ${e.message}', target);
    }
  }

  /// Hook so tests can run the transform inline instead of paying for an
  /// isolate spawn per capture.
  @visibleForTesting
  Future<Uint8List?> Function(Uint8List bytes)? processImageOverride;

  Future<Uint8List?> _runImageProcessing(Uint8List rawBytes) async {
    final override = processImageOverride;
    if (override != null) return override(rawBytes);
    try {
      return await compute(normalizeEvidenceJpeg, rawBytes);
    } catch (_) {
      // OOM or isolate failure on huge images: caller falls back to copy.
      return null;
    }
  }

  /// Returns total bytes occupied by local evidence photos in the app's evidence directory.
  Future<int> getTotalPendingEvidenceBytes() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir =
          Directory('${docs.path}${Platform.pathSeparator}$_evidenceDirName');
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
      final dir =
          Directory('${docs.path}${Platform.pathSeparator}$_evidenceDirName');
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(maxAge ?? retentionPeriod);
      // Canonicalize once: callers pass File.absolute paths (see SyncManager)
      // and dir.list may yield symlinked/relative forms.
      final canonicalExcluded = excludePaths?.map((p) {
        try {
          return File(p).absolute.path;
        } catch (_) {
          return p;
        }
      }).toSet();
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          String canonicalEntity;
          try {
            canonicalEntity = File(entity.path).absolute.path;
          } catch (_) {
            canonicalEntity = entity.path;
          }
          if (canonicalExcluded != null &&
              (canonicalExcluded.contains(entity.path) ||
                  canonicalExcluded.contains(canonicalEntity))) {
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

/// Resolves the single camera-capture location fix (or null). Injectable so
/// tests can drive success/failure without device GPS.
typedef EvidenceLocationResolver = Future<EvidenceLocation?> Function();

final evidenceServiceProvider = Provider<EvidenceService>((ref) {
  return EvidenceService();
});
