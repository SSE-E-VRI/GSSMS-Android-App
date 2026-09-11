import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/profile_photo_cache.dart';
import '../theme/app_theme.dart';

/// Renders a circular profile avatar with photo, offline disk cache,
/// initials fallback, upload progress overlay, and camera badge.
class ProfileAvatar extends ConsumerStatefulWidget {
  const ProfileAvatar({
    super.key,
    this.userId,
    this.photoUrl,
    this.imageProvider,
    this.displayName = '',
    this.radius = 24.0,
    this.onCameraTap,
    this.isUploading = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  final int? userId;
  final String? photoUrl;
  final ImageProvider? imageProvider;
  final String displayName;
  final double radius;
  final VoidCallback? onCameraTap;
  final bool isUploading;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  ConsumerState<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<ProfileAvatar> {
  File? _cachedFile;

  @override
  void initState() {
    super.initState();
    _checkCacheAndFetch();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl ||
        oldWidget.userId != widget.userId ||
        oldWidget.imageProvider != widget.imageProvider) {
      _checkCacheAndFetch();
    }
  }

  Future<void> _checkCacheAndFetch() async {
    if (widget.photoUrl == null || widget.photoUrl!.isEmpty) {
      if (_cachedFile != null && mounted) {
        setState(() {
          _cachedFile = null;
        });
      }
      return;
    }

    final userId = widget.userId;
    if (userId == null) return;

    final cache = ref.read(profilePhotoCacheProvider);

    // 1. Check disk cache first for instant / offline display
    final cached =
        await cache.getCachedPhoto(userId, photoUrl: widget.photoUrl);
    if (cached != null && mounted) {
      setState(() {
        _cachedFile = cached;
      });
      return;
    }

    // 2. Fetch fresh copy if not in cache
    final downloaded = await cache.downloadAndCache(userId, widget.photoUrl!);
    if (downloaded != null && mounted) {
      setState(() {
        _cachedFile = downloaded;
      });
    }
  }

  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'U';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2 && widget.radius >= 20) {
      final first = parts[0].isNotEmpty ? parts[0][0] : '';
      final second = parts[1].isNotEmpty ? parts[1][0] : '';
      final combined = '$first$second'.toUpperCase();
      if (combined.isNotEmpty) return combined;
    }
    return trimmed[0].toUpperCase();
  }

  Widget _buildInitials() {
    final initials = _getInitials(widget.displayName);
    final bg = widget.backgroundColor ?? Theme.of(context).colorScheme.primary;
    final fg = widget.foregroundColor ?? Theme.of(context).colorScheme.onPrimary;
    final fontSize = (widget.radius * 0.85).clamp(11.0, 36.0);

    return Container(
      key: const Key('profile_avatar_initials'),
      width: widget.radius * 2,
      height: widget.radius * 2,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: fg,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    if (widget.imageProvider != null) {
      return Image(
        key: const Key('profile_avatar_image'),
        image: widget.imageProvider!,
        width: widget.radius * 2,
        height: widget.radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildInitials(),
      );
    }

    if (_cachedFile != null && _cachedFile!.existsSync()) {
      return Image.file(
        _cachedFile!,
        key: const Key('profile_avatar_image'),
        width: widget.radius * 2,
        height: widget.radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildInitials(),
      );
    }

    return _buildInitials();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: widget.radius * 2,
      height: widget.radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.backgroundColor ?? context.gssms.surfaceInset,
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildImageContent(),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        if (widget.isUploading)
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    key: Key('profile_avatar_uploading'),
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          ),
        if (widget.onCameraTap != null)
          Positioned(
            bottom: 0,
            right: 0,
            child: Material(
              key: const Key('profile_avatar_camera_badge'),
              color: AppTheme.primaryBlue,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.isUploading ? null : widget.onCameraTap,
                child: Padding(
                  padding: EdgeInsets.all((widget.radius * 0.16).clamp(4.0, 8.0)),
                  child: Icon(
                    Icons.camera_alt,
                    size: (widget.radius * 0.42).clamp(14.0, 22.0),
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
