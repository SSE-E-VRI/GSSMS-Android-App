import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/data/execution_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_autosave.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_widgets.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/failure_details_section.dart';

/// Technician execution form for COMPLAINT-mode (Breakdown) Job Works.
///
/// Mirrors web `ComplaintExecutionForm`: Initial Assessment & Findings,
/// Rectification / Action Taken, Final Remarks (all required), technical
/// parameters, Before + After photos (5 max per kind, JPEG), debounced
/// autosave, Save Progress and Sign & Submit → TECH_COMPLETED. Completeness is enforced
/// server-side; client checks are advisory.
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

  ComplaintExecution? _execution;
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

  bool get _busy => _saving || _submitting;

  @override
  void initState() {
    super.initState();
    _api = ref.read(executionApiServiceProvider);
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final exec = await ref
          .read(executionApiServiceProvider)
          .getComplaintExecution(widget.workOrderId);
      if (!mounted) return;
      _hydrating = true;
      try {
        setState(() {
          _execution = exec;
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

  /// Picks a JPEG from the gallery and uploads it for [kind]. Returns null
  /// if the user cancelled or picked an unusable file (no error, nothing
  /// happened), true once the upload is confirmed on the server, or false
  /// if the upload itself failed (error already shown).
  Future<bool?> _pickAndUploadPhoto(String kind) async {
    XFile? picked;
    try {
      picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
    } catch (_) {
      return null;
    }
    if (picked == null || !mounted) return null;
    final lower = picked.path.toLowerCase();
    if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only JPEG photos are allowed.')),
      );
      return null;
    }
    try {
      final file = File(picked.path);
      if (!await file.exists()) return null;
      final filename = picked.path.split(Platform.pathSeparator).last;
      await ref.read(executionApiServiceProvider).uploadComplaintPhoto(
            widget.workOrderId,
            kind: kind,
            file: await MultipartFile.fromFile(
              picked.path,
              filename: filename.isNotEmpty ? filename : 'evidence.jpg',
              contentType: DioMediaType('image', 'jpeg'),
            ),
          );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload: ${userFacingError(e)}')),
      );
      return false;
    }
  }

  Future<void> _addPhoto(String kind) async {
    setState(() => _saving = true);
    try {
      await _pickAndUploadPhoto(kind);
      await _autosave.flush();
      await _load();
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

  /// Uploads a replacement photo first, then removes [photo] — only once the
  /// new one is confirmed on the server, so a failed pick/upload never
  /// leaves the record with neither photo.
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
    setState(() => _saving = true);
    try {
      final uploaded = await _pickAndUploadPhoto(photo.kind ?? 'BEFORE');
      // null: user cancelled or picked something unusable — leave the old
      // photo in place. false: upload failed, error already shown above.
      // Only a confirmed upload (true) clears the way to delete the old one.
      if (uploaded != true || !mounted) return;
      await ref
          .read(executionApiServiceProvider)
          .deleteComplaintPhoto(widget.workOrderId, photo.id);
      await _autosave.flush();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('New photo uploaded, but could not remove the old one: ${userFacingError(e)}')),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
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
      await ref.read(executionApiServiceProvider).submitComplaintExecution(
        widget.workOrderId,
        {
          ..._draftPayload(),
          'remarks': _remarksController.text.trim(),
          if (session?.username.isNotEmpty == true)
            'technician_name': session!.username,
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
                        SectionCard(
                          title: 'Findings & Action',
                          icon: Icons.fact_check_outlined,
                          children: [
                            TextFormField(
                              key: const Key('exec_findings_field'),
                              controller: _findingsController,
                              enabled: !_busy,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText:
                                    'Initial Assessment & Findings *',
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
                              enabled: !_busy,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText:
                                    'Rectification / Action Taken *',
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty
                                      ? 'Action taken is required'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('exec_remarks_field'),
                              controller: _remarksController,
                              enabled: !_busy,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Final Remarks *',
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty
                                      ? 'Final remarks are required'
                                      : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SectionCard(
                          title: 'Technical Parameters',
                          icon: Icons.tune_outlined,
                          children: [
                            ParamRowsEditor(
                              initial: _params,
                              enabled: !_busy,
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
                              canManage: true,
                              busy: _busy,
                              maxPerKind: 5,
                              onAdd: _addPhoto,
                              onDelete: _deletePhoto,
                              onRetake: _retakePhoto,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FailureDetailsSection(
                          assetCriticality: _execution?.assetCriticality,
                          requiresFailureDetails:
                              _execution?.requiresFailureDetails ?? false,
                          failureCode: _failureCode,
                          onFailureCodeChanged:
                              _busy ? null : _onFailureCodeChanged,
                          restoredTime: _restoredTime,
                          onRestoredTimeChanged:
                              _busy ? null : _onRestoredTimeChanged,
                          breakdownTime: _execution?.breakdownTime,
                          failureCodeOptions:
                              _execution?.failureCodeOptions ?? const [],
                          enabled: !_busy,
                          failureCodeError: _failureCodeError,
                          restoredTimeError: _restoredTimeError,
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
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }
}
