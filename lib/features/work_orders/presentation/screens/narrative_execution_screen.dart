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

/// How long after the last edit a draft is saved on its own.
const Duration kNarrativeAutosaveDelay = Duration(seconds: 2);

/// The narrative execution form (SSOT RULE 5.1): findings, action taken,
/// optional parameters, Before/After photos and final remarks, then
/// Sign & Submit. Used for breakdowns, deficiency rectifications, manual
/// Corrective work, escalated inspection points and legacy inspections.
///
/// Online only. Saves follow the same rules as the web form: autosave after a
/// pause in typing, one save in flight at a time, an edit made during a save
/// triggers one more save, and nothing is written unless the Job Work is
/// IN_PROGRESS.
class NarrativeExecutionScreen extends ConsumerStatefulWidget {
  const NarrativeExecutionScreen({
    super.key,
    required this.recordId,
    required this.context,
  });

  final int recordId;
  final NarrativeContext context;

  @override
  ConsumerState<NarrativeExecutionScreen> createState() => _NarrativeExecutionScreenState();
}

class _NarrativeExecutionScreenState extends ConsumerState<NarrativeExecutionScreen> {
  final _findings = TextEditingController();
  final _action = TextEditingController();
  final _remarks = TextEditingController();
  List<_ParameterRowControllers> _parameterRows = [];
  List<NarrativePhoto> _photos = const [];

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
  NarrativeExecutionApiService get _api => ref.read(narrativeExecutionApiServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    final pending = _autosaveTimer?.isActive ?? false;
    _autosaveTimer?.cancel();
    // Leaving the screen with a save still waiting on its timer: send it now.
    if (pending && _dirty && _editable && !_submitting) {
      unawaited(_api.saveDraft(_workOrderId, _draftFields()).then((_) {}, onError: (_) {}));
    }
    _findings.dispose();
    _action.dispose();
    _remarks.dispose();
    for (final row in _parameterRows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final execution = await _api.getExecution(_workOrderId);
      if (!mounted) return;
      _findings.text = execution.initialFindings;
      _action.text = execution.actionTaken;
      _remarks.text = execution.finalRemarks;
      for (final row in _parameterRows) {
        row.dispose();
      }
      _parameterRows = execution.parameters.map(_ParameterRowControllers.from).toList();
      setState(() {
        _photos = execution.photos;
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

  /// Only parameter rows the backend would accept; incomplete rows stay on
  /// screen but are not sent (a half-typed row would fail the whole save).
  List<NarrativeParameter> get _completeParameters =>
      _parameterRows.map((r) => r.value).where((p) => p.isComplete).toList();

  bool get _hasIncompleteRows => _parameterRows.any((r) => !r.value.isComplete);

  Map<String, dynamic> _draftFields() => {
        'initial_findings': _findings.text,
        'action_taken': _action.text,
        'final_remarks': _remarks.text,
        'parameters': _completeParameters.map((p) => p.toJson()).toList(),
      };

  void _markEdited() {
    if (!_editable) return;
    _editSeq += 1;
    _dirty = true;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(kNarrativeAutosaveDelay, () => unawaited(_save()));
    if (mounted) setState(() {});
  }

  /// One save at a time; waits for any save already running first.
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
      await _api.saveDraft(_workOrderId, _draftFields());
      if (!mounted) return;
      // Never write the response back into the fields: the user may have
      // typed more while the request was in flight.
      final changedMeanwhile = _editSeq != seqAtStart;
      setState(() {
        _savingNow = false;
        _savedAt = DateTime.now();
        _dirty = changedMeanwhile || _hasIncompleteRows;
      });
      if (manual) {
        showGssmsSnackBar(context, 'Progress saved.', tone: GssmsTone.success);
      }
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

  Future<void> _addPhoto(NarrativePhotoKind kind) async {
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
      final photo = await _api.uploadPhoto(_workOrderId, kind, captured.path);
      if (!mounted) return;
      setState(() {
        _photos = [..._photos.where((p) => p.id != photo.id), photo];
      });
    } catch (e) {
      if (mounted) showGssmsSnackBar(context, userFacingError(e), tone: GssmsTone.danger);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto(NarrativePhoto photo) async {
    if (!_editable || photo.locked) return;
    try {
      await _api.deletePhoto(_workOrderId, photo.id);
      if (!mounted) return;
      setState(() => _photos = _photos.where((p) => p.id != photo.id).toList());
    } catch (e) {
      if (mounted) showGssmsSnackBar(context, userFacingError(e), tone: GssmsTone.danger);
    }
  }

  // ---------------------------------------------------------------- submit

  /// What still blocks Sign & Submit, in the order the form shows it.
  List<String> _blockers() {
    final blockers = <String>[];
    if (_findings.text.trim().isEmpty) blockers.add('Write the initial assessment and findings.');
    if (_action.text.trim().isEmpty) blockers.add('Write the action taken.');
    if (!_photos.any((p) => p.kind == NarrativePhotoKind.before.code)) {
      blockers.add('Add at least one Before photo.');
    }
    if (!_photos.any((p) => p.kind == NarrativePhotoKind.after.code)) {
      blockers.add('Add at least one After photo.');
    }
    if (_remarks.text.trim().isEmpty) blockers.add('Write the final outcome.');
    return blockers;
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
      // Wait for any save already running, then store the final text: the
      // submit endpoint checks the stored record, not what is on screen.
      await (_inFlight ?? Future<void>.value()).catchError((_) {});
      await _api.saveDraft(_workOrderId, _draftFields());
      final session = sessionFromAuth(ref.read(authControllerProvider));
      await _api.submit(
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
    // A waiting autosave timer means edits are not stored yet. (`_dirty` also
    // stays true while an incomplete parameter row is held back, which is
    // reported below as part of the "Saved" line instead.)
    if (_autosaveTimer?.isActive ?? false) return 'Unsaved changes';
    final at = _savedAt;
    if (at == null) return _dirty ? 'Unsaved changes' : '';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return _hasIncompleteRows ? 'Saved $hh:$mm (incomplete rows not saved)' : 'Saved $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final title = _ctx.deficiency != null ? 'Deficiency Rectification' : 'Job Work Execution';
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
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
        _buildSourceCard(context),
        const SizedBox(height: 16),
        _section(context, '1. Initial assessment & findings', _textField(_findings, 'What was observed / diagnosed', key: 'findings')),
        _section(context, '2. Rectification / action taken', _textField(_action, 'What was actually done', key: 'action')),
        _section(context, '3. Technical parameters (optional)', _buildParameters(context)),
        _section(context, '4. Photo evidence', _buildPhotos(context)),
        _section(context, '5. Final outcome', _textField(_remarks, 'Outcome of the work', key: 'remarks', lines: 3)),
      ],
    );
  }

  Widget _buildSourceCard(BuildContext context) {
    final d = _ctx.deficiency;
    final rows = <MapEntry<String, String>>[
      MapEntry('Job Work', _ctx.ticketNumber),
      if (d != null) ...[
        MapEntry('Found in', d.sourceTicket ?? '—'),
        MapEntry('Severity', d.severity ?? '—'),
        MapEntry('Asset / equipment', d.equipment ?? '—'),
        MapEntry('Checkpoint', d.checkpoint ?? '—'),
        MapEntry('Finding', d.finding),
        MapEntry('Location', d.stationName ?? _ctx.stationName ?? '—'),
      ] else ...[
        MapEntry('Location', _ctx.stationName ?? '—'),
        MapEntry('Work', _ctx.title.isNotEmpty ? _ctx.title : '—'),
        if (_ctx.description.isNotEmpty) MapEntry('Details', _ctx.description),
      ],
    ];
    return Card(
      key: Key(d != null ? 'deficiency-details' : 'job-work-details'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d != null ? 'Deficiency details' : 'Job Work details',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 108,
                      child: Text(row.key, style: TextStyle(color: context.gssms.textSecondary)),
                    ),
                    Expanded(child: Text(row.value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String heading, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _textField(TextEditingController controller, String hint, {required String key, int lines = 4}) {
    return TextField(
      key: Key('narrative-$key'),
      controller: controller,
      enabled: _editable && !_submitting,
      minLines: lines,
      maxLines: lines + 4,
      decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      onChanged: (_) => _markEdited(),
    );
  }

  Widget _buildParameters(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _parameterRows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: TextField(
                    key: Key('param-name-$i'),
                    controller: _parameterRows[i].parameter,
                    enabled: _editable && !_submitting,
                    decoration: const InputDecoration(labelText: 'Parameter', border: OutlineInputBorder()),
                    onChanged: (_) => _markEdited(),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: Key('param-value-$i'),
                    controller: _parameterRows[i].valueText,
                    enabled: _editable && !_submitting,
                    decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder()),
                    onChanged: (_) => _markEdited(),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: Key('param-unit-$i'),
                    controller: _parameterRows[i].unit,
                    enabled: _editable && !_submitting,
                    decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                    onChanged: (_) => _markEdited(),
                  ),
                ),
                if (_editable)
                  IconButton(
                    key: Key('param-remove-$i'),
                    tooltip: 'Remove row',
                    icon: const Icon(Icons.close),
                    onPressed: _submitting
                        ? null
                        : () {
                            setState(() {
                              _parameterRows.removeAt(i).dispose();
                            });
                            _markEdited();
                          },
                  ),
              ],
            ),
          ),
        if (_editable)
          TextButton.icon(
            key: const Key('param-add'),
            onPressed: _submitting
                ? null
                : () {
                    setState(() => _parameterRows.add(_ParameterRowControllers.from(const NarrativeParameter())));
                    _markEdited();
                  },
            icon: const Icon(Icons.add),
            label: const Text('Add parameter'),
          ),
      ],
    );
  }

  Widget _buildPhotos(BuildContext context) {
    Widget group(NarrativePhotoKind kind, String label) {
      final photos = _photos.where((p) => p.kind == kind.code).toList();
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
                          key: Key('photo-remove-${p.id}'),
                          onTap: () => _removePhoto(p),
                          child: const CircleAvatar(radius: 12, child: Icon(Icons.close, size: 14)),
                        ),
                      ),
                  ],
                ),
              if (_editable)
                OutlinedButton(
                  key: Key('photo-add-${kind.code.toLowerCase()}'),
                  onPressed: (_uploading || _submitting) ? null : () => _addPhoto(kind),
                  child: Text(_uploading ? 'Uploading…' : 'Add photo'),
                ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group(NarrativePhotoKind.before, 'Before / initial condition *'),
        const SizedBox(height: 12),
        group(NarrativePhotoKind.after, 'After / rectification result *'),
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
                key: const Key('narrative-save-status'),
                style: TextStyle(color: statusColor, fontSize: 12),
              ),
            ),
            OutlinedButton(
              key: const Key('narrative-save'),
              onPressed: _submitting ? null : () => unawaited(_save(manual: true)),
              child: const Text('Save progress'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('narrative-submit'),
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting…' : 'Sign & submit'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text controllers for one parameter row.
class _ParameterRowControllers {
  _ParameterRowControllers(NarrativeParameter p)
      : parameter = TextEditingController(text: p.parameter),
        valueText = TextEditingController(text: p.value),
        unit = TextEditingController(text: p.unit);

  factory _ParameterRowControllers.from(NarrativeParameter p) => _ParameterRowControllers(p);

  final TextEditingController parameter;
  final TextEditingController valueText;
  final TextEditingController unit;

  NarrativeParameter get value =>
      NarrativeParameter(parameter: parameter.text, value: valueText.text, unit: unit.text);

  void dispose() {
    parameter.dispose();
    valueText.dispose();
    unit.dispose();
  }
}
