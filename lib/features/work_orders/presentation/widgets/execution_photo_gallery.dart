import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/widgets/protected_network_image.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';

/// Read-only evidence for one asset group or execution scope.
class ExecutionPhotoGallery extends StatelessWidget {
  const ExecutionPhotoGallery({
    super.key,
    required this.photos,
    required this.maxPerKind,
    this.galleryPhotos,
    this.headers,
  });

  final List<ExecutionPhoto> photos;
  final int maxPerKind;
  final List<ExecutionPhoto>? galleryPhotos;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...photos.where((p) => p.isBefore),
      ...photos.where((p) => p.isAfter),
    ];
    final gallery = <ExecutionPhoto>{...?galleryPhotos, ...photos};
    final viewerPhotos = [
      ...gallery.where((p) => p.isBefore),
      ...gallery.where((p) => p.isAfter),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final kind in const ['BEFORE', 'AFTER']) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '${kind == 'BEFORE' ? 'Before' : 'After'} photos '
              '(${ordered.where((p) => p.kind?.toUpperCase() == kind).length}/$maxPerKind)',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          if (!ordered.any((p) => p.kind?.toUpperCase() == kind))
            Text('No $kind photos yet.'),
          GridView.builder(
            key: Key('execution_photo_grid_$kind'),
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemCount:
                ordered.where((p) => p.kind?.toUpperCase() == kind).length,
            itemBuilder: (context, index) {
              final photo = ordered
                  .where((p) => p.kind?.toUpperCase() == kind)
                  .elementAt(index);
              return InkWell(
                key: Key('preview_exec_photo_${photo.id}'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => _GalleryViewer(
                    photos: viewerPhotos,
                    initialIndex: viewerPhotos.indexOf(photo),
                    headers: headers,
                  ),
                )),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox.expand(
                            child: _image(photo, headers, BoxFit.cover)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Photo #${photo.id}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

Widget _image(ExecutionPhoto photo, Map<String, String>? headers, BoxFit fit) {
  if ((photo.url ?? '').trim().isEmpty) {
    return const Center(child: Icon(Icons.image_not_supported_outlined));
  }
  return ProtectedNetworkImage(
    photo.url!,
    headers: headers,
    fit: fit,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : const Center(child: CircularProgressIndicator()),
    errorBuilder: (context, error, stack) => const Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40),
    ),
  );
}

class _GalleryViewer extends StatefulWidget {
  const _GalleryViewer(
      {required this.photos, required this.initialIndex, this.headers});

  final List<ExecutionPhoto> photos;
  final int initialIndex;
  final Map<String, String>? headers;

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title:
            Text('${photo.isBefore ? 'Before' : 'After'} · Photo #${photo.id}'),
      ),
      body: PageView.builder(
        key: const Key('execution_photo_pager'),
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
              child:
                  _image(widget.photos[index], widget.headers, BoxFit.contain)),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
              '${_index + 1} / ${widget.photos.length} · Swipe left or right',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}
