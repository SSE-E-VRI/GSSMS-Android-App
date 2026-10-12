import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/core/widgets/sticky_action_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_evidence_photo.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_point.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:gssms_mobile/features/inspections/presentation/inspection_status_style.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_navigation.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_status_style.dart';
import 'package:intl/intl.dart';

const int _kMaxPointPhotos = 5;

/// Full inspection workspace mirroring web `InspectionDetailView`.
///
/// Header (dual record/effective badges, points count), overview, remarks,
/// general evidence, observation points with disposition workflows
/// (resolve/dispose/mark-unresolved/approve-JW2), point-wise Job Work
/// creation (JW-001/JW-002), post-JW2 breakdown escalation, and explicit
/// close. Legacy whole-inspection Convert stays only for point-less legacy
/// records — web 400s `STRUCTURED_CONVERSION_FORBIDDEN` otherwise.
class InspectionDetailScreen extends ConsumerStatefulWidget {
  const InspectionDetailScreen({super.key, required this.inspection});

  final Inspection inspection;

  @override
  ConsumerState<InspectionDetailScreen> createState() =>
      _InspectionDetailScreenState();
}

class _InspectionDetailScreenState
    extends ConsumerState<InspectionDetailScreen> {
  late Inspection _inspection;
  bool _loadingDetail = false;
  bool _converting = false;
  bool _closing = false;
  bool _acting = false;
  final Set<int> _selectedJw1 = {};

  bool get _busy => _converting || _acting || _closing;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void initState() {
    super.initState();
    _inspection = widget.inspection;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshDetail());
  }

  Future<void> _refreshDetail() async {
    if (!mounted) return;
    final session = sessionFromAuth(ref.read(authControllerProvider));
    if (!sessionAllows(session, 'inspections.view')) return;
    // List rows are lightweight (no nested points); pull the full retrieve.
    // Failure keeps the passed snapshot — never blank a working UI.
    setState(() => _loadingDetail = true);
    try {
      final full = await ref
          .read(inspectionRepositoryProvider)
          .fetchInspectionById(_inspection.id);
      if (!mounted) return;
      setState(() {
        _inspection = full;
        // Prune stale JW1 selection (points left UNASSIGNED since last load).
        _selectedJw1.removeWhere((id) => !full.points.any((p) =>
            p.id == id &&
            p.isEligibleForJw1(inspectionClosed: full.isClosed)));
      });
    } catch (_) {
      // Keep snapshot; a retry happens on next mutation or pull.
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  bool _canEdit(UserSession? session) =>
      sessionAllows(session, 'inspections.view') &&
      sessionAllows(session, 'inspections.edit');

  /// Legacy conversion gate: depot roles only, unconverted, point-less.
  bool _canConvert(UserSession? session) {
    if (session == null) return false;
    if (_inspection.isConverted) return false;
    if (_inspection.points.isNotEmpty) return false;
    return canConvertInspection(session);
  }

  bool _canClose(UserSession? session) {
    if (session == null) return false;
    if (!_canEdit(session)) return false;
    if (_inspection.isClosed) return false;
    return session.roles.any({
      AuthRole.depotIncharge,
      AuthRole.divAdmin,
      AuthRole.superAdmin,
    }.contains);
  }

  bool _canApproveJw2(UserSession? session) {
    if (session == null) return false;
    if (!_canEdit(session)) return false;
    return session.roles.any({
      AuthRole.divAdmin,
      AuthRole.superAdmin,
    }.contains);
  }

  String? get _closeBlockReason {
    final points = _inspection.points;
    if (points.isEmpty) {
      final active = _inspection.jobWorks.any((w) {
        final s = (w.status ?? '').toUpperCase();
        return s != 'VERIFIED' && s != 'CLOSED';
      });
      if (active) return 'A linked Job Work is not completed.';
      return null;
    }
    final nonTerminal =
        points.where((p) => !p.dispositionStatus.isTerminal).toList();
    if (nonTerminal.isNotEmpty) {
      return '${nonTerminal.length} point(s) are not resolved or disposed.';
    }
    if (points.any((p) => p.hasBlockingEscalation)) {
      return 'An escalation Work Order is still active.';
    }
    return null;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _acting = true);
    try {
      await action();
      await _refreshDetail();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  bool _canManagePhotos(UserSession? session) {
    if (!_canEdit(session)) return false;
    return !_inspection.isClosed;
  }

  static const int _maxGeneralPhotos = 3;
  static const int _maxPhotoBytes = 15 * 1024 * 1024;

  Future<MultipartFile?> _asMultipart(XFile photo) async {
    final lower = photo.path.toLowerCase();
    if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) {
      _snack('Only JPEG photos are allowed.');
      return null;
    }
    final file = File(photo.path);
    if (!await file.exists()) {
      _snack('Photo not found.');
      return null;
    }
    if (await file.length() > _maxPhotoBytes) {
      _snack('Photo exceeds the 15 MB limit.');
      return null;
    }
    final filename = photo.path.split(Platform.pathSeparator).last;
    return MultipartFile.fromFile(
      photo.path,
      filename: filename.isNotEmpty ? filename : 'evidence.jpg',
      contentType: DioMediaType('image', 'jpeg'),
    );
  }

  Future<XFile?> _pickPhoto() async {
    try {
      return await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
    } catch (_) {
      return null;
    }
  }

  Future<void> _addGeneralPhoto() async {
    final picked = await _pickPhoto();
    if (picked == null || !mounted) return;
    final file = await _asMultipart(picked);
    if (file == null) return;
    await _mutate(() async {
      try {
        await ref.read(inspectionRepositoryProvider).uploadGeneralPhoto(
              inspectionId: _inspection.id,
              file: file,
            );
        _snack('Evidence photo uploaded.');
      } catch (e) {
        _snack('Could not upload: ${userFacingError(e)}');
      }
    });
  }

  Future<void> _addPointPhoto(InspectionPoint point) async {
    if (point.evidencePhotos.length >= _kMaxPointPhotos) {
      _snack('Maximum 5 evidence photos per point.');
      return;
    }
    final picked = await _pickPhoto();
    if (picked == null || !mounted) return;
    final file = await _asMultipart(picked);
    if (file == null) return;
    await _mutate(() async {
      try {
        await ref.read(inspectionRepositoryProvider).uploadPointPhoto(
              pointId: point.id,
              file: file,
            );
        _snack('Evidence photo uploaded for Point #${point.pointNumber}.');
      } catch (e) {
        _snack('Could not upload: ${userFacingError(e)}');
      }
    });
  }

  Future<void> _confirmConvert() async {
    if (_busy) return;
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Convert to Job Work?',
      icon: Icons.build_circle_outlined,
      message:
          'A Job Work will be created from inspection ${_inspection.reference} '
          'and the inspection will be marked Converted. From then on its '
          'progress is tracked through that Job Work.',
      confirmLabel: 'Convert',
      confirmKey: const Key('confirm_convert_button'),
    );
    if (!confirmed || !mounted) return;

    setState(() => _converting = true);
    try {
      final result = await ref
          .read(inspectionRepositoryProvider)
          .convertToWorkOrder(_inspection.id);
      if (!mounted) return;
      final workOrderId = asJsonInt(result['work_order_id']);
      setState(() {
        _converting = false;
        _inspection = _inspection.markConverted(workOrderId: workOrderId);
      });
      _snack('Converted. A Job Work has been created.');
      // Pull the full record so the Job Work card fills in the server
      // ticket/status beyond the optimistic id.
      unawaited(_refreshDetail());
    } catch (e) {
      if (!mounted) return;
      setState(() => _converting = false);
      _snack('Could not convert: ${workOrderReadableError(e)}');
    }
  }

  Future<void> _closeInspection() async {
    if (_busy) return;
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Close inspection?',
      icon: Icons.check_circle_outline,
      message:
          'All points must be resolved or disposed. This cannot be undone.',
      confirmLabel: 'Close',
      confirmKey: const Key('confirm_close_inspection_button'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _closing = true);
    try {
      final closed = await ref
          .read(inspectionRepositoryProvider)
          .closeInspection(_inspection.id);
      if (!mounted) return;
      setState(() => _inspection = closed);
      _snack('Inspection closed.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not close: ${userFacingError(e)}');
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  // ——— Disposition dialogs ———

  Future<void> _resolveDialog(InspectionPoint point) async {
    final remarks = await _textDialog(
      title: 'Resolve Point #${point.pointNumber}',
      label: 'Resolution remarks *',
      hint: 'e.g. Replaced cracked clamp, torque tested. Resolved.',
      confirmLabel: 'Resolve',
      confirmKey: 'confirm_resolve_point_button',
    );
    if (remarks == null || !mounted) return;
    await _mutate(() async {
      try {
        await ref
            .read(inspectionRepositoryProvider)
            .resolvePoint(point.id, remarks: remarks);
        _snack('Point #${point.pointNumber} resolved.');
      } catch (e) {
        _snack('Could not resolve: ${userFacingError(e)}');
      }
    });
  }

  Future<void> _disposeDialog(InspectionPoint point) async {
    final result = await _reasonDialog(
      title: 'Dispose Point #${point.pointNumber}',
      reasons: InspectionPointReasons.disposeReasons,
      reasonKey: 'dispose_reason_dropdown',
    );
    if (result == null || !mounted) return;
    await _mutate(() async {
      try {
        await ref.read(inspectionRepositoryProvider).disposePoint(point.id,
            reason: result.reason, remarks: result.remarks);
        _snack('Point #${point.pointNumber} disposed.');
      } catch (e) {
        _snack('Could not dispose: ${userFacingError(e)}');
      }
    });
  }

  Future<void> _unresolvedDialog(InspectionPoint point) async {
    final result = await _reasonDialog(
      title: 'Mark Point #${point.pointNumber} Unresolved',
      reasons: InspectionPointReasons.unresolvedReasons,
      reasonKey: 'unresolved_reason_dropdown',
    );
    if (result == null || !mounted) return;
    await _mutate(() async {
      try {
        await ref.read(inspectionRepositoryProvider).markUnresolved(point.id,
            reason: result.reason, remarks: result.remarks);
        _snack('Point #${point.pointNumber} marked unresolved.');
      } catch (e) {
        _snack('Could not mark unresolved: ${userFacingError(e)}');
      }
    });
  }

  Future<void> _approveJw2Dialog(InspectionPoint point) async {
    final remarks = await _textDialog(
      title: 'Approve JW-002 for Point #${point.pointNumber}',
      label: 'Approval remarks (optional)',
      hint: 'e.g. Approved for replacement execution.',
      confirmLabel: 'Approve',
      confirmKey: 'confirm_approve_jw2_button',
      required: false,
    );
    if (remarks == null || !mounted) return;
    await _mutate(() async {
      try {
        await ref
            .read(inspectionRepositoryProvider)
            .approveJw2(point.id, remarks: remarks);
        _snack('Point #${point.pointNumber} approved for JW-002.');
      } catch (e) {
        _snack('Could not approve: ${userFacingError(e)}');
      }
    });
  }

  Future<void> _createJwDialog({
    required List<InspectionPoint> points,
    required bool isJw2,
  }) async {
    final result = await _jobWorkDialog(isJw2: isJw2, points: points);
    if (result == null || !mounted) return;
    await _mutate(() async {
      try {
        final res =
            await ref.read(inspectionRepositoryProvider).createJobWork(
                  inspectionId: _inspection.id,
                  pointIds: points.map((p) => p.id).toList(),
                  priority: result.priority,
                  title: result.title,
                  description: result.description,
                  scheduledDate: result.scheduledDate,
                );
        final ticket = res['ticket_number'] ??
            (res['work_order'] is Map
                ? (res['work_order'] as Map)['ticket_number']
                : null);
        _snack(ticket != null
            ? 'Job Work $ticket created for ${points.length} point(s).'
            : 'Job Work created.');
        setState(() => _selectedJw1
            .removeWhere((id) => points.any((p) => p.id == id)));
      } catch (e) {
        _snack('Could not create Job Work: ${userFacingError(e)}');
      }
    });
  }

  Future<void> _escalateDialog(InspectionPoint point) async {
    final result = await _escalationDialog(point);
    if (result == null || !mounted) return;
    await _mutate(() async {
      try {
        final res =
            await ref.read(inspectionRepositoryProvider).escalatePoint(
                  point.id,
                  type: result.type,
                  priority: result.priority,
                  title: result.title,
                  description: result.description,
                  reason: result.reason,
                  remarks: result.remarks,
                );
        final ticket = res['ticket_number'];
        _snack(ticket != null
            ? 'Escalated to $ticket.'
            : 'Escalated to ${result.type} Work Order.');
      } catch (e) {
        _snack('Could not escalate: ${userFacingError(e)}');
      }
    });
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
    required String hint,
    required String confirmLabel,
    required String confirmKey,
    bool required = true,
  }) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(labelText: label, hintText: hint),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            FilledButton(
              key: Key(confirmKey),
              onPressed: () {
                final v = controller.text.trim();
                if (required && v.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('This field is required.')));
                  return;
                }
                Navigator.of(ctx).pop(v);
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<({String reason, String remarks})?> _reasonDialog({
    required String title,
    required List<String> reasons,
    required String reasonKey,
  }) async {
    String reason = reasons.first;
    final remarksController = TextEditingController();
    final customController = TextEditingController();
    try {
      return await showDialog<({String reason, String remarks})>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    key: Key(reasonKey),
                    value: reason,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Reason *'),
                    items: [
                      for (final r in reasons)
                        DropdownMenuItem(value: r, child: Text(r)),
                    ],
                    onChanged: (v) {
                      if (v != null) setD(() => reason = v);
                    },
                  ),
                  if (reason == 'OTHER') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: customController,
                      decoration: const InputDecoration(
                          labelText: 'Custom reason *'),
                      onChanged: (_) => setD(() {}),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: remarksController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Remarks *',
                        hintText: 'Mandatory remarks'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final effective =
                      reason == 'OTHER' ? customController.text.trim() : reason;
                  final remarks = remarksController.text.trim();
                  if (effective.isEmpty || remarks.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content:
                            Text('Reason and remarks are mandatory.')));
                    return;
                  }
                  Navigator.of(ctx).pop(
                      (reason: effective, remarks: remarks));
                },
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      );
    } finally {
      remarksController.dispose();
      customController.dispose();
    }
  }

  Future<
      ({
        String priority,
        String? title,
        String? description,
        String? scheduledDate
      })?> _jobWorkDialog({
    required bool isJw2,
    required List<InspectionPoint> points,
  }) async {
    String priority = 'HIGH';
    final titleC = TextEditingController();
    final descC = TextEditingController();
    final dateC = TextEditingController();
    try {
      return await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: Text(isJw2
                ? 'Create Replacement Job Work (JW-002)'
                : 'Create Job Work (JW-001) — ${points.length} point(s)'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: priority,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Priority *'),
                    items: const [
                      DropdownMenuItem(
                          value: 'HIGH', child: Text('High')),
                      DropdownMenuItem(
                          value: 'MEDIUM', child: Text('Medium')),
                      DropdownMenuItem(value: 'LOW', child: Text('Low')),
                    ],
                    onChanged: (v) {
                      if (v != null) setD(() => priority = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: titleC,
                      decoration: const InputDecoration(
                          labelText: 'Title (optional)')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: descC,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Description (optional)')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dateC,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Scheduled date (optional)',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate:
                            DateTime(DateTime.now().year + 5),
                      );
                      if (picked != null) {
                        dateC.text =
                            '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop((
                  priority: priority,
                  title: titleC.text.trim().isEmpty
                      ? null
                      : titleC.text.trim(),
                  description: descC.text.trim().isEmpty
                      ? null
                      : descC.text.trim(),
                  scheduledDate: dateC.text.trim().isEmpty
                      ? null
                      : dateC.text.trim(),
                )),
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      );
    } finally {
      titleC.dispose();
      descC.dispose();
      dateC.dispose();
    }
  }

  Future<
      ({
        String type,
        String priority,
        String? title,
        String? description,
        String? reason,
        String? remarks
      })?> _escalationDialog(InspectionPoint point) async {
    String type = 'BREAKDOWN';
    String priority = point.priority.code == 'UNKNOWN'
        ? 'HIGH'
        : point.priority.code;
    final titleC = TextEditingController();
    final descC = TextEditingController();
    final reasonC = TextEditingController();
    final remarksC = TextEditingController();
    try {
      return await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: Text('Escalate Point #${point.pointNumber}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: type,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Work order type'),
                    items: const [
                      DropdownMenuItem(
                          value: 'BREAKDOWN', child: Text('Breakdown')),
                      DropdownMenuItem(
                          value: 'CORRECTIVE', child: Text('Corrective')),
                    ],
                    onChanged: (v) {
                      if (v != null) setD(() => type = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: priority,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Priority'),
                    items: const [
                      DropdownMenuItem(
                          value: 'HIGH', child: Text('High')),
                      DropdownMenuItem(
                          value: 'MEDIUM', child: Text('Medium')),
                      DropdownMenuItem(value: 'LOW', child: Text('Low')),
                    ],
                    onChanged: (v) {
                      if (v != null) setD(() => priority = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: reasonC,
                      decoration: const InputDecoration(
                          labelText: 'Reason (optional)')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: remarksC,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Remarks (optional)')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: titleC,
                      decoration: const InputDecoration(
                          labelText: 'Title (optional)')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: descC,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Description (optional)')),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop((
                  type: type,
                  priority: priority,
                  title: titleC.text.trim().isEmpty
                      ? null
                      : titleC.text.trim(),
                  description: descC.text.trim().isEmpty
                      ? null
                      : descC.text.trim(),
                  reason: reasonC.text.trim().isEmpty
                      ? null
                      : reasonC.text.trim(),
                  remarks: remarksC.text.trim().isEmpty
                      ? null
                      : remarksC.text.trim(),
                )),
                child: const Text('Escalate'),
              ),
            ],
          ),
        ),
      );
    } finally {
      titleC.dispose();
      descC.dispose();
      reasonC.dispose();
      remarksC.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final session = authState is Authenticated ? authState.session : null;
    final inspection = _inspection;
    final title = 'Inspection ${inspection.reference}';

    if (!sessionAllows(session, 'inspections.view')) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const PermissionDeniedView(),
      );
    }

    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final when = inspection.inspectionDate ?? inspection.createdAt;
    final inspector = [
      inspection.createdByName,
      if (inspection.createdByDesignation != null &&
          inspection.createdByDesignation!.trim().isNotEmpty)
        '(${inspection.createdByDesignation})',
    ].whereType<String>().join(' ');

    final canEdit = _canEdit(session);
    final points = inspection.points;
    final eligibleJw1 = points
        .where((p) => p.isEligibleForJw1(inspectionClosed: inspection.isClosed))
        .toList();
    final closeReason = _closeBlockReason;
    final showClose = _canClose(session);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDetail,
        child: ListView(
          padding: const EdgeInsets.all(GssmsSpacing.s16),
          children: [
            SectionCard(
              children: [
                Wrap(
                  spacing: GssmsSpacing.s8,
                  runSpacing: GssmsSpacing.s8,
                  children: [
                    InspectionStatusChip(inspection: inspection),
                    InspectionEffectiveStatusChip(inspection: inspection),
                    InspectionPointsBadge(inspection: inspection),
                    InspectionJobWorkChip(inspection: inspection),
                  ],
                ),
                const SizedBox(height: GssmsSpacing.s12),
                Text(inspection.title, style: textTheme.titleLarge),
                const SizedBox(height: GssmsSpacing.s4),
                Text(
                  when != null
                      ? 'Inspected ${_dateFormat.format(when)}'
                      : 'Inspection date not available',
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
              title: 'Notes',
              icon: Icons.notes_outlined,
              children: [
                TextWell(
                    text: inspection.notes,
                    placeholder: 'No notes provided.'),
              ],
            ),
            const SizedBox(height: GssmsSpacing.s12),
            SectionCard(
              title: 'Details',
              icon: Icons.info_outline,
              children: [
                InfoRow(label: 'Reference ID', value: inspection.reference),
                if (inspection.inspectionNumber != null)
                  InfoRow(
                      label: 'Inspection No',
                      value: inspection.inspectionNumber),
                InfoRow(
                  label: 'Location',
                  value: inspection.locationLabel,
                  emptyText: 'Location not set',
                ),
                if (inspection.depotName != null)
                  InfoRow(label: 'Depot', value: inspection.depotName),
                if (inspection.assetUniqueId != null)
                  InfoRow(
                      label: 'Asset',
                      value: inspection.assetName != null
                          ? '${inspection.assetUniqueId} (${inspection.assetName})'
                          : inspection.assetUniqueId),
                if (inspection.generalAssetDescription != null &&
                    inspection.generalAssetDescription!.trim().isNotEmpty)
                  InfoRow(
                      label: 'General Asset',
                      value: inspection.generalAssetDescription),
                if (inspector.isNotEmpty)
                  InfoRow(label: 'Inspected By', value: inspector),
              ],
            ),
            if (inspection.isConverted) ...[
              const SizedBox(height: GssmsSpacing.s12),
              _LinkedJobWorkCard(
                inspection: inspection,
                onOpen: inspection.workOrderId != null &&
                        sessionAllows(session, 'maintenance.view')
                    ? () => openWorkOrderGuarded(
                          context: context,
                          session: session,
                          workOrderId: inspection.workOrderId!,
                        )
                    : null,
              ),
            ],
            if (inspection.jobWorks.isNotEmpty) ...[
              const SizedBox(height: GssmsSpacing.s12),
              SectionCard(
                title: 'Job Works (${inspection.jobWorks.length})',
                icon: Icons.build_circle_outlined,
                children: [
                  for (final jw in inspection.jobWorks)
                    InfoRow(
                      label: jw.ticketNumber ?? 'Job Work',
                      value: jw.status,
                    ),
                ],
              ),
            ],
            const SizedBox(height: GssmsSpacing.s12),
            SectionCard(
              title: 'Observation Points (${points.length})',
              icon: Icons.pin_drop_outlined,
              children: [
                if (points.isEmpty)
                  const TextWell(
                      text: null,
                      placeholder:
                          'No structured points. Legacy note — convert as a whole or review web.'),
                for (final point in points)
                  _PointCard(
                    point: point,
                    inspectionClosed: inspection.isClosed,
                    canEdit: canEdit,
                    canApproveJw2: _canApproveJw2(session),
                    acting: _busy,                    jw1Selected: _selectedJw1.contains(point.id),
                    onToggleJw1: eligibleJw1.any((p) => p.id == point.id)
                        ? () => setState(() {
                              if (_selectedJw1.contains(point.id)) {
                                _selectedJw1.remove(point.id);
                              } else {
                                _selectedJw1.add(point.id);
                              }
                            })
                        : null,
                    onResolve: canEdit &&
                            point.dispositionStatus ==
                                PointDispositionStatus.assigned
                        ? () => _resolveDialog(point)
                        : null,
                    onDispose: canEdit &&
                            !point.dispositionStatus.isTerminal
                        ? () => _disposeDialog(point)
                        : null,
                    onUnresolved: canEdit &&
                            point.dispositionStatus ==
                                PointDispositionStatus.assigned
                        ? () => _unresolvedDialog(point)
                        : null,
                    onApproveJw2: canEdit &&
                            _canApproveJw2(session) &&
                            point.dispositionStatus ==
                                PointDispositionStatus.unresolved
                        ? () => _approveJw2Dialog(point)
                        : null,
                    onCreateJw2: canEdit &&
                            point.isEligibleForJw2(
                                inspectionClosed: inspection.isClosed)
                        ? () => _createJwDialog(
                            points: [point], isJw2: true)
                        : null,
                    onEscalate: canEdit &&
                            point.isEligibleForEscalation(
                                inspectionClosed: inspection.isClosed)
                        ? () => _escalateDialog(point)
                        : null,
                    session: session,
                    onAddPhoto: _canManagePhotos(session) &&
                            point.canUploadPointPhoto(
                                inspectionClosed: inspection.isClosed) &&
                            point.evidencePhotos.length < _kMaxPointPhotos
                        ? () => _addPointPhoto(point)
                        : null,
                  ),
                if (canEdit && eligibleJw1.length >= 2) ...[
                  const SizedBox(height: GssmsSpacing.s8),
                  FilledButton.icon(
                    key: const Key('create_clubbed_jw1_button'),
                    onPressed: _busy || _selectedJw1.isEmpty
                        ? null
                        : () {
                            final selected = points
                                .where((p) => _selectedJw1.contains(p.id))
                                .toList();
                            if (selected.isEmpty) return;
                            _createJwDialog(
                                points: selected, isJw2: false);
                          },
                    icon: const Icon(Icons.build_circle_outlined),
                    label: Text(_selectedJw1.isEmpty
                        ? 'Select points for JW-001'
                        : 'Create JW-001 (${_selectedJw1.length})'),
                  ),
                ],
                if (canEdit && eligibleJw1.length == 1) ...[
                  const SizedBox(height: GssmsSpacing.s8),
                  FilledButton.icon(
                    key: const Key('create_single_jw1_button'),
                    onPressed: _busy
                        ? null
                        : () => _createJwDialog(
                            points: eligibleJw1, isJw2: false),
                    icon: const Icon(Icons.build_circle_outlined),
                    label: const Text('Create JW-001'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: GssmsSpacing.s12),
            SectionCard(
              title:
                  'General Evidence (${inspection.generalEvidencePhotos.length}/$_maxGeneralPhotos)',
              icon: Icons.camera_alt_outlined,
              children: [
                if (inspection.generalEvidencePhotos.isEmpty)
                  const TextWell(
                      text: null,
                      placeholder:
                          'No general photos yet. Site/overview context goes here (JPEG only).'),
                for (final photo in inspection.generalEvidencePhotos)
                  _EvidencePhotoRow(
                    photo: photo,
                  ),
                if (_canManagePhotos(session) &&
                    inspection.generalEvidencePhotos.length <
                        _maxGeneralPhotos) ...[
                  const SizedBox(height: GssmsSpacing.s8),
                  OutlinedButton.icon(
                    key: const Key('add_general_evidence_button'),
                    onPressed: _busy ? null : _addGeneralPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 16),
                    label: const Text('Add Photo (JPEG only)'),
                  ),
                ],
                if (inspection.isClosed)
                  const Padding(
                    padding: EdgeInsets.only(top: GssmsSpacing.s8),
                    child: StatusChip(
                      label: 'Locked (Inspection Closed)',
                      tone: GssmsTone.warning,
                      icon: Icons.lock_outline,
                    ),
                  ),
              ],
            ),
            if (showClose) ...[
              const SizedBox(height: GssmsSpacing.s12),
              SectionCard(
                title: 'Closure',
                icon: Icons.check_circle_outline,
                children: [
                  if (closeReason != null)
                    Text(closeReason,
                        style: textTheme.bodySmall
                            ?.copyWith(color: tokens.textSecondary)),
                  const SizedBox(height: GssmsSpacing.s8),
                  FilledButton.icon(
                    key: const Key('close_inspection_button'),
                    onPressed:
                        closeReason != null || _busy ? null : _closeInspection,
                    icon: _closing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label:
                        Text(_closing ? 'Closing…' : 'Close Inspection'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: GssmsSpacing.s24),
          ],
        ),
      ),
      bottomNavigationBar: _canConvert(session)
          ? StickyActionBar(
              child: FilledButton.icon(
                key: const Key('convert_to_work_order_button'),
                onPressed: _busy ? null : _confirmConvert,
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

/// One evidence-photo row: caption (or fallback), lock/uploader meta.
/// Read-only: recorded inspections cannot be edited or deleted.
class _EvidencePhotoRow extends StatelessWidget {
  const _EvidencePhotoRow({
    required this.photo,
  });

  final InspectionEvidencePhoto photo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      key: Key('insp_photo_row_${photo.id}'),
      padding: const EdgeInsets.symmetric(vertical: GssmsSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  photo.caption?.isNotEmpty == true
                      ? photo.caption!
                      : 'Photo #${photo.id}',
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  photo.isLocked
                      ? 'Locked${photo.uploadedByName != null ? ' • ${photo.uploadedByName}' : ''}'
                      : (photo.uploadedByName ?? ''),
                  style: textTheme.bodySmall
                      ?.copyWith(color: context.gssms.textSecondary),
                ),
              ],
            ),
          ),
          if (photo.isLocked)
            const Icon(Icons.lock_outline, size: 18)
        ],
      ),
    );
  }
}

class _PointCard extends StatelessWidget {
  const _PointCard({
    required this.point,
    required this.inspectionClosed,
    required this.canEdit,
    required this.canApproveJw2,
    required this.acting,
    this.jw1Selected,
    this.onToggleJw1,
    this.onResolve,
    this.onDispose,
    this.onUnresolved,
    this.onApproveJw2,
    this.onCreateJw2,
    this.onEscalate,
    this.session,
    this.onAddPhoto,
  });

  final InspectionPoint point;
  final bool inspectionClosed;
  final bool canEdit;
  final bool canApproveJw2;
  final bool acting;
  final bool? jw1Selected;
  final VoidCallback? onToggleJw1;
  final VoidCallback? onResolve;
  final VoidCallback? onDispose;
  final VoidCallback? onUnresolved;
  final VoidCallback? onApproveJw2;
  final VoidCallback? onCreateJw2;
  final VoidCallback? onEscalate;
  final UserSession? session;

  /// Evidence-photo management (upload while UNASSIGNED, edit/delete while
  /// unlocked) — mirrors web's per-point evidence gate.
  final VoidCallback? onAddPhoto;

  /// Chronological attempt history: JW-001 → verdict → approval → JW-002 →
  /// escalation, from assignments + disposition audit fields. Mirrors web's
  /// per-point execution history drawer (read-only here).
  List<String> get _historyLines {
    final lines = <String>[];
    lines.add('Observed — ${point.observation}');
    final ordered = [...point.jobWorks]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final jw in ordered) {
      lines.add(
          'JW-00${jw.sequence} ${jw.ticketNumber ?? ''} — ${jw.workOrderStatus ?? 'created'}'
              .trim());
    }
    if (point.unresolvedReason?.isNotEmpty == true) {
      lines.add(
          'Marked unresolved${point.unresolvedByName != null ? ' by ${point.unresolvedByName}' : ''} — ${point.unresolvedReason}');
    }
    if (point.jw2ApprovedByName != null) {
      lines.add('JW-002 approved by ${point.jw2ApprovedByName}');
    }
    if (point.dispositionStatus == PointDispositionStatus.resolved) {
      lines.add(
          'Resolved${point.resolvedByName != null ? ' by ${point.resolvedByName}' : ''}${point.resolutionRemarks?.isNotEmpty == true ? ' — ${point.resolutionRemarks}' : ''}');
    }
    if (point.dispositionStatus == PointDispositionStatus.disposed) {
      lines.add(
          'Disposed (${point.disposedReason ?? 'no reason'})${point.disposedRemarks?.isNotEmpty == true ? ' — ${point.disposedRemarks}' : ''}');
    }
    for (final wo in point.escalatedWorkOrders) {
      lines.add(
          'Escalated to ${wo.ticketNumber ?? '#${wo.id}'} (${wo.status ?? ''})');
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: Key('inspection_point_card_${point.id}'),
      margin: const EdgeInsets.only(bottom: GssmsSpacing.s8),
      decoration: BoxDecoration(
        border: Border.all(color: context.gssms.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(GssmsSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Point #${point.pointNumber}',
                    style: textTheme.titleSmall),
              ),
              PointDispositionChip(status: point.dispositionStatus),
            ],
          ),
          const SizedBox(height: GssmsSpacing.s4),
          Text(point.observation, style: textTheme.bodyMedium),
          const SizedBox(height: GssmsSpacing.s4),
          Wrap(
            spacing: GssmsSpacing.s8,
            runSpacing: GssmsSpacing.s4,
            children: [
              PointPriorityChip(priority: point.priority),
              StatusChip(
                label: point.scopeLabel,
                tone: GssmsTone.neutral,
                icon: Icons.build_circle_outlined,
              ),
              if (point.jobWorks.isNotEmpty)
                StatusChip(
                  label: point.jobWorks
                      .map((j) =>
                          'JW-00${j.sequence} ${j.ticketNumber ?? ''}'.trim())
                      .join(', '),
                  tone: GssmsTone.info,
                  icon: Icons.link,
                ),
            ],
          ),
          if (point.resolutionRemarks?.isNotEmpty == true)
            InfoRow(
                label: 'Resolution', value: point.resolutionRemarks),
          if (point.disposedReason?.isNotEmpty == true)
            InfoRow(
                label: 'Disposed',
                value:
                    '${point.disposedReason}${point.disposedRemarks?.isNotEmpty == true ? ' — ${point.disposedRemarks}' : ''}'),
          if (point.unresolvedReason?.isNotEmpty == true)
            InfoRow(
                label: 'Unresolved',
                value:
                    '${point.unresolvedReason}${point.unresolvedRemarks?.isNotEmpty == true ? ' — ${point.unresolvedRemarks}' : ''}'),
          if (point.escalatedWorkOrders.isNotEmpty)
            InfoRow(
              label: 'Escalated',
              value: point.escalatedWorkOrders
                  .map((w) =>
                      '${w.ticketNumber ?? '#${w.id}'} (${w.status ?? ''})')
                  .join(', '),
            ),
          Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: Key('point_history_${point.id}'),
              tilePadding: EdgeInsets.zero,
              title: Text('Execution history (${_historyLines.length})',
                  style: textTheme.labelMedium?.copyWith(
                      color: context.gssms.textSecondary)),
              children: [
                for (var i = 0; i < _historyLines.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: i == _historyLines.length - 1 ? 0 : 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ',
                            style: textTheme.bodySmall?.copyWith(
                                color: context.gssms.textSecondary)),
                        Expanded(
                          child: Text(_historyLines[i],
                              style: textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (point.evidencePhotos.isNotEmpty || onAddPhoto != null) ...[
            const SizedBox(height: GssmsSpacing.s4),
            Text(
                'Evidence (${point.evidencePhotos.length}/$_kMaxPointPhotos)',
                style: textTheme.labelMedium?.copyWith(
                    color: context.gssms.textSecondary)),
            for (final photo in point.evidencePhotos)
              _EvidencePhotoRow(
                photo: photo,
              ),
            if (onAddPhoto != null) ...[
              const SizedBox(height: GssmsSpacing.s4),
              OutlinedButton.icon(
                key: Key('add_point_evidence_${point.id}'),
                onPressed: acting ? null : onAddPhoto,
                icon: const Icon(Icons.photo_camera_outlined, size: 16),
                label: const Text('Add Photo (JPEG only)'),
              ),
            ],
          ],
          if (canEdit && !inspectionClosed) ...[
            const SizedBox(height: GssmsSpacing.s8),
            Wrap(
              spacing: GssmsSpacing.s8,
              runSpacing: GssmsSpacing.s4,
              children: [
                if (onToggleJw1 != null)
                  FilterChip(
                    key: Key('jw1_select_point_${point.id}'),
                    label: const Text('JW-001'),
                    selected: jw1Selected == true,
                    onSelected: acting ? null : (_) => onToggleJw1!(),
                  ),
                if (onResolve != null)
                  OutlinedButton(
                    key: Key('resolve_point_${point.id}'),
                    onPressed: acting ? null : onResolve,
                    child: const Text('Resolve'),
                  ),
                if (onDispose != null)
                  OutlinedButton(
                    key: Key('dispose_point_${point.id}'),
                    onPressed: acting ? null : onDispose,
                    child: const Text('Dispose'),
                  ),
                if (onUnresolved != null)
                  OutlinedButton(
                    key: Key('unresolved_point_${point.id}'),
                    onPressed: acting ? null : onUnresolved,
                    child: const Text('Unresolved'),
                  ),
                if (onApproveJw2 != null)
                  OutlinedButton(
                    key: Key('approve_jw2_point_${point.id}'),
                    onPressed: acting ? null : onApproveJw2,
                    child: const Text('Approve JW-002'),
                  ),
                if (onCreateJw2 != null)
                  OutlinedButton(
                    key: Key('create_jw2_point_${point.id}'),
                    onPressed: acting ? null : onCreateJw2,
                    child: const Text('Create JW-002'),
                  ),
                if (onEscalate != null)
                  OutlinedButton(
                    key: Key('escalate_point_${point.id}'),
                    onPressed: acting ? null : onEscalate,
                    child: const Text('Escalate'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LinkedJobWorkCard extends StatelessWidget {
  const _LinkedJobWorkCard({required this.inspection, this.onOpen});

  final Inspection inspection;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = linkedJobWorkProgress(inspection.workOrderStatus);
    return SectionCard(
      title: 'Linked Job Work',
      icon: Icons.link,
      children: [
        if (inspection.workOrderId != null)
          InfoRow(label: 'Job Work', value: 'Job Work #${inspection.workOrderId}'),
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
            key: const Key('view_linked_work_order'),
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new),
            label: const Text('View Linked Job Work'),
          ),
        ],
      ],
    );
  }
}
