import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/deficiency_severity_option.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/verification_workspace_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

// H7: autoDispose — per-WO workspaces (full checklists, severities) must not
// accumulate for the whole session; the screen re-fetches on open.
final verificationWorkspaceControllerProvider = NotifierProvider.autoDispose.family<
    VerificationWorkspaceController, VerificationWorkspaceState, int>(() {
  return VerificationWorkspaceController();
});

const verificationSeverityConflictMessage =
    'This deficiency was updated by someone else. The latest state has been reloaded.';

class VerificationWorkspaceController
    extends AutoDisposeFamilyNotifier<VerificationWorkspaceState, int> {
  @override
  VerificationWorkspaceState build(int arg) {
    return const VerificationWorkspaceLoading();
  }

  IWorkOrderRepository get _repository => ref.read(workOrderRepositoryProvider);

  List<DeficiencySeverityOption> get _severities {
    final s = state;
    return s is VerificationWorkspaceLoaded ? s.severities : const [];
  }

  int? get _recordId {
    final s = state;
    return s is VerificationWorkspaceLoaded ? s.workspace.recordId : null;
  }

  Future<void> load() async {
    state = const VerificationWorkspaceLoading();
    try {
      final workspace = await _repository.fetchVerificationWorkspace(arg);
      state = VerificationWorkspaceLoaded(workspace: workspace);
    } catch (e) {
      state = VerificationWorkspaceError(
        'Failed to load verification workspace: ${workOrderReadableError(e)}',
      );
      return;
    }
    // Severities are best-effort: a failure leaves an empty list.
    try {
      final severities = await _repository.getDeficiencySeverities();
      final s = state;
      if (s is VerificationWorkspaceLoaded) {
        state = s.copyWith(severities: severities);
      }
    } catch (_) {}
  }

  /// Reloads the workspace in place (keeps severities) without showing the
  /// full-screen loading state.
  Future<void> _reload() async {
    try {
      final workspace = await _repository.fetchVerificationWorkspace(arg);
      state = VerificationWorkspaceLoaded(
        workspace: workspace,
        severities: _severities,
      );
    } catch (_) {
      // Keep the previous snapshot; the caller already has a message.
    }
  }

  void _setMutating(bool value) {
    final s = state;
    if (s is VerificationWorkspaceLoaded) {
      state = s.copyWith(isMutating: value);
    }
  }

  /// Runs a mutation, then reloads. Returns null on success, else an error
  /// message. [conflictMessage] replaces the text for a 409 and reloads.
  Future<String?> _mutate(
    Future<void> Function() action, {
    String? conflictMessage,
  }) async {
    _setMutating(true);
    try {
      await action();
    } catch (e) {
      var message = userFacingError(e);
      if (conflictMessage != null &&
          classifyApiFailure(e) == ApiFailureKind.conflict) {
        message = conflictMessage;
        await _reload();
      }
      _setMutating(false);
      return message;
    }
    await _reload();
    _setMutating(false);
    return null;
  }

  /// Returns null on success, otherwise a user-facing message.
  Future<String?> updateSeverity(
    VerificationDeficiencyRow row,
    int severityId,
  ) {
    final id = row.deficiencyId;
    final version = row.deficiencyVersion;
    if (id == null || version == null) {
      return Future.value('This deficiency cannot be updated yet.');
    }
    return _mutate(
      () => _repository.updateDeficiencySeverity(
        id,
        severityId: severityId,
        expectedVersion: version,
      ),
      conflictMessage: verificationSeverityConflictMessage,
    );
  }

  Future<String?> flagRemark(
    VerificationDeficiencyRow row, {
    String? assetUniqueId,
    int? severityId,
  }) {
    final recordId = _recordId;
    final index = row.remarkIndex;
    if (recordId == null || index == null) {
      return Future.value('This remark cannot be flagged.');
    }
    return _mutate(
      () => _repository.flagRemarkDeficiency(
        recordId,
        remarkIndex: index,
        assetUniqueId: assetUniqueId,
        severityId: severityId,
      ),
    );
  }

  Future<String?> unflagRemark(VerificationDeficiencyRow row) {
    final recordId = _recordId;
    final index = row.remarkIndex;
    if (recordId == null || index == null) {
      return Future.value('This remark cannot be un-flagged.');
    }
    return _mutate(
      () => _repository.unflagRemarkDeficiency(recordId, remarkIndex: index),
    );
  }

  /// Un-checks a checked-out group at TECH_COMPLETED. The server then returns
  /// the Job Work to the technician, so no reload is performed (the caller
  /// closes the screen). Returns null on success.
  Future<String?> uncheckGroup(
    VerificationAssetGroup group,
    String reason,
  ) async {
    final recordId = _recordId;
    if (recordId == null) return 'No checklist record to update.';
    _setMutating(true);
    try {
      await _repository.setGroupInclusion(
        recordId,
        assetCategoryId: group.assetCategoryId,
        assetName: group.assetName,
        included: false,
        reason: reason,
      );
    } catch (e) {
      _setMutating(false);
      return userFacingError(e);
    }
    _setMutating(false);
    return null;
  }
}
