import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/utils/gallery_permission.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/execution_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_autosave.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_widgets.dart';

/// Technician execution form for INSPECTION-mode Job Works.
///
/// Mirrors web `InspectionExecutionForm` (pointwise): one card per assigned
/// point (initial findings, action taken, final remarks, corrective-action
/// switch, technical parameters, Before/After photos up to 5 each), general
/// header context, debounced autosave, Save Progress and Submit → TECH_COMPLETED. Completeness
/// (field text + per-point photo proof) is enforced server-side; client
/// checks only preview it.
class InspectionExecutionScreen extends ConsumerStatefulWidget {
  const InspectionExecutionScreen({
    super.key,
    required this.workOrderId,
    this.ticketNumber,
    this.title,
  });

  final int workOrderId;
  final String? ticketNumber;
  final String? title;

  @override
  ConsumerState<InspectionExecutionScreen> createState() =>
      _InspectionExecutionScreenState();
}

class _PointDraft {
  _PointDraft({
    required this.findings,
    required this.action,
    required this.remarks,
    required this.corrective,
    required this.params,
  });

  final TextEditingController findings;
  final TextEditingController action;
  final TextEditingController remarks;
  bool corrective;
  List<Map<String, String>> params;

  void dispose() {
    findings.dispose();
    action.dispose();
    remarks.dispose();
  }
}

class _InspectionExecutionScreenState
    extends ConsumerState<InspectionExecutionScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();

  PointwiseInspectionExecution? _execution;
  final Map<int, _PointDraft> _drafts = {};
  bool _loading = true;
  bool _saving = false;
  bool _submitting = false;
  String? _error;
  bool _hydrating = false;
  late final ExecutionApiService _api;
  late final ExecutionAutosaveController _autosave;

  bool get _busy => _saving || _submitting;

  String get _headerTitle {
    final number = _execution?.inspectionNumber;
    final title = (_execution?.inspectionTitle?.trim().isNotEmpty == true)
        ? _execution!.inspectionTitle!.trim()
        : (widget.title?.trim() ?? '');
    if (number != null && number.isNotEmpty) {
      return title.isNotEmpty ? '$number - $title' : number;
    }
    return title;
  }

  @override
  void initState() {
    super.initState();
    _api = ref.read(executionApiServiceProvider);
    _autosave = ExecutionAutosaveController(save: _autosaveSave);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _onEdited() {
    if (!_hydrating) _autosave.markEdited();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_autosave.flush());
    }
  }

  /// Autosave write. The payload is captured synchronously so the unmount
  /// flush still works; the response never touches the input controllers.
  Future<void> _autosaveSave() async {
    final points = _pointPayloads();
    await _api.saveInspectionDraft(widget.workOrderId, {
      'points': points,
      'point_executions': points,
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosave.dispose();
    for (final d in _drafts.values) {
      d.dispose();
    }
    super.dispose();
  }

  void _syncDrafts(PointwiseInspectionExecution exec) {
    final seen = <int>{};
    for (final pt in exec.points) {
      seen.add(pt.pointJobWorkId);
      final existing = _drafts[pt.pointJobWorkId];
      if (existing == null) {
        final draft = _PointDraft(
          findings: TextEditingController(text: pt.initialFindings),
          action: TextEditingController(text: pt.actionTaken),
          remarks: TextEditingController(text: pt.finalRemarks),
          corrective: pt.correctiveActionPerformed,
          params: pt.technicalParameters
              .map((e) => Map<String, String>.from(e))
              .toList(),
        );
        attachEditListener(draft.findings, _onEdited);
        attachEditListener(draft.action, _onEdited);
        attachEditListener(draft.remarks, _onEdited);
        _drafts[pt.pointJobWorkId] = draft;
      } else {
        existing.findings.text = pt.initialFindings;
        existing.action.text = pt.actionTaken;
        existing.remarks.text = pt.finalRemarks;
        existing.corrective = pt.correctiveActionPerformed;
        existing.params = pt.technicalParameters
            .map((e) => Map<String, String>.from(e))
            .toList();
      }
    }
    for (final id in _drafts.keys.toList()) {
      if (!seen.contains(id)) _drafts.remove(id)?.dispose();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Initialize is idempotent: creates empty per-point rows (and the
      // header record) so PATCH/submit always have something to write to.
      final exec = await ref
          .read(executionApiServiceProvider)
          .initializeInspectionExecution(widget.workOrderId);
      if (!mounted) return;
      _hydrating = true;
      try {
        setState(() {
          _execution = exec;
          _syncDrafts(exec);
        });
      } finally {
        _hydrating = false;
      }
      _autosave.markClean();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final exec = await ref
          .read(executionApiServiceProvider)
          .getInspectionExecution(widget.workOrderId);
      if (!mounted) return;
      _hydrating = true;
      try {
        setState(() {
          _execution = exec;
          _syncDrafts(exec);
        });
      } finally {
        _hydrating = false;
      }
      _autosave.markClean();
    } catch (_) {
      // Photo mutations already surfaced their own result; a stale-refresh
      // failure must not mask it.
    }
  }

  List<Map<String, dynamic>> _pointPayloads() {
    final points = _execution?.points ?? [];
    return points.map((pt) {
      final draft = _drafts[pt.pointJobWorkId];
      final params = (draft?.params ?? [])
          .where((r) =>
              r['parameter']!.isNotEmpty && r['value']!.isNotEmpty)
          .toList();
      return {
        'point_job_work_id': pt.pointJobWorkId,
        'id': pt.pointJobWorkId,
        'initial_findings': draft?.findings.text.trim() ?? '',
        'action_taken': draft?.action.text.trim() ?? '',
        'final_remarks': draft?.remarks.text.trim() ?? '',
        'corrective_action_performed': draft?.corrective ?? true,
        'technical_parameters': params,
        'parameters': params,
      };
    }).toList();
  }

  Future<void> _saveDraft() async {
    setState(() => _saving = true);
    try {
      final ok = await _autosave.flush(manual: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Progress saved.'
              : 'Could not save: ${_autosave.lastError}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Lets the user choose camera or gallery, then captures/picks a photo
  /// through [EvidenceService] — scaled to 1600px, re-encoded as JPEG and
  /// stripped of EXIF/GPS on the phone, like every other evidence photo.
  /// Returns null if the user cancelled the source choice, gallery
  /// permission was refused, or the picker was cancelled. The caller owns
  /// the returned local copy and discards it after the upload attempt.
  Future<EvidenceFile?> _pickPhoto(String kind) async {
    final source = await pickExecutionImageSource(context);
    if (source == null || !mounted) return null;
    if (source == ImageSource.gallery &&
        !await ref.read(galleryPermissionServiceProvider).request(context)) {
      return null;
    }
    if (!mounted) return null;
    try {
      return await ref.read(evidenceServiceProvider).capture(
            kind: kind.toUpperCase() == 'AFTER'
                ? EvidenceKind.after
                : EvidenceKind.before,
            source: source,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture photo: ${userFacingError(e)}')),
        );
      }
      return null;
    }
  }

  Future<void> _addPhoto(
      InspectionPointExecutionEntry point, String kind) async {
    if (point.photos
            .where((p) => (p.kind ?? '').toUpperCase() == kind.toUpperCase())
            .length >=
        5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Maximum 5 ${kind.toLowerCase()} photos allowed for this point.')),
      );
      return;
    }
    final picked = await _pickPhoto(kind);
    if (picked == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final filename = picked.path.split(Platform.pathSeparator).last;
      await ref.read(executionApiServiceProvider).uploadInspectionPhoto(
            widget.workOrderId,
            pointJobWorkId: point.pointJobWorkId,
            photoType: kind,
            file: await MultipartFile.fromFile(
              picked.path,
              filename: filename.isNotEmpty ? filename : 'evidence.jpg',
              contentType: DioMediaType('image', 'jpeg'),
            ),
          );
      await _autosave.flush();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload: ${userFacingError(e)}')),
      );
    } finally {
      await _discard(picked.path);
      if (mounted) setState(() => _saving = false);
    }
  }

  /// This screen uploads immediately and keeps nothing for later, so the
  /// local copy goes whether the upload worked or not (a failure shows an
  /// error and the user retakes).
  Future<void> _discard(String path) async {
    try {
      await ref.read(evidenceServiceProvider).discard(path);
    } catch (_) {}
  }

  Future<void> _deletePhoto(ExecutionPhoto photo) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Delete photo?',
      icon: Icons.delete_outline,
      message: 'This execution photo will be permanently deleted.',
      confirmLabel: 'Delete',
      confirmKey: Key('confirm_delete_insp_exec_photo_${photo.id}'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(executionApiServiceProvider)
          .deleteInspectionPhoto(widget.workOrderId, photo.id);
      await _autosave.flush();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: ${userFacingError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Uploads a replacement photo first, then removes [photo] — only once
  /// the new one is confirmed on the server, so a failed pick/upload never
  /// leaves the point with neither photo.
  Future<void> _retakePhoto(
      InspectionPointExecutionEntry point, ExecutionPhoto photo) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Retake photo?',
      icon: Icons.replay_outlined,
      message:
          'Capture a new photo to replace this one. The old photo stays until the new one uploads successfully.',
      confirmLabel: 'Retake',
      confirmKey: Key('confirm_retake_insp_exec_photo_${photo.id}'),
    );
    if (!confirmed || !mounted) return;
    final picked = await _pickPhoto(photo.kind ?? 'BEFORE');
    if (picked == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final filename = picked.path.split(Platform.pathSeparator).last;
      await ref.read(executionApiServiceProvider).uploadInspectionPhoto(
            widget.workOrderId,
            pointJobWorkId: point.pointJobWorkId,
            photoType: photo.kind ?? 'BEFORE',
            file: await MultipartFile.fromFile(
              picked.path,
              filename: filename.isNotEmpty ? filename : 'evidence.jpg',
              contentType: DioMediaType('image', 'jpeg'),
            ),
          );
      await ref
          .read(executionApiServiceProvider)
          .deleteInspectionPhoto(widget.workOrderId, photo.id);
      await _autosave.flush();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not retake photo: ${userFacingError(e)}')),
      );
      await _refresh();
    } finally {
      await _discard(picked.path);
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Advisory pre-check; the server's proof rules decide authoritatively.
  String? _blockedReason() {
    final points = _execution?.points ?? [];
    if (points.isEmpty) return 'This Job Work has no assigned points.';
    for (final pt in points) {
      final draft = _drafts[pt.pointJobWorkId];
      final label = 'Point #${pt.pointNumber}';
      if ((draft?.findings.text.trim().isEmpty ?? true)) {
        return '$label: initial findings are required.';
      }
      if ((draft?.action.text.trim().isEmpty ?? true)) {
        return '$label: action taken is required.';
      }
      if ((draft?.remarks.text.trim().isEmpty ?? true)) {
        return '$label: final remarks are required.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final blocked = _blockedReason();
    if (blocked != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Submit execution?',
      icon: Icons.verified_outlined,
      message:
          'This moves the Job Work to Technically Completed for supervisor verification.',
      confirmLabel: 'Submit',
      confirmKey: const Key('confirm_submit_inspection_execution'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _submitting = true);
    try {
      await _autosave.flush();
      final payloads = _pointPayloads();
      final first =
          payloads.isNotEmpty ? payloads.first : <String, dynamic>{};
      await ref.read(executionApiServiceProvider).submitInspectionExecution(
        widget.workOrderId,
        {
          'is_pointwise': true,
          'point_executions': payloads,
          'points': payloads,
          'initial_findings': first['initial_findings'] ?? '',
          'action_taken': first['action_taken'] ?? '',
          'final_remarks': first['final_remarks'] ?? '',
          'corrective_action_performed':
              first['corrective_action_performed'] ?? true,
          'technical_parameters': first['technical_parameters'] ?? [],
          'parameters': first['technical_parameters'] ?? [],
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inspection execution submitted.')),
      );
      _autosave.markSubmitted();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit: ${userFacingError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = sessionFromAuth(ref.watch(authControllerProvider));
    if (!sessionAllows(session, 'maintenance.edit')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inspection Execution')),
        body: const PermissionDeniedView(),
      );
    }

    return ListenableBuilder(
      listenable: _autosave,
      builder: (_, child) => PopScope(
        canPop: !_autosave.isDirty && !_autosave.isSaving,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final ok = await _autosave.flush();
          if (!mounted) return;
          if (ok) {
            Navigator.of(this.context).pop();
          } else if (await confirmDiscardUnsaved(this.context)) {
            if (mounted) Navigator.of(this.context).pop();
          }
        },
        child: child!,
      ),
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.ticketNumber != null
              ? 'Inspection Execution ${widget.ticketNumber}'
              : 'Inspection Execution')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if ((_execution?.inspectionNumber != null &&
                                _execution!
                                    .inspectionNumber!.isNotEmpty) ||
                            (widget.title != null &&
                                widget.title!.trim().isNotEmpty))
                          SectionCard(children: [
                            Text(
                                _headerTitle,
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                            if (_execution?.stationName != null)
                              Text(
                                  '${_execution!.stationName ?? ''}${_execution?.inspectorName != null ? ' • ${_execution!.inspectorName}' : ''}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: context
                                              .gssms.textSecondary)),
                          ]),
                        if ((_execution?.inspectionNumber != null &&
                                _execution!
                                    .inspectionNumber!.isNotEmpty) ||
                            (widget.title != null &&
                                widget.title!.trim().isNotEmpty))
                          const SizedBox(height: 12),
                        if ((_execution?.generalEvidencePhotos ?? const [])
                            .isNotEmpty) ...[
                          SectionCard(
                            key: const Key('insp_exec_general_evidence'),
                            title: 'Inspection evidence',
                            icon: Icons.camera_alt_outlined,
                            children: [
                              InspectorEvidenceStrip(
                                label: 'General photos',
                                photos: _execution!.generalEvidencePhotos,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        for (final pt in _execution?.points ?? [])
                          _pointCard(pt),
                        const SizedBox(height: 16),
                        AutosaveStatusLine(controller: _autosave),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const Key('save_insp_exec_draft_button'),
                                onPressed: _busy ? null : _saveDraft,
                                icon: const Icon(Icons.save_outlined),
                                label: Text(
                                    _saving ? 'Saving…' : 'Save Progress'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                key: const Key('submit_insp_exec_button'),
                                onPressed: _busy ? null : _submit,
                                icon:
                                    const Icon(Icons.verified_outlined),
                                label: Text(_submitting
                                    ? 'Submitting…'
                                    : 'Submit'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _pointCard(InspectionPointExecutionEntry pt) {
    final draft = _drafts[pt.pointJobWorkId];
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: Key('insp_exec_point_${pt.pointJobWorkId}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: context.gssms.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Point #${pt.pointNumber}',
              style: textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(pt.observation, style: textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextFormField(
            key: Key('insp_exec_findings_${pt.pointJobWorkId}'),
            controller: draft?.findings,
            enabled: !_busy,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Initial findings *',
            ),
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Findings are required'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: Key('insp_exec_action_${pt.pointJobWorkId}'),
            controller: draft?.action,
            enabled: !_busy,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Action taken *',
            ),
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Action taken is required'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: Key('insp_exec_remarks_${pt.pointJobWorkId}'),
            controller: draft?.remarks,
            enabled: !_busy,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Final remarks *',
            ),
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Final remarks are required'
                : null,
          ),
          SwitchListTile(
            key: Key('insp_exec_corrective_${pt.pointJobWorkId}'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Corrective action performed'),
            value: draft?.corrective ?? true,
            onChanged: _busy
                ? null
                : (v) {
                    setState(() {
                      if (draft != null) draft.corrective = v;
                    });
                    _autosave.markEdited();
                  },
          ),
          ParamRowsEditor(
            initial: draft?.params ?? const [],
            enabled: !_busy,
            onChanged: (rows) {
              setState(() {
                if (draft != null) draft.params = rows;
              });
              _autosave.markEdited();
            },
          ),
          const SizedBox(height: 8),
          if (pt.inspectionEvidencePhotos.isNotEmpty) ...[
            // The inspector's photos of this point (web parity). On the
            // server they already count as this point's Before evidence.
            InspectorEvidenceStrip(
              key: Key('insp_exec_inspector_photos_${pt.pointJobWorkId}'),
              label: 'From the inspection',
              photos: pt.inspectionEvidencePhotos,
            ),
            const SizedBox(height: 8),
          ],
          ExecutionPhotoGrid(
            photos: pt.photos,
            canManage: true,
            busy: _busy,
            maxPerKind: 5,
            onAdd: (kind) => _addPhoto(pt, kind),
            onDelete: _deletePhoto,
            onRetake: (photo) => _retakePhoto(pt, photo),
          ),
        ],
      ),
    );
  }
}
