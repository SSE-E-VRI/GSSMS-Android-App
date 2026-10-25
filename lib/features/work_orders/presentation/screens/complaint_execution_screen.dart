import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
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
import 'package:gssms_mobile/features/work_orders/data/pending_execution_photo_store.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_autosave.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_widgets.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/failure_details_section.dart';

/// Technician execution form for COMPLAINT-mode (Breakdown) Job Works.
///
/// Mirrors web `ComplaintExecutionForm`: read-only Breakdown Information,
/// Initial Assessment & Findings, Rectification / Action Taken, optional
/// technical parameters, Before + After photos (10 max per kind, JPEG),
/// Final Remarks (the three texts required), Technician Name, debounced
/// autosave, Save Progress and Sign & Submit → TECH_COMPLETED. Read-only
/// unless the Job Work is IN_PROGRESS. Completeness is enforced
/// server-side; client checks are advisory.
///
/// Photos are captured/picked straight to a durable local file and stay
/// local (surviving app restarts) until Save Progress or Sign & Submit —
/// neither auto-uploads on every Add/Retake tap.
class ComplaintExecutionScreen extends ConsumerStatefulWidget {
  const ComplaintExecutionScreen({
    super.key,
    required this.workOrderId,
    this.ticketNumber,
    this.title,
  });

  final int workOrderId;
  final String? ticketNumber;
  final String? title;

  @override
  ConsumerState<ComplaintExecutionScreen> createState() =>
      _ComplaintExecutionScreenState();
}

class _ComplaintExecutionScreenState
    extends ConsumerState<ComplaintExecutionScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _findingsController = TextEditingController();
  final _actionController = TextEditingController();
  final _remarksController = TextEditingController();

  final _techNameController = TextEditingController();

  ComplaintExecution? _execution;

  /// Breakdown details and Job Work status; null if they could not be
  /// loaded (the form then stays editable and the server decides).
  BreakdownInfo? _info;
  List<Map<String, String>> _params = [];
  int? _failureCode;
  DateTime? _restoredTime;
  String? _failureCodeError;
  String? _restoredTimeError;
  bool _loading = true;
  bool _saving = false;
  bool _submitting = false;
  String? _error;
  bool _hydrating = false;
  late final ExecutionApiService _api;
  late final ExecutionAutosaveController _autosave;

  /// Photos captured/picked this session (or a prior one) that haven't been
  /// uploaded yet — durable on disk via EvidenceService, indexed by
  /// [PendingExecutionPhotoStore] so they survive the app being killed
  /// before Save Progress / Sign & Submit is tapped, and are never swept by
  /// the evidence retention pass.
  final List<PendingExecutionPhoto> _pendingPhotos = [];

  final _pendingStore = const PendingExecutionPhotoStore();

  bool get _busy => _saving || _submitting;

  /// Same rule as the web form and the server: edits only while IN_PROGRESS.
  bool get _editable => _info?.isEditable ?? true;

  @override
  void initState() {
    super.initState();
    _api = ref.read(executionApiServiceProvider);
    _techNameController.text =
        sessionFromAuth(ref.read(authControllerProvider))?.username ?? '';
    _autosave = ExecutionAutosaveController(save: _autosaveSave);
    for (final c in [
      _findingsController,
      _actionController,
      _remarksController,
    ]) {
      attachEditListener(c, _onEdited);
    }
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    unawaited(_loadPendingPhotos());
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
  /// flush still works; the response never overwrites what is being typed
  /// (photos only change through upload/delete, which reload explicitly).
  Future<void> _autosaveSave() async {
    final payload = _draftPayload();
    await _api.saveComplaintDraft(widget.workOrderId, payload);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosave.dispose();
    _findingsController.dispose();
    _actionController.dispose();
    _remarksController.dispose();
    _techNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(executionApiServiceProvider);
      // The breakdown details are context, not required to work: a failure
      // there leaves the form usable (and editable — the server decides).
      final infoFuture = api
          .getBreakdownInfo(widget.workOrderId)
          .then<BreakdownInfo?>((i) => i)
          .catchError((Object _) => null);
      final exec = await api.getComplaintExecution(widget.workOrderId);
      final info = await infoFuture;
      if (!mounted) return;
      _hydrating = true;
      try {
        setState(() {
          _execution = exec;
          _info = info ?? _info;
          _findingsController.text = exec.initialFindings;
          _actionController.text = exec.actionTaken;
          _remarksController.text = exec.finalRemarks;
          _params = exec.parameters
              .map((e) => Map<String, String>.from(e))
              .toList();
          _failureCode = exec.failureCode;
          _restoredTime = exec.restoredTime ??
              (exec.requiresFailureDetails ? DateTime.now() : null);
          _failureCodeError = null;
          _restoredTimeError = null;
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

  /// The signed-in user, who owns the photos captured on this screen.
  int? get _ownerUserId =>
      sessionFromAuth(ref.read(authControllerProvider))?.userId;

  /// Restores this user's pending (not-yet-uploaded) photos left from a
  /// previous session, dropping entries whose local file no longer exists.
  Future<void> _loadPendingPhotos() async {
    final restored = await _pendingStore.load(
      widget.workOrderId,
      ownerUserId: _ownerUserId,
    );
    if (!mounted) return;
    setState(() {
      _pendingPhotos
        ..clear()
        ..addAll(restored);
    });
  }

  Future<void> _persistPendingPhotos() => _pendingStore.save(
        widget.workOrderId,
        List.of(_pendingPhotos),
        ownerUserId: _ownerUserId,
      );

  void _onFailureCodeChanged(int? code) {
    setState(() {
      _failureCode = code;
      _failureCodeError = null;
    });
    _autosave.markEdited();
  }

  void _onRestoredTimeChanged(DateTime? dt) {
    setState(() {
      _restoredTime = dt;
      _restoredTimeError = null;
    });
    _autosave.markEdited();
  }

  Map<String, dynamic> _draftPayload() => {
        'initial_findings': _findingsController.text.trim(),
        'action_taken': _actionController.text.trim(),
        'final_remarks': _remarksController.text.trim(),
        'parameters': _params
            .where((r) =>
                r['parameter']!.isNotEmpty && r['value']!.isNotEmpty)
            .toList(),
        'failure_code': _failureCode,
        'restored_time': _restoredTime?.toIso8601String(),
      };

  /// Save Progress: uploads any pending local photos first (they must be on
  /// the server before a draft save is meaningful), then saves the text
  /// fields. Stops at the first photo upload failure, leaving the rest
  /// pending — nothing already uploaded gets re-sent on retry.
  Future<void> _saveDraft() async {
    setState(() => _saving = true);
    try {
      if (_pendingPhotos.isNotEmpty) {
        final uploaded = await _uploadPendingPhotos();
        if (!mounted) return;
        if (!uploaded) {
          // The photo error is already on screen; still save the typed
          // fields so one failed photo never costs the technician's text.
          await _autosave.flush(manual: true);
          return;
        }
        await _load();
      }
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

  /// Uploads every pending local photo to the server, discarding the local
  /// copy and removing it from [_pendingPhotos] (and the persisted index)
  /// only once the server confirms it. Returns false and surfaces the error
  /// on the first failure, leaving everything from that point on pending —
  /// calling this again never re-uploads what already succeeded.
  Future<bool> _uploadPendingPhotos() async {
    for (final photo in List<PendingExecutionPhoto>.from(_pendingPhotos)) {
      try {
        final filename = photo.localPath.split(Platform.pathSeparator).last;
        await _api.uploadComplaintPhoto(
          widget.workOrderId,
          kind: photo.kind,
          file: await MultipartFile.fromFile(
            photo.localPath,
            filename: filename.isNotEmpty ? filename : 'evidence.jpg',
            contentType: DioMediaType('image', 'jpeg'),
          ),
        );
        await ref.read(evidenceServiceProvider).discard(photo.localPath);
        if (mounted) {
          setState(() => _pendingPhotos.remove(photo));
        } else {
          _pendingPhotos.remove(photo);
        }
        await _persistPendingPhotos();
      } catch (e) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Could not upload a pending photo: ${userFacingError(e)}')),
        );
        return false;
      }
    }
    return true;
  }

  /// Captures/picks a photo and keeps it on-device as pending — it is not
  /// uploaded until Save Progress or Sign & Submit.
  Future<void> _addPhoto(String kind) async {
    final source = await pickExecutionImageSource(context);
    if (source == null || !mounted) return;
    if (source == ImageSource.gallery &&
        !await ref.read(galleryPermissionServiceProvider).request(context)) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final captured = await ref.read(evidenceServiceProvider).capture(
            kind: kind == 'AFTER' ? EvidenceKind.after : EvidenceKind.before,
            source: source,
          );
      if (captured == null || !mounted) return; // user cancelled
      setState(() => _pendingPhotos
          .add(PendingExecutionPhoto(kind: kind, localPath: captured.path)));
      await _persistPendingPhotos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not capture photo: ${userFacingError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deletePhoto(ExecutionPhoto photo) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Delete photo?',
      icon: Icons.delete_outline,
      message: 'This execution photo will be permanently deleted.',
      confirmLabel: 'Delete',
      confirmKey: Key('confirm_delete_exec_photo_${photo.id}'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(executionApiServiceProvider)
          .deleteComplaintPhoto(widget.workOrderId, photo.id);
      await _autosave.flush();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: ${userFacingError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Already-uploaded photo retake: still swaps immediately (upload
  /// replacement, then delete old) rather than deferring — the photo being
  /// replaced is already safely on the server, so there's no local-only
  /// state to stage; only newly-added photos defer to Save/Submit.
  Future<void> _retakePhoto(ExecutionPhoto photo) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Retake photo?',
      icon: Icons.replay_outlined,
      message:
          'Capture a new photo to replace this one. The old photo stays until the new one uploads successfully.',
      confirmLabel: 'Retake',
      confirmKey: Key('confirm_retake_exec_photo_${photo.id}'),
    );
    if (!confirmed || !mounted) return;
    final source = await pickExecutionImageSource(context);
    if (source == null || !mounted) return;
    if (source == ImageSource.gallery &&
        !await ref.read(galleryPermissionServiceProvider).request(context)) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final captured = await ref.read(evidenceServiceProvider).capture(
            kind: (photo.kind ?? 'BEFORE') == 'AFTER'
                ? EvidenceKind.after
                : EvidenceKind.before,
            source: source,
          );
      if (captured == null || !mounted) return;
      final filename = captured.path.split(Platform.pathSeparator).last;
      await _api.uploadComplaintPhoto(
        widget.workOrderId,
        kind: photo.kind ?? 'BEFORE',
        file: await MultipartFile.fromFile(
          captured.path,
          filename: filename.isNotEmpty ? filename : 'evidence.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      );
      await ref.read(evidenceServiceProvider).discard(captured.path);
      await ref
          .read(executionApiServiceProvider)
          .deleteComplaintPhoto(widget.workOrderId, photo.id);
      await _autosave.flush();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not retake photo: ${userFacingError(e)}')),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Pending (not-yet-uploaded) photo retake: purely local, no network —
  /// discard the old local file and capture a new one in its place.
  Future<void> _retakePendingPhoto(PendingExecutionPhoto photo) async {
    final source = await pickExecutionImageSource(context);
    if (source == null || !mounted) return;
    if (source == ImageSource.gallery &&
        !await ref.read(galleryPermissionServiceProvider).request(context)) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final captured = await ref.read(evidenceServiceProvider).capture(
            kind: photo.kind == 'AFTER' ? EvidenceKind.after : EvidenceKind.before,
            source: source,
          );
      if (captured == null || !mounted) return;
      await ref.read(evidenceServiceProvider).discard(photo.localPath);
      final index = _pendingPhotos.indexOf(photo);
      if (index >= 0) {
        setState(() => _pendingPhotos[index] =
            PendingExecutionPhoto(kind: photo.kind, localPath: captured.path));
      }
      await _persistPendingPhotos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not capture photo: ${userFacingError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Pending (not-yet-uploaded) photo delete: local-only, no network call.
  Future<void> _deletePendingPhoto(PendingExecutionPhoto photo) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Remove photo?',
      icon: Icons.delete_outline,
      message:
          'This photo has not been uploaded yet and will be removed from this device.',
      confirmLabel: 'Remove',
      confirmKey: Key('confirm_delete_pending_photo_${photo.localPath.hashCode}'),
    );
    if (!confirmed || !mounted) return;
    await ref.read(evidenceServiceProvider).discard(photo.localPath);
    setState(() => _pendingPhotos.remove(photo));
    await _persistPendingPhotos();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Submit's Before/After check reads server state, so any pending local
    // photos must land on the server — and _execution must be refreshed —
    // before that check runs, or a fully-captured-but-not-yet-saved pair
    // would be wrongly rejected as missing.
    if (_pendingPhotos.isNotEmpty) {
      setState(() => _submitting = true);
      final uploaded = await _uploadPendingPhotos();
      if (!mounted) return;
      setState(() => _submitting = false);
      if (!uploaded) return;
      await _load();
      if (!mounted) return;
    }
    final exec = _execution;
    if (exec != null && (!exec.hasBefore || !exec.hasAfter)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'A Before and an After photo are both required before completion.')),
      );
      return;
    }
    if (exec?.requiresFailureDetails == true) {
      var hasIsoError = false;
      if (_failureCode == null) {
        _failureCodeError =
            'Failure Code is mandatory for Critical Asset maintenance logs (ISO 55000).';
        hasIsoError = true;
      }
      if (_restoredTime == null) {
        _restoredTimeError =
            'Restored Time is mandatory for Critical Asset maintenance logs (ISO 55000).';
        hasIsoError = true;
      }
      if (hasIsoError) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Failure Code and Restored Time are mandatory for Critical/High criticality assets (ISO 55000).'),
          ),
        );
        return;
      }
    }
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Sign & Submit?',
      icon: Icons.verified_outlined,
      message:
          'This moves the Job Work to Technically Completed for supervisor verification.',
      confirmLabel: 'Submit',
      confirmKey: const Key('confirm_submit_complaint_execution'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _submitting = true);
    try {
      await _autosave.flush();
      final session = sessionFromAuth(ref.read(authControllerProvider));
      // The name signed on the report: what the technician typed, else the
      // login name (web: techSignatureName || username).
      final typedName = _techNameController.text.trim();
      final technicianName =
          typedName.isNotEmpty ? typedName : (session?.username ?? '');
      await ref.read(executionApiServiceProvider).submitComplaintExecution(
        widget.workOrderId,
        {
          ..._draftPayload(),
          'remarks': _remarksController.text.trim(),
          if (technicianName.isNotEmpty) 'technician_name': technicianName,
          'technician_signature': 'SIGNED_DIGITALLY',
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Execution submitted.')),
      );
      _autosave.markSubmitted();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && e.response?.data is Map) {
        final data = e.response!.data as Map;
        final fields = data['fields'] is Map ? data['fields'] as Map : null;
        if (fields != null) {
          setState(() {
            if (fields['failure_code'] != null) {
              _failureCodeError = fields['failure_code'].toString();
            }
            if (fields['restored_time'] != null) {
              _restoredTimeError = fields['restored_time'].toString();
            }
          });
        }
      }
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
        appBar: AppBar(title: const Text('Breakdown Execution')),
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
              ? 'Breakdown Execution ${widget.ticketNumber}'
              : 'Breakdown Execution')),
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
                  onRefresh: _load,
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (widget.title != null &&
                            widget.title!.trim().isNotEmpty)
                          SectionCard(children: [
                            Text(widget.title!,
                                style: Theme.of(context).textTheme.titleMedium),
                          ]),
                        if (widget.title != null &&
                            widget.title!.trim().isNotEmpty)
                          const SizedBox(height: 12),
                        if (_info != null) ...[
                          _breakdownInfoCard(context, _info!),
                          const SizedBox(height: 12),
                        ],
                        if (!_editable) ...[
                          _readOnlyNotice(context, _info!),
                          const SizedBox(height: 12),
                        ],
                        SectionCard(
                          title: 'Findings & Action',
                          icon: Icons.fact_check_outlined,
                          children: [
                            TextFormField(
                              key: const Key('exec_findings_field'),
                              controller: _findingsController,
                              enabled: !_busy && _editable,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText:
                                    'Initial Assessment & Findings *',
                                helperText: 'What was observed / diagnosed',
                                hintText:
                                    'e.g. Equipment found operational during inspection. Reported fault could not be reproduced.',
                                hintMaxLines: 3,
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty
                                      ? 'Findings are required'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('exec_action_field'),
                              controller: _actionController,
                              enabled: !_busy && _editable,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText:
                                    'Rectification / Action Taken *',
                                helperText: 'What was actually done',
                                hintText:
                                    'e.g. Loose terminal tightened; supply restored.',
                                hintMaxLines: 2,
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty
                                      ? 'Action taken is required'
                                      : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SectionCard(
                          title: 'Technical Parameters (Optional)',
                          icon: Icons.tune_outlined,
                          children: [
                            ParamRowsEditor(
                              initial: _params,
                              enabled: !_busy,
                              readOnly: !_editable,
                              emptyText:
                                  'No parameters applicable to this breakdown.',
                              parameterHint: 'e.g. R-Y Voltage',
                              onChanged: (rows) {
                                setState(() => _params = rows);
                                _autosave.markEdited();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SectionCard(
                          title: 'Before / After Photos',
                          icon: Icons.camera_alt_outlined,
                          children: [
                            ExecutionPhotoGrid(
                              photos: _execution?.photos ?? const [],
                              pendingPhotos: _pendingPhotos,
                              canManage: _editable,
                              busy: _busy,
                              // Matches the server and web (10 per kind,
                              // including the complaint's own locked photos).
                              maxPerKind: 10,
                              onAdd: _addPhoto,
                              onDelete: _deletePhoto,
                              onRetake: _retakePhoto,
                              onDeletePending: _deletePendingPhoto,
                              onRetakePending: _retakePendingPhoto,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // After the photos, as on the web: the outcome is
                        // written once the work and its evidence are done.
                        SectionCard(
                          title: 'Final Remarks',
                          icon: Icons.flag_outlined,
                          children: [
                            TextFormField(
                              key: const Key('exec_remarks_field'),
                              controller: _remarksController,
                              enabled: !_busy && _editable,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Final Remarks *',
                                helperText: 'Final outcome',
                                hintText:
                                    'e.g. Equipment restored to normal operation.',
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty
                                      ? 'Final remarks are required'
                                      : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FailureDetailsSection(
                          assetCriticality: _execution?.assetCriticality,
                          requiresFailureDetails:
                              _execution?.requiresFailureDetails ?? false,
                          failureCode: _failureCode,
                          onFailureCodeChanged: _busy || !_editable
                              ? null
                              : _onFailureCodeChanged,
                          restoredTime: _restoredTime,
                          onRestoredTimeChanged: _busy || !_editable
                              ? null
                              : _onRestoredTimeChanged,
                          // Web falls back to the complaint's creation time.
                          breakdownTime: _execution?.breakdownTime ??
                              _info?.complaintCreatedAt,
                          failureCodeOptions:
                              _execution?.failureCodeOptions ?? const [],
                          enabled: !_busy && _editable,
                          failureCodeError: _failureCodeError,
                          restoredTimeError: _restoredTimeError,
                        ),
                        if (_editable) ...[
                          const SizedBox(height: 12),
                          SectionCard(
                            title: 'Sign & Submit',
                            icon: Icons.draw_outlined,
                            children: [
                              TextFormField(
                                key: const Key('exec_technician_name_field'),
                                controller: _techNameController,
                                enabled: !_busy,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Technician Name',
                                  helperText:
                                      'Signed on the report. Defaults to your login name.',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          AutosaveStatusLine(controller: _autosave),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: const Key('save_exec_draft_button'),
                                  onPressed: _busy ? null : _saveDraft,
                                  icon: const Icon(Icons.save_outlined),
                                  label: Text(
                                      _saving ? 'Saving…' : 'Save Progress'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  key: const Key('submit_exec_button'),
                                  onPressed: _busy ? null : _submit,
                                  icon: const Icon(Icons.verified_outlined),
                                  label: Text(_submitting
                                      ? 'Submitting…'
                                      : 'Sign & Submit'),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  /// The web form's read-only "Breakdown Information" block: what was
  /// reported, so the technician works with the complaint in view.
  Widget _breakdownInfoCard(BuildContext context, BreakdownInfo info) {
    String orDash(String v) => v.trim().isEmpty ? '—' : v;
    final date = info.failureDate == null
        ? '—'
        : DateFormat('dd/MM/yyyy').format(info.failureDate!);
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: context.gssms.textSecondary,
      letterSpacing: 0.4,
    );
    Widget field(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: labelStyle),
            const SizedBox(height: 2),
            Text(value, style: theme.textTheme.bodyMedium),
          ],
        );
    Widget pair(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ],
        );
    return SectionCard(
      key: const Key('breakdown_info_card'),
      title: 'Breakdown Information',
      icon: Icons.campaign_outlined,
      children: [
        pair(
          field('Job Work', orDash(info.ticket)),
          field('Complainant', orDash(info.complainant)),
        ),
        const SizedBox(height: 10),
        pair(
          field('Failure Date', date),
          field('Failure Time', orDash(info.failureTime)),
        ),
        const SizedBox(height: 10),
        pair(
          field('Reported Asset', orDash(info.reportedAsset)),
          field('Station / Location', orDash(info.station)),
        ),
        const SizedBox(height: 10),
        Text('ORIGINAL BREAKDOWN DESCRIPTION', style: labelStyle),
        const SizedBox(height: 4),
        // Read-only, always: the complainant's record (web R4).
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.gssms.surfaceInset,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(orDash(info.description),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: context.gssms.textSecondary)),
        ),
      ],
    );
  }

  Widget _readOnlyNotice(BuildContext context, BreakdownInfo info) {
    final status = info.status
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0]}${w.substring(1).toLowerCase()}')
        .join(' ');
    final tone = context.gssms.warning;
    return Container(
      key: const Key('exec_read_only_notice'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: tone.foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This Job Work is ${status.isEmpty ? 'not in progress' : status}. '
              'It can be edited only while In Progress, so this form is read-only.',
              style: TextStyle(color: tone.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
