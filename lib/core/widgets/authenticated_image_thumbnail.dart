import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';

/// Full-screen, pinch-to-zoom viewer for evidence photos.
class PhotoPreviewScaffold extends StatelessWidget {
  const PhotoPreviewScaffold({
    super.key,
    required this.title,
    required this.image,
  });

  final String title;
  final Widget? image;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: image ??
              const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 64,
              ),
        ),
      ),
    );
  }
}

/// Thumbnail for evidence photos requiring authenticated HTTP access.
///
/// Attaches the current session's Bearer token to media requests (since
/// backend media endpoints require authentication). Tapping opens a
/// full-screen pinch-to-zoom [PhotoPreviewScaffold].
class AuthenticatedImageThumbnail extends ConsumerWidget {
  const AuthenticatedImageThumbnail({
    super.key,
    required this.url,
    this.width = 48,
    this.height = 48,
    this.previewTitle,
    this.tapKey,
  });

  final String? url;
  final double width;
  final double height;
  final String? previewTitle;
  final Key? tapKey;

  void _openPreview(
    BuildContext context,
    String imageUrl,
    Map<String, String>? headers,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoPreviewScaffold(
          title: previewTitle ?? 'Photo',
          image: Image.network(
            imageUrl,
            headers: headers,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token =
        sessionFromAuth(ref.watch(authControllerProvider))?.accessToken;
    final headers =
        token == null ? null : <String, String>{'Authorization': 'Bearer $token'};
    final hasUrl = url != null && url!.trim().isNotEmpty;

    return InkWell(
      key: tapKey,
      borderRadius: BorderRadius.circular(GssmsRadius.r4),
      onTap: hasUrl ? () => _openPreview(context, url!.trim(), headers) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GssmsRadius.r4),
        child: SizedBox(
          width: width,
          height: height,
          child: hasUrl
              ? Image.network(
                  url!.trim(),
                  headers: headers,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) =>
                      progress == null
                          ? child
                          : const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                  errorBuilder: (context, error, stack) => Container(
                    color: context.gssms.surfaceInset,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      size: 20,
                    ),
                  ),
                )
              : Container(
                  color: context.gssms.surfaceInset,
                  child: const Icon(
                    Icons.image_outlined,
                    size: 20,
                  ),
                ),
        ),
      ),
    );
  }
}
