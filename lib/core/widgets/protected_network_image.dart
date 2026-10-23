import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/config/app_config.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';

/// Only the configured backend origin may receive session credentials.
Uri? trustedMediaUri(String value, AppConfig config) {
  try {
    final base = Uri.parse(config.baseUrl);
    final uri = base.resolve(value.trim());
    if (value.trim().isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.scheme != base.scheme ||
        uri.host != base.host ||
        uri.port != base.port ||
        (uri.scheme != 'https' && !(config.isDev && uri.scheme == 'http'))) {
      return null;
    }
    return uri;
  } catch (_) {
    return null;
  }
}

/// Authenticated native image loader. Redirects are rejected, including redirects
/// to subdomains. Cache identity includes the session token to isolate users.
@immutable
class ProtectedMediaImage extends ImageProvider<ProtectedMediaImage> {
  const ProtectedMediaImage(this.uri, this.token);
  final Uri uri;
  final String? token;
  @override
  Future<ProtectedMediaImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
          ProtectedMediaImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async =>
      decode(await ui.ImmutableBuffer.fromUint8List(await loadBytes()));

  @visibleForTesting
  Future<Uint8List> loadBytes() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      if (token != null && token!.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('Photo unavailable');
      }
      const limit = 30 * 1024 * 1024;
      if (response.contentLength > limit) {
        throw const HttpException('Photo too large');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > limit) {
          throw const HttpException('Photo too large');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ProtectedMediaImage && other.uri == uri && other.token == token;
  @override
  int get hashCode => Object.hash(uri, token);
}

class ProtectedNetworkImage extends ConsumerWidget {
  const ProtectedNetworkImage(this.url,
      {super.key,
      this.headers,
      this.fit,
      this.cacheWidth,
      this.errorBuilder,
      this.loadingBuilder});
  final String url;
  // Kept for existing attachment APIs. Credentials are always read from the
  // current session instead of trusting captured headers from an old screen.
  final Map<String, String>? headers;
  final BoxFit? fit;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final uri = trustedMediaUri(url, config);
    if (uri == null) {
      return errorBuilder?.call(
              context, const FormatException('Untrusted photo origin'), null) ??
          const Icon(Icons.broken_image_outlined);
    }
    final token =
        sessionFromAuth(ref.watch(authControllerProvider))?.accessToken;
    return Image(
        image: ResizeImage.resizeIfNeeded(
            cacheWidth, null, ProtectedMediaImage(uri, token)),
        fit: fit,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder);
  }
}
