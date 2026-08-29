import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Constraints enforced by the backend's `validate_jpeg` on
/// `MaintenanceRecord.proof_of_execution`.
class EvidenceLimits {
  const EvidenceLimits._();

  /// The server rejects anything that is not `image/jpeg`.
  static const String requiredMimeType = 'image/jpeg';

  /// Server-side maximum is 5 MB.
  static const int maxBytes = 5 * 1024 * 1024;
}

/// A captured photo, already copied somewhere durable.
class EvidenceFile {
  const EvidenceFile({required this.path, required this.sizeBytes});

  final String path;
  final int sizeBytes;

  String get fileName => path.split(Platform.pathSeparator).last;

  bool get isWithinSizeLimit => sizeBytes <= EvidenceLimits.maxBytes;
}

/// Captures proof-of-execution photos and keeps them somewhere the outbox can
/// still find them later.
///
/// The picker hands back a file in a OS cache directory that may be reclaimed
/// at any time. A queued upload can outlive that, so every capture is copied
/// into the app's documents directory and referenced from there.
class EvidenceService {
  EvidenceService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const String _evidenceDirName = 'gssms_evidence';

  /// Captures from the camera (or gallery) and returns a durable copy.
  /// Returns null when the user cancels.
  ///
  /// Images are requested as JPEG at a bounded size because the server accepts
  /// only JPEG under 5 MB, and a modern phone camera easily exceeds that.
  Future<EvidenceFile?> capture({
    ImageSource source = ImageSource.camera,
    int imageQuality = 85,
    double maxWidth = 1920,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    return persist(picked.path);
  }

  /// Copies [sourcePath] into the app's evidence directory so a queued upload
  /// survives the OS clearing its caches.
  Future<EvidenceFile> persist(String sourcePath) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$_evidenceDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target = '${dir.path}${Platform.pathSeparator}proof_$stamp.jpg';
    final copied = await File(sourcePath).copy(target);

    return EvidenceFile(path: copied.path, sizeBytes: await copied.length());
  }

  /// Removes a stored evidence file once its upload has been accepted.
  Future<void> discard(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

final evidenceServiceProvider = Provider<EvidenceService>((ref) {
  return EvidenceService();
});
