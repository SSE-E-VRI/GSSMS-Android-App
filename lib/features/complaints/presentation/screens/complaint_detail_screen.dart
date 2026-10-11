import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/data/lookup_options_service.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/core/widgets/sticky_action_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/complaint_status_style.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_navigation.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_status_style.dart';
import 'package:intl/intl.dart';

/// Detail workspace for one reported breakdown, plus the Convert to Job
/// Work action web offers from the same place.
///
/// Mirrors web's "Breakdown Details" view (ComplaintListView.jsx): reference,
/// date reported, title, description, failure/complainant record, location,
/// asset, evidence photos, current status and the linked Job Work — plus the
/// direct close/reject action (DEPOT_INCHARGE only) web offers beside it.
class ComplaintDetailScreen extends ConsumerStatefulWidget {
  const ComplaintDetailScreen({super.key, required this.complaint});

  final Complaint complaint;

  @override
  ConsumerState<ComplaintDetailScreen> createState() =>
      _ComplaintDetailScreenState();
}

class _ComplaintDetailScreenState extends ConsumerState<ComplaintDetailScreen> {
  late Complaint _complaint;
  bool _loadingDetail = false;
  bool _converting = false;
  bool _acting = false;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void initState() {
    super.initState();
    _complaint = widget.complaint;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshDetail());
  }

  Future<void> _refreshDetail() async {
    if (!mounted) return;
    final session = sessionFromAuth(ref.read(authControllerProvider));
    if (!sessionAllows(session, 'complaints.view')) return;
    // List rows carry no nested photos; pull the full retrieve in the
    // background. A failure keeps the passed snapshot — never blank a
    // working UI over a background blip.
    setState(() => _loadingDetail = true);
    try {
      final full = await ref
          .read(complaintRepositoryProvider)
          .fetchComplaintById(_complaint.id);
      if (!mounted) return;
      setState(() => _complaint = full);
    } catch (_) {
      // Keep snapshot; retry happens on next mutation or pull.
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _mutate(Future<void> Function() action) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await action();
      await _refreshDetail();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  /// Conversion is gated to the depot roles ConversionService actually
  /// accepts — same `_validate_scope` gate as inspections.
  bool _canConvert(UserSession? session) {
    if (session == null) return false;
    if (_complaint.isConverted) return false;
    return canConvertComplaint(session);
  }

  /// Direct close/reject is DEPOT_INCHARGE only server-side
  /// (`RequireDepotInchargeScope`), OPEN records only.
  bool _canClose(UserSession? session) {
    if (session == null) return false;
    if (_complaint.status != ComplaintStatus.open) return false;
    if (_complaint.isConverted) return false;
    return session.roles.contains(AuthRole.depotIncharge);
  }

  bool _canManagePhotos(UserSession? session) {
    if (session == null) return false;
    if (_complaint.status != ComplaintStatus.open) return false;
    return sessionAllows(session, 'complaints.create');
  }

  Future<void> _confirmConvert() async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Convert to Job Work?',
      icon: Icons.build_circle_outlined,
      message:
          'A Job Work will be created from breakdown ${_complaint.reference} and '
          'the breakdown will be marked Converted. From then on its progress '
          'is tracked through that Job Work.',
      confirmLabel: 'Convert',
      confirmKey: const Key('confirm_convert_button'),
    );
    if (!confirmed || !mounted) return;

    setState(() => _converting = true);
    try {
      final result = await ref
          .read(complaintRepositoryProvider)
          .convertToWorkOrder(_complaint.id);
      if (!mounted) return;
      final workOrderId = result['work_order_id'] as int?;
      setState(() {
        _converting = false;
        _complaint = _complaint.markConverted(workOrderId: workOrderId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Converted. A Job Work has been created.'),
          action: workOrderId == null ||
                  !sessionAllows(sessionOf(ref), 'maintenance.view')
              ? null
              : SnackBarAction(
                  label: 'View',
                  onPressed: () => _openJobWork(workOrderId),
                ),
        ),
      );
      // Stay on this screen: it now shows the converted state, and the list
      // behind it re-fetches when the user backs out.
    } catch (e) {
      if (!mounted) return;
      setState(() => _converting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not convert: ${workOrderReadableError(e)}'),
        ),
      );
    }
  }

  Future<void> _closeDialog() async {
    String reason = ComplaintClosureReasons.values.first;
    final remarksController = TextEditingController();
    try {
      final result = await showDialog<({String reason, String remarks})>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('Close / Reject Breakdown'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    key: const Key('close_reason_dropdown'),
                    value: reason,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Reason *'),
                    items: [
                      for (final r in ComplaintClosureReasons.values)
                        DropdownMenuItem(
                          value: r,
                          child: Text(
                              ComplaintClosureReasons.displayName(r)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setD(() => reason = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: remarksController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Remarks *',
                      hintText:
                          'Explain why this breakdown is being closed without a Job Work...',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel')),
              FilledButton(
                key: const Key('confirm_close_breakdown_button'),
                onPressed: () {
                  final remarks = remarksController.text.trim();
                  if (remarks.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Remarks are mandatory.')));
                    return;
                  }
                  Navigator.of(ctx)
                      .pop((reason: reason, remarks: remarks));
                },
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
      if (result == null || !mounted) return;
      await _mutate(() async {
        try {
          final closed = await ref
              .read(complaintRepositoryProvider)
              .closeComplaint(
                _complaint.id,
                closureReason: result.reason,
                closureRemarks: result.remarks,
              );
          if (!mounted) return;
          setState(() => _complaint = closed);
          _snack('Breakdown "${_complaint.title}" closed.');
        } catch (e) {
          _snack('Could not close: ${workOrderReadableError(e)}');
        }
      });
    } finally {
      remarksController.dispose();
    }
  }

  Future<void> _addPhoto() async {
    XFile? picked;
    try {
      picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
    } catch (_) {
      return;
    }
    if (picked == null || !mounted) return;
    final lower = picked.path.toLowerCase();
    if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) {
      _snack('Only JPEG photos are allowed.');
      return;
    }
    await _mutate(() async {
      try {
        final file = File(picked!.path);
        if (!await file.exists()) {
          _snack('Photo not found.');
          return;
        }
        if (await file.length() > 15 * 1024 * 1024) {
          _snack('Photo exceeds the 15 MB limit.');
          return;
        }
        final filename = picked!.path.split(Platform.pathSeparator).last;
        await ref.read(complaintRepositoryProvider).uploadPhoto(
              complaintId: _complaint.id,
              file: await MultipartFile.fromFile(
                picked.path,
                filename: filename.isNotEmpty ? filename : 'evidence.jpg',
                contentType: DioMediaType('image', 'jpeg'),
              ),
            );
        _snack('Photo uploaded.');
      } catch (e) {
        _snack('Could not upload: ${workOrderReadableError(e)}');
      }
    });
  }

  void _openJobWork(int workOrderId) {
    openWorkOrderGuarded(
      context: context,
      session: sessionOf(ref),
      workOrderId: workOrderId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Breakdown ${_complaint.reference}';
    if (!sessionAllows(sessionOf(ref), 'complaints.view')) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const PermissionDeniedView(),
      );
    }

    final session = sessionOf(ref);
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final department = _complaint.department;
    final departmentOptions = department == null
        ? null
        : ref.watch(lookupOptionsProvider('complaint_department')).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDetail,
        child: ListView(
          padding: const EdgeInsets.all(GssmsSpacing.s16),
          children: [
            // WHAT IS THIS / WHAT STATE IS IT IN — first thing on screen.
            SectionCard(
              children: [
                Wrap(
                  spacing: GssmsSpacing.s8,
                  runSpacing: GssmsSpacing.s8,
                  children: [
                    ComplaintStatusChip(complaint: _complaint),
                    ComplaintEffectiveChip(complaint: _complaint),
                    ComplaintJobWorkChip(complaint: _complaint),
                  ],
                ),
                const SizedBox(height: GssmsSpacing.s12),
                Text(_complaint.title, style: textTheme.titleLarge),
                const SizedBox(height: GssmsSpacing.s4),
                Text(
                  _complaint.createdAt != null
                      ? 'Reported ${_dateFormat.format(_complaint.createdAt!)}'
                      : 'Date reported not available',
                  style: textTheme.bodySmall
                      ?.copyWith(color: tokens.textSecondary),
                ),
                if (_loadingDetail) ...[
                  const SizedBox(height: GssmsSpacing.s8),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
            const SizedBox(height: GssmsSpacing.s12),
            SectionCard(
              title: 'Description',
              icon: Icons.notes_outlined,
              children: [
                TextWell(
                  text: _complaint.description,
                  placeholder: 'No description provided.',
                ),
              ],
            ),
            const SizedBox(height: GssmsSpacing.s12),
            SectionCard(
              title: 'Details',
              icon: Icons.info_outline,
              children: [
                InfoRow(label: 'Reference ID', value: _complaint.reference),
                if (department != null)
                  InfoRow(
                    label: 'Department',
                    value: lookupLabel(departmentOptions, department),
                  ),
                if (_complaint.failureDate != null)
                  InfoRow(
                      label: 'Failure Date',
                      value: _complaint.failureDate),
                if (_complaint.failureTime != null)
                  InfoRow(
                      label: 'Failure Time',
                      value: _complaint.failureTime),
                if (_complaint.complainantName != null &&
                    _complaint.complainantName!.trim().isNotEmpty)
                  InfoRow(
                      label: 'Complainant',
                      value: _complaint.complainantName),
                InfoRow(
                  label: 'Location',
                  value: _complaint.locationLabel,
                  emptyText: 'Location not set',
                ),
                if (_complaint.depotName != null)
                  InfoRow(label: 'Depot', value: _complaint.depotName),
                InfoRow(label: 'Asset', value: _complaint.assetUniqueId),
                if (_complaint.generalAssetDescription != null &&
                    _complaint.generalAssetDescription!.trim().isNotEmpty)
                  InfoRow(
                      label: 'General Asset',
                      value: _complaint.generalAssetDescription),
                if (_complaint.closureReason != null)
                  InfoRow(
                    label: 'Closure',
                    value:
                        '${ComplaintClosureReasons.displayName(_complaint.closureReason!)}${_complaint.closureRemarks?.isNotEmpty == true ? ' — ${_complaint.closureRemarks}' : ''}',
                  ),
              ],
            ),
            const SizedBox(height: GssmsSpacing.s12),
            SectionCard(
              title: 'Evidence Photos (${_complaint.photos.length}/5)',
              icon: Icons.camera_alt_outlined,
              children: [
                if (_complaint.photos.isEmpty)
                  const TextWell(
                      text: null, placeholder: 'No evidence photos yet.'),
                for (final photo in _complaint.photos)
                  Padding(
                    key: Key('breakdown_photo_${photo.id}'),
                    padding:
                        const EdgeInsets.symmetric(vertical: GssmsSpacing.s6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                photo.uploadedByName ??
                                    'Photo #${photo.id}',
                                style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500),
                              ),
                              if (photo.uploadedAt != null)
                                Text(
                                  _dateFormat.format(photo.uploadedAt!),
                                  style: textTheme.bodySmall?.copyWith(
                                      color: tokens.textSecondary),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_canManagePhotos(session) &&
                    _complaint.photos.length < 5) ...[
                  const SizedBox(height: GssmsSpacing.s8),
                  OutlinedButton.icon(
                    key: const Key('add_breakdown_photo_button'),
                    onPressed: _acting ? null : _addPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 16),
                    label: const Text('Add Photo (JPEG only)'),
                  ),
                ],
              ],
            ),
            if (_complaint.isConverted) ...[
              const SizedBox(height: GssmsSpacing.s12),
              _LinkedJobWorkCard(
                complaint: _complaint,
                onOpen: _complaint.workOrderId == null ||
                        !sessionAllows(session, 'maintenance.view')
                    ? null
                    : () => _openJobWork(_complaint.workOrderId!),
              ),
            ],
            if (_canClose(session)) ...[
              const SizedBox(height: GssmsSpacing.s12),
              SectionCard(
                title: 'Closure',
                icon: Icons.check_circle_outline,
                children: [
                  Text(
                    'Close or reject this breakdown directly, without a Job Work. A reason and remarks are required.',
                    style: textTheme.bodySmall
                        ?.copyWith(color: tokens.textSecondary),
                  ),
                  const SizedBox(height: GssmsSpacing.s8),
                  FilledButton.icon(
                    key: const Key('close_breakdown_button'),
                    onPressed: _acting ? null : _closeDialog,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Close / Reject'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: GssmsSpacing.s24),
          ],
        ),
      ),
      bottomNavigationBar: !_complaint.isConverted && _canConvert(session)
          ? StickyActionBar(
              child: FilledButton.icon(
                key: const Key('convert_to_work_order_button'),
                onPressed: _converting ? null : _confirmConvert,
                icon: _converting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.build_circle_outlined),
                label: Text(_converting ? 'Converting…' : 'Convert to Job Work'),
              ),
            )
          : null,
    );
  }
}

class _LinkedJobWorkCard extends StatelessWidget {
  const _LinkedJobWorkCard({required this.complaint, this.onOpen});

  final Complaint complaint;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = linkedJobWorkProgress(complaint.workOrderStatus);
    final reference = complaint.workOrderTicketNumber ??
        (complaint.workOrderId != null ? 'Job Work #${complaint.workOrderId}' : null);
    return SectionCard(
      title: 'Linked Job Work',
      icon: Icons.link,
      children: [
        if (reference != null) InfoRow(label: 'Job Work', value: reference),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: GssmsSpacing.s6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: progress.label,
              tone: progress.tone,
              icon: progress.icon,
            ),
          ),
        ),
        if (onOpen != null) ...[
          const SizedBox(height: GssmsSpacing.s8),
          OutlinedButton.icon(
            key: const Key('view_linked_job_work_button'),
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new),
            label: const Text('View Linked Job Work'),
          ),
        ],
      ],
    );
  }
}
