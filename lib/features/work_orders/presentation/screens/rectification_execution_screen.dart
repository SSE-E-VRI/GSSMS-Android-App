import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/data/execution_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_autosave.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_widgets.dart';

/// Technician execution form for RECTIFICATION-mode (deficiency) Job Works.
///
/// Mirrors web `RectificationExecutionForm`: one card per deficiency item
/// (action taken, outcome, reason, Before/After photos), plus the final
/// outcome remarks. Server completeness (action + outcome + Before photo per
/// item, After photo when rectified, reason when not, final remarks) is
/// enforced authoritatively — client checks only preview it.
class RectificationExecutionScreen extends ConsumerStatefulWidget {
  const RectificationExecutionScreen({
    super.key,
    required this.workOrderId,
    this.ticketNumber,
    this.title,
  });

  final int workOrderId;
  final String? ticketNumber;
  final String? title;

  @override
  ConsumerState<RectificationExecutionScreen> createState() =>
      _RectificationExecutionScreenState();
}

class _ItemDraft {
  _ItemDraft({
    required this.action,
    required this.outcome,
    required this.reason,
  });

  final TextEditingController action;
  String outcome;
  final TextEditingController reason;

  void dispose() {
    action.dispose();
    reason.dispose();
  }
}

class _RectificationExecutionScreenState
    extends ConsumerState<RectificationExecutionScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _finalRemarksController = TextEditingController();
  final _otherStaffController = TextEditingController();

  RectificationPayload? _payload;
  final Map<int, _ItemDraft> _drafts = {};
  bool _loading = true;
  bool _saving = false;
  bool _submitting = false;
  String? _error;
  bool _hydrating = false;
  late final ExecutionApiService _api;
  late final ExecutionAutosaveController _autosave;

  bool get _busy => _saving || _submitting;

  static const _outcomes = ['', 'RECTIFIED', 'NOT_RECTIFIED'];

  @override
  void initState() {
    super.initState();
    _api = ref.read(executionApiServiceProvider);
    _autosave = ExecutionAutosaveController(save: _autosaveSave);
    attachEditListener(_finalRemarksController, _onEdited);
    attachEditListener(_otherStaffController, _onEdited);
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
    final payload = _draftPayload();
    await _api.saveRectificationDraft(widget.workOrderId, payload);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosave.dispose();
    _finalRemarksController.dispose();
    _otherStaffController.dispose();
    for (final d in _drafts.values) {
      d.dispose();
    }
    super.dispose();
  }

  void _syncDrafts(RectificationPayload payload) {
    for (final id in _drafts.keys.toList()) {
      if (payload.items.every((i) => i.id != id)) {
        _drafts.remove(id)?.dispose();
      }
    }
    for (final item in payload.items) {
      final existing = _drafts[item.id];
      if (existing == null) {
        final draft = _ItemDraft(
          action: TextEditingController(text: item.actionTaken),
          outcome: item.outcome,
          reason: TextEditingController(text: item.reason),
        );
        attachEditListener(draft.action, _onEdited);
        attachEditListener(draft.reason, _onEdited);
        _drafts[item.id] = draft;
      } else {
        existing.action.text = item.actionTaken;
        existing.outcome = item.outcome;
        existing.reason.text = item.reason;
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await ref
          .read(executionApiServiceProvider)
          .getRectification(widget.workOrderId);
      if (!mounted) return;
      _hydrating = true;
      try {
        setState(() {
          _payload = payload;
          _finalRemarksController.text = payload.finalRemarks;
          _otherStaffController.text = payload.otherStaff;
          _syncDrafts(payload);
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

  Map<String, dynamic> _draftPayload() => {
        'final_remarks': _finalRemarksController.text.trim(),
        'other_staff': _otherStaffController.text.trim(),
        'items': [
          for (final entry in _drafts.entries)
            {
              'id': entry.key,
              'action_taken': entry.value.action.text.trim(),
              'outcome': entry.value.outcome,
              'reason': entry.value.reason.text.trim(),
            },
        ],
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

  Future<void> _addPhoto(RectificationItem item, String kind) async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only JPEG photos are allowed.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final filename = picked.path.split(Platform.pathSeparator).last;
      await ref.read(executionApiServiceProvider).uploadRectificationPhoto(
            widget.workOrderId,
            item.id,
            kind: kind,
            file: await MultipartFile.fromFile(
              picked.path,
              filename: filename.isNotEmpty ? filename : 'evidence.jpg',
              contentType: DioMediaType('image', 'jpeg'),
            ),
          );
      await _autosave.flush();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload: ${userFacingError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deletePhoto(RectificationItem item, ExecutionPhoto photo) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Delete photo?',
      icon: Icons.delete_outline,
      message: 'This item photo will be permanently deleted.',
      confirmLabel: 'Delete',
      confirmKey: Key('confirm_delete_rect_photo_${photo.id}'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(executionApiServiceProvider).deleteRectificationPhoto(
            widget.workOrderId,
            item.id,
            photo.id,
          );
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

  /// Advisory pre-check mirroring the server's completion rules so the
  /// technician sees what's missing before the authoritative submit.
  String? _blockedReason() {
    final payload = _payload;
    if (payload == null || payload.items.isEmpty) {
      return 'This Job Work has no rectification items.';
    }
    for (var i = 0; i < payload.items.length; i++) {
      final item = payload.items[i];
      final draft = _drafts[item.id];
      final action = draft?.action.text.trim() ?? '';
      final outcome = draft?.outcome ?? '';
      final reason = draft?.reason.text.trim() ?? '';
      final label = 'Item ${i + 1}';
      if (action.isEmpty) return '$label: action taken is required.';
      if (outcome.isEmpty) return '$label: choose Rectified or Not rectified.';
      if (!item.photos.any((p) => p.isBefore)) {
        return '$label: a Before photo is required.';
      }
      if (outcome == 'RECTIFIED' && !item.photos.any((p) => p.isAfter)) {
        return '$label: an After photo is required for a rectified item.';
      }
      if (outcome == 'NOT_RECTIFIED' && reason.isEmpty) {
        return '$label: give the reason it could not be rectified.';
      }
    }
    if (_finalRemarksController.text.trim().isEmpty) {
      return 'Final outcome is required before completion.';
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
      title: 'Submit rectification?',
      icon: Icons.verified_outlined,
      message:
          'This moves the Job Work to Technically Completed for supervisor verification.',
      confirmLabel: 'Submit',
      confirmKey: const Key('confirm_submit_rectification'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _submitting = true);
    try {
      if (!await _autosave.flush(manual: true)) {
        throw StateError(_autosave.lastError ?? 'Progress could not be saved.');
      }
      final session = sessionFromAuth(ref.read(authControllerProvider));
      await ref.read(executionApiServiceProvider).submitRectification(
        widget.workOrderId,
        {
          'remarks': _finalRemarksController.text.trim(),
          if (session?.username.isNotEmpty == true)
            'technician_name': session!.username,
          'technician_signature': 'SIGNED_DIGITALLY',
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rectification submitted.')),
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

  String _outcomeLabel(String code) {
    switch (code) {
      case 'RECTIFIED':
        return 'Rectified';
      case 'NOT_RECTIFIED':
        return 'Not rectified';
      default:
        return 'Select outcome';
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = sessionFromAuth(ref.watch(authControllerProvider));
    if (!sessionAllows(session, 'maintenance.edit')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rectification Execution')),
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
              ? 'Rectification ${widget.ticketNumber}'
              : 'Rectification Execution')),
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
                        for (final item in _payload?.items ?? [])
                          _itemCard(item),
                        const SizedBox(height: 12),
                        SectionCard(
                          title: 'Final Outcome',
                          icon: Icons.flag_outlined,
                          children: [
                            TextFormField(
                              key: const Key('rect_final_remarks_field'),
                              controller: _finalRemarksController,
                              enabled: !_busy,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Final outcome remarks *',
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty
                                      ? 'Final outcome is required'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _otherStaffController,
                              enabled: !_busy,
                              decoration: const InputDecoration(
                                labelText: 'Other staff (optional)',
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
                                key: const Key('save_rect_draft_button'),
                                onPressed: _busy ? null : _saveDraft,
                                icon: const Icon(Icons.save_outlined),
                                label: Text(
                                    _saving ? 'Saving…' : 'Save Progress'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                key: const Key('submit_rect_button'),
                                onPressed: _busy ? null : _submit,
                                icon:
                                    const Icon(Icons.verified_outlined),
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

  Widget _itemCard(RectificationItem item) {
    final draft = _drafts[item.id];
    return Container(
      key: Key('rect_item_card_${item.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: context.gssms.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.checkpoint.isNotEmpty ? item.checkpoint : 'Item',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(item.finding,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (item.severity != null && item.severity!.isNotEmpty)
                StatusChip(
                  label: item.severity!,
                  tone: GssmsTone.warning,
                  icon: Icons.priority_high,
                ),
              StatusChip(
                label: item.asset.isNotEmpty ? item.asset : 'General',
                tone: GssmsTone.neutral,
                icon: Icons.build_circle_outlined,
              ),
              if (item.sourceTicket != null)
                StatusChip(
                  label: item.sourceTicket!,
                  tone: GssmsTone.info,
                  icon: Icons.link,
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: Key('rect_item_action_${item.id}'),
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
          DropdownButtonFormField<String>(
            key: Key('rect_item_outcome_${item.id}'),
            value: (draft?.outcome.isNotEmpty == true)
                ? draft!.outcome
                : null,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Outcome *', isDense: true),
            items: [
              for (final o in _outcomes.where((o) => o.isNotEmpty))
                DropdownMenuItem(
                    value: o, child: Text(_outcomeLabel(o))),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => draft?.outcome = v);
                    _autosave.markEdited();
                  },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: Key('rect_item_reason_${item.id}'),
            controller: draft?.reason,
            enabled: !_busy,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason (required if not rectified)',
            ),
          ),
          const SizedBox(height: 12),
          ExecutionPhotoGrid(
            photos: item.photos,
            canManage: true,
            busy: _busy,
            maxPerKind: 10,
            onAdd: (kind) => _addPhoto(item, kind),
            onDelete: (photo) => _deletePhoto(item, photo),
          ),
        ],
      ),
    );
  }
}
