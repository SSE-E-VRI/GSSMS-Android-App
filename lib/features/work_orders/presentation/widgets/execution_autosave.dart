import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';

enum AutosaveStatus { idle, saving, saved, error }

/// Debounced autosave for the technician execution forms.
///
/// Mirrors the web rules: 2 s debounce after a real edit, one save in flight,
/// an edit made during a save triggers exactly one more save afterwards, and
/// a pending save is flushed when the form closes. The [save] callback must
/// build its payload synchronously (before its first `await`) so the
/// unmount flush in [dispose] can run after the screen state is gone.
class ExecutionAutosaveController extends ChangeNotifier {
  ExecutionAutosaveController({
    required Future<void> Function() save,
    Duration delay = const Duration(milliseconds: 2000),
  })  : _save = save,
        _delay = delay;

  final Future<void> Function() _save;
  final Duration _delay;

  int _editSeq = 0;
  bool _dirty = false;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _submitted = false;
  bool _disposed = false;

  AutosaveStatus status = AutosaveStatus.idle;
  DateTime? lastSavedAt;
  String? lastError;

  bool get isDirty => _dirty;
  bool get isSaving => _inFlight != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Call after a real user edit (never while hydrating from the server).
  void markEdited() {
    if (_submitted || _disposed) return;
    _editSeq++;
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(_delay, () => unawaited(_run(manual: false)));
    _notify();
  }

  /// Saves any pending edit now. A [manual] flush always saves.
  /// Returns false only when a save was attempted and failed.
  Future<bool> flush({bool manual = false}) async {
    _timer?.cancel();
    var forceSave = manual;
    while (true) {
      while (_inFlight != null) {
        await _inFlight;
      }
      if (_submitted || _disposed) return true;
      if (!forceSave && !_dirty) return true;
      if (!await _run(manual: forceSave)) return false;
      forceSave = false;
      // A user can keep editing during the request. Do not let navigation or
      // submission proceed until those newer edits have also been persisted.
    }
  }

  Future<bool> _run({required bool manual}) async {
    if (_submitted || _disposed) return true;
    if (_inFlight != null) return true; // the in-flight save re-runs if needed
    if (!manual && !_dirty) return true;
    final seq = _editSeq;
    final done = Completer<void>();
    _inFlight = done.future;
    status = AutosaveStatus.saving;
    _notify();
    try {
      await _save();
      lastSavedAt = DateTime.now();
      lastError = null;
      if (_editSeq == seq) {
        _dirty = false;
      } else if (!_disposed && !_submitted) {
        Timer.run(() => unawaited(_run(manual: false)));
      }
      status = AutosaveStatus.saved;
      return true;
    } catch (e) {
      status = AutosaveStatus.error;
      lastError = userFacingError(e);
      return false;
    } finally {
      _inFlight = null;
      done.complete();
      _notify();
    }
  }

  void markSubmitted() {
    _submitted = true;
    _timer?.cancel();
    _notify();
  }

  /// After a manual reload replaced the form with server state.
  void markClean() {
    _timer?.cancel();
    _dirty = false;
    _notify();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_dirty && !_submitted) {
      unawaited(_save().catchError((Object _) {}));
    }
    _disposed = true;
    super.dispose();
  }
}

/// Wires a text controller to [onEdit], firing only when the text changes
/// (not on selection or focus changes).
void attachEditListener(TextEditingController c, VoidCallback onEdit) {
  var last = c.text;
  c.addListener(() {
    if (c.text == last) return;
    last = c.text;
    onEdit();
  });
}

/// Saving… / All changes saved · HH:mm / Not saved — error (Retry).
class AutosaveStatusLine extends StatelessWidget {
  const AutosaveStatusLine({super.key, required this.controller});

  final ExecutionAutosaveController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tokens = context.gssms;
        final style = Theme.of(context).textTheme.bodySmall;
        switch (controller.status) {
          case AutosaveStatus.idle:
            return const SizedBox.shrink(key: Key('exec_autosave_status'));
          case AutosaveStatus.saving:
            return Padding(
              key: const Key('exec_autosave_status'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Saving…',
                      style: style?.copyWith(color: tokens.textSecondary)),
                ],
              ),
            );
          case AutosaveStatus.saved:
            final at = controller.lastSavedAt;
            return Padding(
              key: const Key('exec_autosave_status'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: tokens.success.foreground),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      at == null
                          ? 'All changes saved'
                          : 'All changes saved · ${DateFormat('hh:mm a').format(at.toLocal())}',
                      style:
                          style?.copyWith(color: tokens.success.foreground),
                    ),
                  ),
                ],
              ),
            );
          case AutosaveStatus.error:
            return Padding(
              key: const Key('exec_autosave_status'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Not saved — ${controller.lastError ?? 'unknown error'}',
                      style: style?.copyWith(color: tokens.danger.foreground),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        unawaited(controller.flush(manual: true)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
        }
      },
    );
  }
}

/// Asked when leaving with edits that could not be saved.
Future<bool> confirmDiscardUnsaved(BuildContext context) {
  return showConfirmationDialog(
    context,
    title: 'Unsaved changes',
    message: 'Your latest changes could not be saved.',
    confirmLabel: 'Leave anyway',
    cancelLabel: 'Stay',
    icon: Icons.warning_amber_outlined,
    destructive: true,
  );
}
