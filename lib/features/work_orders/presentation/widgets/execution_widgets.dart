import 'package:gssms_mobile/core/widgets/authenticated_image_thumbnail.dart';
import 'package:gssms_mobile/core/widgets/protected_network_image.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_photo_gallery.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/pending_execution_photo_store.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';

export 'package:gssms_mobile/features/work_orders/data/pending_execution_photo_store.dart'
    show PendingExecutionPhoto;

/// Editable {parameter, value, unit} rows (max 50 server-side). Used by the
/// complaint and inspection execution forms — the server validates
/// non-blank parameter/value in one place regardless of caller.
class ParamRowsEditor extends StatefulWidget {
  const ParamRowsEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    this.enabled = true,
    this.readOnly = false,
    this.emptyText,
    this.parameterHint,
  });

  final List<Map<String, String>> initial;
  final ValueChanged<List<Map<String, String>>> onChanged;
  final bool enabled;

  /// Shows the rows without add/remove controls (a Job Work that can no
  /// longer be edited), as opposed to [enabled], which only greys them out
  /// while a save is running.
  final bool readOnly;

  /// Shown instead of the rows when there are none.
  final String? emptyText;

  /// Example shown in an empty Parameter field (e.g. "R-Y Voltage").
  final String? parameterHint;

  @override
  State<ParamRowsEditor> createState() => _ParamRowsEditorState();
}

class _ParamRowsEditorState extends State<ParamRowsEditor> {
  late List<TextEditingController> _params;
  late List<TextEditingController> _values;
  late List<TextEditingController> _units;

  @override
  void initState() {
    super.initState();
    _params = [];
    _values = [];
    _units = [];
    for (final row in widget.initial) {
      _params.add(TextEditingController(text: row['parameter'] ?? ''));
      _values.add(TextEditingController(text: row['value'] ?? ''));
      _units.add(TextEditingController(text: row['unit'] ?? ''));
    }
  }

  @override
  void dispose() {
    for (final c in [..._params, ..._values, ..._units]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(List.generate(
      _params.length,
      (i) => {
        'parameter': _params[i].text.trim(),
        'value': _values[i].text.trim(),
        'unit': _units[i].text.trim(),
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.enabled && !widget.readOnly;
    final empty = widget.emptyText;
    return Column(
      children: [
        if (_params.isEmpty && empty != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(empty,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: context.gssms.textSecondary)),
            ),
          ),
        for (var i = 0; i < _params.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == _params.length - 1 ? 0 : 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _params[i],
                    enabled: editable,
                    decoration: InputDecoration(
                      labelText: 'Parameter',
                      hintText: widget.parameterHint,
                      isDense: true,
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _values[i],
                    enabled: editable,
                    decoration: const InputDecoration(
                      labelText: 'Value',
                      isDense: true,
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _units[i],
                    enabled: editable,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      isDense: true,
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
                if (!widget.readOnly)
                  IconButton(
                    key: Key('remove_param_row_$i'),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Remove row',
                    onPressed: !editable
                        ? null
                        : () => setState(() {
                              _params[i].dispose();
                              _values[i].dispose();
                              _units[i].dispose();
                              _params.removeAt(i);
                              _values.removeAt(i);
                              _units.removeAt(i);
                              _emit();
                            }),
                  ),
              ],
            ),
          ),
        if (!widget.readOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('add_param_row_button'),
              onPressed: !editable || _params.length >= 50
                  ? null
                  : () => setState(() {
                        _params.add(TextEditingController());
                        _values.add(TextEditingController());
                        _units.add(TextEditingController());
                        _emit();
                      }),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add parameter'),
            ),
          ),
      ],
    );
  }
}

/// Read-only row of photos the inspector took when logging the inspection
/// (a point's own evidence, or the general site photos). Tap to enlarge;
/// never deletable here. Renders nothing when there are none.
class InspectorEvidenceStrip extends StatelessWidget {
  const InspectorEvidenceStrip({
    super.key,
    required this.label,
    required this.photos,
  });

  final String label;
  final List<ExecutionPhoto> photos;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final p in photos)
        if ((p.url ?? '').trim().isNotEmpty) p,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lock_outline, size: 14, color: context.gssms.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text('$label (${shown.length})',
                  style: Theme.of(context).textTheme.labelMedium),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in shown)
              AuthenticatedImageThumbnail(
                key: Key('inspector_photo_${p.id}'),
                url: p.url,
                width: 64,
                height: 64,
                previewTitle: (p.caption ?? '').trim().isNotEmpty
                    ? p.caption
                    : 'Inspection photo #${p.id}',
              ),
          ],
        ),
      ],
    );
  }
}

/// Before/After photo grid for one execution scope (whole execution, one
/// rectification item, or one inspection point). Locked photos show a lock
/// and no delete/retake affordance — the server rejects their removal.
class ExecutionPhotoGrid extends ConsumerWidget {
  const ExecutionPhotoGrid({
    super.key,
    required this.photos,
    required this.canManage,
    required this.busy,
    required this.onAdd,
    required this.onDelete,
    this.onRetake,
    this.pendingPhotos = const [],
    this.onDeletePending,
    this.onRetakePending,
    this.maxPerKind = 10,
    this.galleryPhotos,
  });

  final List<ExecutionPhoto> photos;
  final List<ExecutionPhoto>? galleryPhotos;
  final bool canManage;
  final bool busy;
  final ValueChanged<String> onAdd;
  final ValueChanged<ExecutionPhoto> onDelete;

  /// Replace this photo with a newly captured one. Shown next to Delete
  /// when provided; omit to hide the affordance for callers that don't
  /// support it yet.
  final ValueChanged<ExecutionPhoto>? onRetake;

  /// Locally-captured photos not yet uploaded — rendered after the
  /// server-confirmed ones, with a "not uploaded" indicator.
  final List<PendingExecutionPhoto> pendingPhotos;
  final ValueChanged<PendingExecutionPhoto>? onDeletePending;
  final ValueChanged<PendingExecutionPhoto>? onRetakePending;

  final int maxPerKind;

  List<ExecutionPhoto> _ofKind(String kind) =>
      photos.where((p) => (p.kind ?? '').toUpperCase() == kind).toList();

  List<PendingExecutionPhoto> _pendingOfKind(String kind) =>
      pendingPhotos.where((p) => p.kind.toUpperCase() == kind).toList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `protected_media` requires authentication and Image.network sends
    // none by itself, so photos would otherwise render as broken images
    // (same reasoning as ChecklistLineCard's evidence thumbnails).
    final token = sessionFromAuth(ref.read(authControllerProvider))?.accessToken;
    final headers = (token == null || token.isEmpty)
        ? null
        : {'Authorization': 'Bearer $token'};
    if (!canManage && pendingPhotos.isEmpty) {
      return ExecutionPhotoGallery(
        photos: photos,
        galleryPhotos: galleryPhotos,
        maxPerKind: maxPerKind,
        headers: headers,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final kind in const ['BEFORE', 'AFTER'])
          Padding(
            padding: EdgeInsets.only(bottom: kind == 'AFTER' ? 0 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        kind == 'BEFORE'
                            ? 'Before photos (${_ofKind(kind).length + _pendingOfKind(kind).length}/$maxPerKind)'
                            : 'After photos (${_ofKind(kind).length + _pendingOfKind(kind).length}/$maxPerKind)',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    if (canManage &&
                        _ofKind(kind).length + _pendingOfKind(kind).length <
                            maxPerKind)
                      TextButton.icon(
                        key: Key('add_${kind.toLowerCase()}_photo_button'),
                        onPressed: busy ? null : () => onAdd(kind),
                        icon: const Icon(Icons.photo_camera_outlined,
                            size: 16),
                        label: const Text('Add'),
                      ),
                  ],
                ),
                if (_ofKind(kind).isEmpty && _pendingOfKind(kind).isEmpty)
                  Text('No $kind photos yet.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.gssms.textSecondary)),
                for (final photo in _ofKind(kind))
                  _ExecutionPhotoTile(
                    photo: photo,
                    canManage: canManage,
                    busy: busy,
                    onDelete: onDelete,
                    onRetake: onRetake,
                    headers: headers,
                  ),
                for (final photo in _pendingOfKind(kind))
                  _PendingPhotoTile(
                    photo: photo,
                    canManage: canManage,
                    busy: busy,
                    onDelete: onDeletePending,
                    onRetake: onRetakePending,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ExecutionPhotoTile extends StatelessWidget {
  const _ExecutionPhotoTile({
    required this.photo,
    required this.canManage,
    required this.busy,
    required this.onDelete,
    required this.onRetake,
    required this.headers,
  });

  final ExecutionPhoto photo;
  final bool canManage;
  final bool busy;
  final ValueChanged<ExecutionPhoto> onDelete;
  final ValueChanged<ExecutionPhoto>? onRetake;
  final Map<String, String>? headers;

  bool get _locked => photo.locked || photo.fromComplaint;

  @override
  Widget build(BuildContext context) {
    final hasUrl = photo.url != null && photo.url!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          InkWell(
            key: Key('preview_exec_photo_${photo.id}'),
            borderRadius: BorderRadius.circular(GssmsRadius.r4),
            onTap: hasUrl ? () => _openPreview(context) : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GssmsRadius.r4),
              child: SizedBox(
                width: 48,
                height: 48,
                child: hasUrl
                    ? ProtectedNetworkImage(
                        photo.url!,
                        headers: headers,
                        fit: BoxFit.cover,
                        // No cacheWidth here deliberately: decoding
                        // EXIF-rotated (portrait) camera JPEGs at a reduced
                        // target size renders solid black on this device —
                        // confirmed live (Photo #6, landscape, was fine;
                        // Photo #1, portrait, was black until this was
                        // removed). Full-resolution decode is slower but
                        // correct; revisit only with a fix that also
                        // verifies portrait EXIF orientation.
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                                ? child
                                : const Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                        errorBuilder: (context, error, stack) => Container(
                          color: context.gssms.surfaceInset,
                          child: const Icon(Icons.broken_image_outlined,
                              size: 20),
                        ),
                      )
                    : Container(
                        color: context.gssms.surfaceInset,
                        child: const Icon(Icons.image_outlined, size: 20),
                      ),
              ),
            ),
          ),
          const SizedBox(width: GssmsSpacing.s8),
          Expanded(
            child: Text(
              'Photo #${photo.id}${photo.fromComplaint ? ' (from breakdown report)' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_locked)
            const Icon(Icons.lock_outline, size: 16)
          else if (canManage) ...[
            if (onRetake != null)
              IconButton(
                key: Key('retake_exec_photo_${photo.id}'),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                tooltip: 'Retake photo',
                onPressed: busy ? null : () => onRetake!(photo),
              ),
            IconButton(
              key: Key('delete_exec_photo_${photo.id}'),
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Delete photo',
              onPressed: busy ? null : () => onDelete(photo),
            ),
          ],
        ],
      ),
    );
  }

  void _openPreview(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _PhotoPreviewScaffold(
        title: 'Photo #${photo.id}',
        image: (photo.url == null || photo.url!.isEmpty)
            ? null
            : ProtectedNetworkImage(
                photo.url!,
                headers: headers,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 64),
              ),
      ),
      fullscreenDialog: true,
    ));
  }
}

/// A locally-captured photo not yet uploaded. No lock/retake-on-server
/// semantics apply — delete and retake act purely on the local file.
class _PendingPhotoTile extends StatelessWidget {
  const _PendingPhotoTile({
    required this.photo,
    required this.canManage,
    required this.busy,
    required this.onDelete,
    required this.onRetake,
  });

  final PendingExecutionPhoto photo;
  final bool canManage;
  final bool busy;
  final ValueChanged<PendingExecutionPhoto>? onDelete;
  final ValueChanged<PendingExecutionPhoto>? onRetake;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(GssmsRadius.r4),
            onTap: () => _openPreview(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GssmsRadius.r4),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Image.file(
                  File(photo.localPath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    color: context.gssms.surfaceInset,
                    child:
                        const Icon(Icons.broken_image_outlined, size: 20),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: GssmsSpacing.s8),
          Expanded(
            child: Row(
              children: [
                Icon(Icons.cloud_upload_outlined,
                    size: 14, color: context.gssms.warning.foreground),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'On this phone. Uploads when you tap Save Progress.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.gssms.warning.foreground,
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (canManage) ...[
            if (onRetake != null)
              IconButton(
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                tooltip: 'Retake photo',
                onPressed: busy ? null : () => onRetake!(photo),
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Remove photo',
                onPressed: busy ? null : () => onDelete!(photo),
              ),
          ],
        ],
      ),
    );
  }

  void _openPreview(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _PhotoPreviewScaffold(
        title: 'Photo (not uploaded)',
        image: Image.file(
          File(photo.localPath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64),
        ),
      ),
      fullscreenDialog: true,
    ));
  }
}

/// Full-screen, pinch-to-zoom view shared by network- and local-file photos.
class _PhotoPreviewScaffold extends StatelessWidget {
  const _PhotoPreviewScaffold({required this.title, required this.image});

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
              const Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 64),
        ),
      ),
    );
  }
}

/// BEFORE/AFTER choice dialog. Returns null on cancel.
Future<String?> pickPhotoKind(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Photo type'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Before'),
            onTap: () => Navigator.of(ctx).pop('BEFORE'),
          ),
          ListTile(
            title: const Text('After'),
            onTap: () => Navigator.of(ctx).pop('AFTER'),
          ),
        ],
      ),
    ),
  );
}

/// Camera/Gallery choice dialog for adding or retaking an execution photo.
/// Returns null on cancel.
Future<ImageSource?> pickExecutionImageSource(BuildContext context) {
  return showDialog<ImageSource>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add photo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}
