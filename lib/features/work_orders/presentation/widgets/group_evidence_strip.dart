import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';
import 'package:gssms_mobile/core/widgets/feedback.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_line_card.dart';

/// Before / After (and During, when present) photo evidence for one asset
/// group. The photos are stored on the group's first line ([holder]) through
/// the ordinary line-attachment endpoints, so queued uploads and their sync
/// chips behave exactly like per-line photos.
class GroupEvidenceStrip extends ConsumerStatefulWidget {
  const GroupEvidenceStrip({
    super.key,
    required this.recordId,
    required this.holder,
    this.isPastTechCompleted = false,
  });

  /// Server cap per (line, kind).
  static const int maxPerKind = 5;

  final int recordId;
  final MaintenanceRecordLine holder;
  final bool isPastTechCompleted;

  @override
  ConsumerState<GroupEvidenceStrip> createState() => _GroupEvidenceStripState();
}

class _GroupEvidenceStripState extends ConsumerState<GroupEvidenceStrip> {
  late bool _expanded = widget.holder.attachments.isNotEmpty;

  Map<String, String>? _authHeaders() {
    final token =
        sessionFromAuth(ref.read(authControllerProvider))?.accessToken;
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  ChecklistController get _controller =>
      ref.read(checklistControllerProvider(widget.recordId).notifier);

  Future<void> _capture(EvidenceKind kind, ImageSource source) async {
    // Read everything ref-derived before the camera hand-off (the State can
    // be disposed while the camera app is in the foreground).
    final evidenceService = ref.read(evidenceServiceProvider);
    final controller = _controller;
    final lineId = widget.holder.id;
    try {
      final nearCap = await evidenceService.isStorageNearCap();
      if (nearCap && mounted) {
        showGssmsSnackBar(
          context,
          'Photos waiting to sync are using over 200 MB. Sync before taking '
          'more photos.',
          tone: GssmsTone.warning,
        );
      }
      final evidence =
          await evidenceService.capture(kind: kind, source: source);
      if (evidence == null) return;
      await controller.uploadLineAttachment(
        lineId: lineId,
        kind: kind.name.toUpperCase(),
        imagePath: evidence.path,
        capturedAt: DateTime.now(),
      );
    } catch (e) {
      if (mounted) {
        showGssmsSnackBar(
          context,
          'Could not capture photo. ${workOrderReadableError(e)}',
          tone: GssmsTone.danger,
        );
      }
    }
  }

  Future<void> _delete(LineAttachment attachment) async {
    if (widget.isPastTechCompleted) {
      showGssmsSnackBar(
        context,
        'Cannot delete attachments after technician completion.',
        tone: GssmsTone.danger,
      );
      return;
    }
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Delete Photo',
      message: 'Delete this ${attachment.kind.toLowerCase()} photo? It is '
          'removed from this asset group'
          '${attachment.url.isNotEmpty ? ' and from the server' : ''}.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _controller.deleteLineAttachment(
      lineId: widget.holder.id,
      attachmentId: attachment.id,
      localPath: attachment.localPath,
      idempotencyKey: attachment.idempotencyKey,
    );
  }

  void _showFullscreen(LineAttachment attachment) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Theme.of(ctx).appBarTheme.backgroundColor,
              child: Row(
                children: [
                  Text(
                    '${attachment.kind} Photo',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.65,
              ),
              child: InteractiveViewer(
                child: AttachmentImage(
                  attachment: attachment,
                  headers: _authHeaders(),
                  fit: BoxFit.contain,
                  placeholderSize: 64,
                ),
              ),
            ),
            if (attachment.capturedAt != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Captured: ${DateFormat('dd MMM yyyy, hh:mm a').format(attachment.capturedAt!.toLocal())}',
                  style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                        color: ctx.gssms.textSecondary,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final holder = widget.holder;
    final tokens = context.gssms;
    final before = holder.attachments.where((a) => a.kind == 'BEFORE').toList();
    final during = holder.attachments.where((a) => a.kind == 'DURING').toList();
    final after = holder.attachments.where((a) => a.kind == 'AFTER').toList();
    final hasAny = holder.attachments.isNotEmpty;

    final summary = during.isEmpty
        ? 'Before ${before.length} · After ${after.length}'
        : 'Before ${before.length} · During ${during.length} · After ${after.length}';

    return Column(
      key: Key('group_evidence_${holder.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: Key('group_evidence_toggle_${holder.id}'),
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(GssmsRadius.r8),
          child: Container(
            constraints: const BoxConstraints(minHeight: GssmsSize.touchTarget),
            padding: const EdgeInsets.symmetric(horizontal: GssmsSpacing.s8),
            decoration: BoxDecoration(
              color: tokens.surfaceInset,
              borderRadius: BorderRadius.circular(GssmsRadius.r8),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.photo_camera_outlined,
                  size: 18,
                  color: hasAny ? tokens.link : tokens.textSecondary,
                ),
                const SizedBox(width: GssmsSpacing.s8),
                Expanded(
                  child: Text(
                    'Photo Evidence · $summary',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: tokens.textSecondary,
                  semanticLabel: _expanded ? 'Hide photos' : 'Show photos',
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: GssmsSpacing.s8),
          _strip(EvidenceKind.before, 'Before Photos', before),
          if (during.isNotEmpty) ...[
            const SizedBox(height: GssmsSpacing.s8),
            _strip(EvidenceKind.during, 'During Photos', during),
          ],
          const SizedBox(height: GssmsSpacing.s8),
          _strip(EvidenceKind.after, 'After Photos', after),
        ],
      ],
    );
  }

  Widget _strip(
    EvidenceKind kind,
    String title,
    List<LineAttachment> attachments,
  ) {
    final canAdd = attachments.length < GroupEvidenceStrip.maxPerKind &&
        !widget.isPastTechCompleted;
    final tokens = context.gssms;
    final id = widget.holder.id;

    Widget action(
        String keySuffix, IconData icon, String tooltip, ImageSource source) {
      return SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          key: Key('group_${id}_${keySuffix}_${kind.name}'),
          icon: Icon(icon, size: 22),
          tooltip: tooltip,
          onPressed: canAdd ? () => _capture(kind, source) : null,
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: EdgeInsets.zero,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(GssmsSpacing.s8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GssmsRadius.r8),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$title (${attachments.length}/${GroupEvidenceStrip.maxPerKind})',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              action('camera', Icons.photo_camera, 'Capture from camera',
                  ImageSource.camera),
              const SizedBox(width: 4),
              action('gallery', Icons.photo_library_outlined,
                  'Select from gallery', ImageSource.gallery),
            ],
          ),
          if (attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No photos captured yet.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final att in attachments) ...[
                    _thumbnail(att),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _thumbnail(LineAttachment attachment) {
    final tokens = context.gssms;
    final GssmsTonePalette badge;
    final IconData badgeIcon;
    final String badgeText;
    if (attachment.isFailed) {
      badge = tokens.danger;
      badgeIcon = Icons.warning_amber_rounded;
      badgeText = 'failed';
    } else if (attachment.isPending) {
      badge = tokens.warning;
      badgeIcon = Icons.sync;
      badgeText = 'queued';
    } else {
      badge = tokens.success;
      badgeIcon = Icons.check_circle;
      badgeText = 'uploaded';
    }
    final thumbKey = attachment.idempotencyKey ?? attachment.id;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: Key('line_attachment_thumb_$thumbKey'),
          onTap: () => _showFullscreen(attachment),
          onLongPress:
              widget.isPastTechCompleted ? null : () => _delete(attachment),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 76,
                  height: 76,
                  color: tokens.surfaceInset,
                  child: AttachmentImage(
                    attachment: attachment,
                    headers: _authHeaders(),
                    fit: BoxFit.cover,
                    decodeWidth:
                        76 * MediaQuery.devicePixelRatioOf(context).ceil(),
                  ),
                ),
              ),
              Positioned(
                top: 3,
                right: 3,
                child: Tooltip(
                  message: badgeText,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: badge.solid,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(badgeIcon, size: 12, color: badge.onSolid),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (attachment.isFailed) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            key: Key('retry_attachment_$thumbKey'),
            icon:
                Icon(Icons.refresh, size: 16, color: tokens.danger.foreground),
            label: Text(
              'Retry',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.danger.foreground,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: GssmsSpacing.s8),
              minimumSize: const Size(76, GssmsSize.touchTarget),
            ),
            onPressed: () => _controller.retryAttachment(attachment),
          ),
        ],
      ],
    );
  }
}
