import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';

/// Ensures gallery/photo-library read access before invoking the image
/// picker with `ImageSource.gallery`. A Riverpod-provided service (not a
/// free function) so widget tests can override it the same way they
/// already override `evidenceServiceProvider`, instead of hitting the real
/// permission_handler platform channel (unmocked in tests).
///
/// image_picker's own Android implementation only ever requests the CAMERA
/// permission itself — it never requests READ_MEDIA_IMAGES or
/// READ_EXTERNAL_STORAGE for a gallery pick. That's fine on devices with
/// Google's modern Photo Picker, which needs no permission at all, but OEM
/// builds without it (common on Chinese-market Android, e.g. Funtouch OS)
/// fall back to the legacy gallery intent, which does need the runtime
/// permission — and since nothing in image_picker ever prompts for it, the
/// OS silently blocks access instead of ever showing the consent dialog,
/// which is what surfaces to the user as a generic "permission error".
class GalleryPermissionService {
  const GalleryPermissionService();

  /// Requests both `Permission.photos` (READ_MEDIA_IMAGES, API 33+) and
  /// `Permission.storage` (READ_EXTERNAL_STORAGE, API <33) unconditionally.
  /// That's safe: permission_handler resolves whichever one doesn't apply
  /// to the running OS version as already-granted without ever prompting
  /// for it (it only adds a permission to the native request when the OS
  /// version matches AND the manifest declares it — ours declares
  /// READ_EXTERNAL_STORAGE with maxSdkVersion="32", so it's simply absent
  /// from the installed package, and therefore a no-op, on API 33+
  /// devices).
  Future<bool> request(BuildContext context) async {
    final photos = await Permission.photos.request();
    final storage = await Permission.storage.request();
    if (photos.isGranted || photos.isLimited || storage.isGranted) {
      return true;
    }
    if (!context.mounted) return false;
    if (photos.isPermanentlyDenied || storage.isPermanentlyDenied) {
      final openSettings = await showConfirmationDialog(
        context,
        title: 'Photo access needed',
        message:
            'GSSMS needs permission to access your photos. Allow it in Settings to choose a photo from your gallery.',
        confirmLabel: 'Open Settings',
      );
      if (openSettings) await openAppSettings();
      return false;
    }
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo access was denied.')),
    );
    return false;
  }
}

final galleryPermissionServiceProvider =
    Provider<GalleryPermissionService>((ref) => const GalleryPermissionService());
