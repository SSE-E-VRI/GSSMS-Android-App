import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/feedback.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/narrative_execution_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/narrative_execution.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/narrative_execution_screen.dart'
    show kNarrativeAutosaveDelay;

/// Grouped deficiency rectification (SSOT section 6): one card per deficiency
/// with action taken, outcome, reason (when not rectified) and Before/After
/// photos, then one final outcome for the whole Job Work.
///
/// Online only. Autosave follows RULE 5.3: a pause in typing saves, one save
/// at a time, an edit during a save triggers one more, the server response
/// never overwrites typed text, and only IN_PROGRESS is editable.
class RectificationExecutionScreen extends ConsumerStatefulWidget {
  const RectificationExecutionScreen({super.key, required this.recordId, required this.context});

  final int recordId;
  final NarrativeContext context;

  @override
  ConsumerState<RectificationExecutionScreen> createState() => _RectificationExecutionScreenState();
}

class _ItemControllers {
  _ItemControllers(RectificationItem item)
      : action = TextEditingController(text: item.actionTaken),
        reason = TextEditingController(text: item.reason),
        outcome = item.outcome,
        photos = item.photos;

  final TextEditingController action;
  final TextEditingController reason;
  String outcome;
  List<NarrativePhoto> photos;

  void dispose() {
    action.dispose();
    reason.dispose();
  }
}

class _RectificationExecutionScreenState extends ConsumerState<RectificationExecutionScreen> {
  final _remarks = TextEditingController();
  List<RectificationItem> _items = const [];
  final Map<int, _ItemControllers> _state = {};

  bool _loading = true;
  String? _loadError;
  bool _submitting = false;
  bool _uploading = false;

  Timer? _autosaveTimer;
  Future<void>? _inFlight;
  int _editSeq = 0;
  bool _dirty = false;
  DateTime? _savedAt;
  String? _saveError;
  bool _savingNow = false;

  NarrativeContext get _ctx => widget.context;
  int get _workOrderId => _ctx.workOrderId;
  bool get _editable => _ctx.isEditable;
  // Captured once: `ref` cannot be read from dispose(), which flushes a pending save.
  late final NarrativeExecutionApiService _api = ref.read(narrativeExecutionApiServiceProvider);

  @override
  void initState() {
    super.initState();
    _api;
    _load();
  }

  @override
  void dispose() {
    final pending = _autosaveTimer?.isActive ?? false;
    _autosaveTimer?.cancel();
    if (pending && _dirty && _editable && !_submitting) {
      unawaited(_api
          .saveRectification(_workOrderId, finalRemarks: _remarks.text, items: _draftItems())
          .then((_) {}, onError: (_) {}));
    }
    _remarks.dispose();
    for (final s in _state.values) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final execution = await _api.getRectification(_workOrderId);
      if (!mounted) return;
      for (final s in _state.values) {
        s.dispose();
      }
      _state
        ..clear()
        ..addEntries(execution.items.map((i) => MapEntry(i.id, _ItemControllers(i))));
      _remarks.text = execution.finalRemarks;
      setState(() {
        _items = execution.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = userFacingError(e);
      });
    }
  }

  // ---------------------------------------------------------------- saving

  List<Map<String, dynamic>> _draftItems() => [
        for (final item in _items)
          {
            'id': item.id,
            'action_taken': _state[item.id]!.action.text,
            'outcome': _state[item.id]!.outcome,
            'reason': _state[item.id]!.reason.text,
          },
      ];

  void _markEdited() {
    if (!_editable) return;
    _editSeq += 1;
    _dirty = true;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(kNarrativeAutosaveDelay, () => unawaited(_save()));
    if (mounted) setState(() {});
  }

  Future<void> _save({bool manual = false}) {
    final previous = _inFlight ?? Future<void>.value();
    final run = previous.catchError((_) {}).then((_) => _doSave(manual: manual));
    _inFlight = run;
    return run;
  }

  Future<void> _doSave({required bool manual}) async {
    if (!mounted || !_editable || _submitting) return;
    final seqAtStart = _editSeq;
    setState(() {
      _savingNow = true;
      _saveError = null;
    });
    try {
      await _api.saveRectification(_workOrderId, finalRemarks: _remarks.text, items: _draftItems());
      if (!mounted) return;
      final changedMeanwhile = _editSeq != seqAtStart;
      setState(() {
        _savingNow = false;
        _savedAt = DateTime.now();
        _dirty = changedMeanwhile;
      });
      if (manual) showGssmsSnackBar(context, 'Progress saved.', tone: GssmsTone.success);
      if (changedMeanwhile) {
        _autosaveTimer?.cancel();
        _autosaveTimer = Timer(Duration.zero, () => unawaited(_save()));
      }
    } catch (e) {
      if (!mounted) return;
      final message = userFacingError(e);
      setState(() {
        _savingNow = false;
        _saveError = message;
      });
      if (manual) showGssmsSnackBar(context, message, tone: GssmsTone.danger);
    }
  }

  // ---------------------------------------------------------------- photos

  Future<void> _addPhoto(RectificationItem item, NarrativePhotoKind kind) async {
    if (_uploading || !_editable) return;
    final evidenceKind = kind == NarrativePhotoKind.before ? EvidenceKind.before : EvidenceKind.after;
    try {
      final captured = await ref.read(evidenceServiceProvider).capture(kind: evidenceKind);
      if (captured == null) return;
      if (!captured.isWithinSizeLimit) {
        if (mounted) {
          showGssmsSnackBar(context, 'Photo is larger than 5 MB. Retake it closer or at lower quality.',
              tone: GssmsTone.danger);
        }
        return;
      }
      setState(() => _uploading = true);
      final photo = await _api.uploadRectificationPhoto(_workOrderId, item.id, kind, captured.path);
      if (!mounted) return;
      final s = _state[item.id]!;
      setState(() => s.photos = [...s.photos.where((p) => p.id != photo.id), photo]);
    } catch (e) {
      if (mounted) showGssmsSnackBar(context, userFacingError(e), tone: GssmsTone.danger);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto(RectificationItem item, NarrativePhoto photo) async {
    if (!_editable || photo.locked) return;
    try {
      await _api.deleteRectificationPhoto(_workOrderId, item.id, photo.id);
      if (!mounted) return;
      final s = _state[item.id]!;
      setState(() => s.photos = s.photos.where((p) => p.id != photo.id).toList());
    } catch (e) {
      if (mounted) showGssmsSnackBar(context, userFacingError(e), tone: GssmsTone.danger);
    }
  }

  // ---------------------------------------------------------------- submit

  /// The item as currently on screen (text, outcome, photos).
  RectificationItem _current(RectificationItem item) {
    final s = _state[item.id]!;
    return RectificationItem(
      id: item.id,
      asset: item.asset,
      checkpoint: item.checkpoint,
      finding: item.finding,
      severity: item.severity,
      sourceTicket: item.sourceTicket,
      actionTaken: s.action.text,
      outcome: s.outcome,
      reason: s.reason.text,
      photos: s.photos,
    );
  }

  List<String> _blockers() {
    final out = <String>[];
    for (final item in _items) {
      out.addAll(_current(item).blockers());
    }
    if (_remarks.text.trim().isEmpty) out.add('Write the final outcome.');
    return out;
  }

  Future<void> _submit() async {
    if (_submitting || !_editable) return;
    final blockers = _blockers();
    if (blockers.isNotEmpty) {
      showGssmsSnackBar(context, blockers.first, tone: GssmsTone.warning);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit for verification?'),
        content: const Text('This moves the Job Work to Technically Completed. You cannot edit it afterwards.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _autosaveTimer?.cancel();
    setState(() => _submitting = true);
    try {
      await (_inFlight ?? Future<void>.value()).catchError((_) {});
      await _api.saveRectification(_workOrderId, finalRemarks: _remarks.text, items: _draftItems());
      final session = sessionFromAuth(ref.read(authControllerProvider));
      await _api.submitRectification(
        _workOrderId,
        remarks: _remarks.text.trim(),
        technicianName: session?.displayName ?? '',
      );
      if (!mounted) return;
      _dirty = false;
      showGssmsSnackBar(context, 'Submitted for verification.', tone: GssmsTone.success);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showGssmsSnackBar(context, userFacingError(e), tone: GssmsTone.danger);
    }
  }

  // ---------------------------------------------------------------- build

  String get _saveStatusText {
    if (_saveError != null) return 'Save failed: $_saveError';
    if (_savingNow) return 'Saving…';
    if (_autosaveTimer?.isActive ?? false) return 'Unsaved changes';
    final at = _savedAt;
    if (at == null) return _dirty ? 'Unsaved changes' : '';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return 'Saved $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Deficiency Rectification'),
              Text(
                _ctx.ticketNumber.isNotEmpty ? _ctx.ticketNumber : '#${widget.recordId}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
        body: _buildBody(context),
        bottomNavigationBar: (_loading || _loadError != null || !_editable) ? null : _buildActionBar(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final enabled = _editable && !_submitting;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (!_editable)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'This Job Work is ${_ctx.status.toLowerCase().replaceAll('_', ' ')}. It can be read but not edited.',
              style: TextStyle(color: context.gssms.textSecondary),
            ),
          ),
        Text(
          '${_items.length} deficienc${_items.length == 1 ? 'y' : 'ies'} at ${_ctx.stationName ?? 'this location'}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        for (final item in _items) _buildItemCard(context, item, enabled),
        Text('Final outcome', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          key: const Key('rect-remarks'),
          controller: _remarks,
          enabled: enabled,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Overall outcome of the work',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markEdited(),
        ),
      ],
    );
  }

  Widget _buildItemCard(BuildContext context, RectificationItem item, bool enabled) {
    final s = _state[item.id]!;
    return Card(
      key: Key('rect-item-${item.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.asset} — ${item.checkpoint}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(item.finding),
            if (item.severity != null || item.sourceTicket != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [
                    if (item.severity != null) 'Severity: ${item.severity}',
                    if (item.sourceTicket != null) 'Found in ${item.sourceTicket}',
                  ].join(' · '),
                  style: TextStyle(color: context.gssms.textSecondary, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              key: Key('rect-action-${item.id}'),
              controller: s.action,
              enabled: enabled,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Action taken', border: OutlineInputBorder()),
              onChanged: (_) => _markEdited(),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              key: Key('rect-outcome-${item.id}'),
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'RECTIFIED', label: Text('Rectified')),
                ButtonSegment(value: 'NOT_RECTIFIED', label: Text('Not rectified')),
              ],
              selected: s.outcome.isEmpty ? <String>{} : {s.outcome},
              onSelectionChanged: enabled
                  ? (selection) {
                      setState(() => s.outcome = selection.isEmpty ? '' : selection.first);
                      _markEdited();
                    }
                  : null,
            ),
            if (s.outcome == 'NOT_RECTIFIED') ...[
              const SizedBox(height: 10),
              TextField(
                key: Key('rect-reason-${item.id}'),
                controller: s.reason,
                enabled: enabled,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Reason it could not be rectified',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _markEdited(),
              ),
            ],
            const SizedBox(height: 12),
            _photoGroup(context, item, s, NarrativePhotoKind.before, 'Before *'),
            const SizedBox(height: 10),
            _photoGroup(
              context,
              item,
              s,
              NarrativePhotoKind.after,
              s.outcome == 'RECTIFIED' ? 'After *' : 'After',
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoGroup(
    BuildContext context,
    RectificationItem item,
    _ItemControllers s,
    NarrativePhotoKind kind,
    String label,
  ) {
    final photos = s.photos.where((p) => p.kind == kind.code).toList();
    final token = sessionFromAuth(ref.read(authControllerProvider))?.accessToken;
    final headers = (token == null || token.isEmpty) ? null : {'Authorization': 'Bearer $token'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.gssms.textSecondary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in photos)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 84,
                      height: 84,
                      child: p.url.isEmpty
                          ? const Icon(Icons.image_not_supported)
                          : Image.network(
                              p.url,
                              headers: headers,
                              fit: BoxFit.cover,
                              cacheWidth: 200,
                              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                            ),
                    ),
                  ),
                  if (_editable && !p.locked)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: InkWell(
                        key: Key('rect-photo-remove-${p.id}'),
                        onTap: () => _removePhoto(item, p),
                        child: const CircleAvatar(radius: 12, child: Icon(Icons.close, size: 14)),
                      ),
                    ),
                ],
              ),
            if (_editable)
              OutlinedButton(
                key: Key('rect-photo-add-${item.id}-${kind.code.toLowerCase()}'),
                onPressed: (_uploading || _submitting) ? null : () => _addPhoto(item, kind),
                child: Text(_uploading ? 'Uploading…' : 'Add photo'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final statusColor = _saveError != null ? context.gssms.danger.solid : context.gssms.textSecondary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _saveStatusText,
                key: const Key('rect-save-status'),
                style: TextStyle(color: statusColor, fontSize: 12),
              ),
            ),
            OutlinedButton(
              key: const Key('rect-save'),
              onPressed: _submitting ? null : () => unawaited(_save(manual: true)),
              child: const Text('Save progress'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('rect-submit'),
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting…' : 'Sign & submit'),
            ),
          ],
        ),
      ),
    );
  }
}
