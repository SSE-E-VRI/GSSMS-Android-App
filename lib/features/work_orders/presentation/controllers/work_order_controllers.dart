import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'dart:async';
import 'package:dio/dio.dart' show DioException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/sync/mutation_outcome.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/widgets/date_range_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/technician.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';

final workOrderApiServiceProvider = Provider<WorkOrderApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return WorkOrderApiService(dio);
});

final workOrderRepositoryProvider = Provider<IWorkOrderRepository>((ref) {
  final api = ref.watch(workOrderApiServiceProvider);
  final cache = ref.watch(localCacheServiceProvider);
  final syncManager = ref.watch(syncManagerProvider.notifier);
  return WorkOrderRepository(api,
      cacheService: cache, syncManager: syncManager,
      sessionProvider: () => ref.read(authRepositoryProvider).currentSession);
});

// --- Work Order List Controller ---
final workOrderListControllerProvider =
    NotifierProvider<WorkOrderListController, WorkOrderListState>(() {
  return WorkOrderListController();
});

class WorkOrderListController extends Notifier<WorkOrderListState> {
  @override
  WorkOrderListState build() {
    return const WorkOrderListLoading();
  }

  IWorkOrderRepository get _repository => ref.read(workOrderRepositoryProvider);

  /// The last successfully loaded filters, whether the current state is
  /// still that loaded state or an error that carried them forward — so a
  /// retry/filter-change issued after a failure doesn't silently reset them.
  WorkOrderListLoaded? _resolvePrevious() {
    final s = state;
    if (s is WorkOrderListLoaded) return s;
    if (s is WorkOrderListError) return s.previousLoaded;
    return null;
  }

  /// Incremented per server fetch so a slow response for an older filter
  /// (e.g. the user changed the date range twice quickly) cannot overwrite
  /// the result of the newer one.
  int _requestSeq = 0;

  /// Fetches from the server with the current filters. Every call hits the
  /// server; [forceRefresh] is kept so call sites still read as intent.
  Future<void> fetchWorkOrders({bool forceRefresh = false}) async {
    final previous = _resolvePrevious();
    // Stale-while-refresh: a pull-to-refresh or post-mutation reload keeps the
    // current rows on screen (the refresh indicator shows progress) instead of
    // blanking the list; only a first load has nothing to show.
    if (previous == null) {
      state = const WorkOrderListLoading();
    }
    await _load(
      base: previous,
      dateFrom: previous?.dateFrom,
      dateTo: previous?.dateTo,
      scope: previous?.orgScope ?? OrgScopeSelection.empty,
    );
  }

  /// Fetches with the given server-side filters and applies the result on top
  /// of [base], so every client-side filter (status, type, infra, search)
  /// survives the reload instead of silently resetting while its dropdown
  /// still shows the old selection.
  Future<void> _load({
    required WorkOrderListLoaded? base,
    required DateTime? dateFrom,
    required DateTime? dateTo,
    required OrgScopeSelection scope,
  }) async {
    final seq = ++_requestSeq;
    try {
      final orders = await _repository.fetchWorkOrders(
        dateFrom: formatApiDate(dateFrom),
        dateTo: formatApiDate(dateTo),
        zoneId: scope.zoneId,
        divisionId: scope.divisionId,
        depotId: scope.depotId,
        stationId: scope.stationId,
      );
      if (seq != _requestSeq) return;
      state = WorkOrderListLoaded(
        workOrders: orders,
        selectedStatusFilter: base?.selectedStatusFilter,
        selectedTypeFilter: base?.selectedTypeFilter,
        searchQuery: base?.searchQuery ?? '',
        dateFrom: dateFrom,
        dateTo: dateTo,
        orgScope: scope,
        infraType: base?.infraType ?? InfraFilterType.all,
        infraName: base?.infraName,
      );
    } catch (e) {
      if (seq != _requestSeq) return;
      state = WorkOrderListError(userFacingError(e), previousLoaded: base);
    }
  }

  void setStatusFilter(WorkOrderStatus? status) {
    final s = state;
    if (s is WorkOrderListLoaded) {
      state = s.copyWith(
        selectedStatusFilter: status,
        clearStatusFilter: status == null,
      );
    } else if (s is WorkOrderListError && s.previousLoaded != null) {
      state = WorkOrderListError(
        s.message,
        previousLoaded: s.previousLoaded!.copyWith(
          selectedStatusFilter: status,
          clearStatusFilter: status == null,
        ),
      );
    }
  }

  /// Web Job Works type chips (All / Corrective / Preventive) — in-memory,
  /// like the status chips, so they combine with search + infra filters.
  void setTypeFilter(WorkOrderType? type) {
    final s = state;
    if (s is WorkOrderListLoaded) {
      state = s.copyWith(
        selectedTypeFilter: type,
        clearTypeFilter: type == null,
      );
    } else if (s is WorkOrderListError && s.previousLoaded != null) {
      state = WorkOrderListError(
        s.message,
        previousLoaded: s.previousLoaded!.copyWith(
          selectedTypeFilter: type,
          clearTypeFilter: type == null,
        ),
      );
    }
  }

  /// Web filter row: Infra Type + Infra Name. Client-side until the API
  /// offers matching query params.
  void setInfraFilter(InfraFilterType type, String? name) {
    final s = state;
    if (s is WorkOrderListLoaded) {
      // Changing type invalidates a name picked under the old type.
      final keepName = s.infraType == type ? name : null;
      state = s.copyWith(
        infraType: type,
        infraName: keepName,
        clearInfraName: keepName == null,
      );
    } else if (s is WorkOrderListError && s.previousLoaded != null) {
      state = WorkOrderListError(
        s.message,
        previousLoaded: s.previousLoaded!.copyWith(
          infraType: type,
          infraName: null,
          clearInfraName: true,
        ),
      );
    }
  }

  void setInfraName(String? name) {
    final s = state;
    if (s is WorkOrderListLoaded) {
      state = s.copyWith(infraName: name, clearInfraName: name == null);
    } else if (s is WorkOrderListError && s.previousLoaded != null) {
      state = WorkOrderListError(
        s.message,
        previousLoaded: s.previousLoaded!
            .copyWith(infraName: name, clearInfraName: name == null),
      );
    }
  }

  void clearInfraFilters() {
    final s = state;
    if (s is WorkOrderListLoaded) {
      state = s.copyWith(infraType: InfraFilterType.all, clearInfraName: true);
    } else if (s is WorkOrderListError && s.previousLoaded != null) {
      state = WorkOrderListError(
        s.message,
        previousLoaded: s.previousLoaded!.copyWith(
          infraType: InfraFilterType.all,
          clearInfraName: true,
        ),
      );
    }
  }

  void setSearchQuery(String query) {
    final s = state;
    if (s is WorkOrderListLoaded) {
      state = s.copyWith(searchQuery: query);
    } else if (s is WorkOrderListError && s.previousLoaded != null) {
      state = WorkOrderListError(
        s.message,
        previousLoaded: s.previousLoaded!.copyWith(searchQuery: query),
      );
    }
  }

  /// Server-side date filter. Unlike status chips this is not applied in memory:
  /// the list can be unbounded, so the range is sent as `date_from`/`date_to`
  /// (main register) or `start_date`/`end_date` (staff-scoped "My Work" —
  /// see WorkOrderApiService.getWorkOrders).
  Future<void> setDateRange(DateTime? from, DateTime? to) async {
    final previous = _resolvePrevious();
    await _load(
      base: previous,
      dateFrom: from,
      dateTo: to,
      scope: previous?.orgScope ?? OrgScopeSelection.empty,
    );
  }

  /// Server-side Zone/Division/Depot/Station filter, same reasoning as
  /// [setDateRange] — not an in-memory filter, sent as query params.
  Future<void> setOrgScope(OrgScopeSelection scope) async {
    final previous = _resolvePrevious();
    await _load(
      base: previous,
      dateFrom: previous?.dateFrom,
      dateTo: previous?.dateTo,
      scope: scope,
    );
  }
}

// --- Work Order Detail Controller ---
// H7: autoDispose so per-id detail controllers (incl. full audit history)
// don't accumulate for the whole app session — the screen re-fetches on open.
final workOrderDetailControllerProvider = NotifierProvider.autoDispose
    .family<WorkOrderDetailController, WorkOrderDetailState, int>((arg) {
  return WorkOrderDetailController(arg);
});

class WorkOrderDetailController extends Notifier<WorkOrderDetailState> {
  WorkOrderDetailController(this.arg);

  final int arg;

  @override
  WorkOrderDetailState build() {
    return const WorkOrderDetailLoading();
  }

  IWorkOrderRepository get _repository => ref.read(workOrderRepositoryProvider);

  Future<void> loadDetail() async {
    state = const WorkOrderDetailLoading();
    try {
      final workOrder = await _repository.fetchWorkOrderById(arg);
      state = WorkOrderDetailLoaded(workOrder: workOrder);
      // The work order itself is the screen's payload; permitted actions and
      // history are enrichments, so a failure there (offline, or a role without
      // audit access) must not turn a readable detail page into an error.
      await loadActionsAndAudit();
    } catch (e) {
      state = WorkOrderDetailError(userFacingError(e));
    }
  }

  /// Loads server-permitted transitions and the audit trail into the current
  /// detail state, ignoring failures of either.
  Future<void> loadActionsAndAudit() async {
    var actionsUnavailableOffline = false;
    final results = await Future.wait([
      _repository
          .fetchAllowedActions(arg)
          .then<Object?>((v) => v)
          .catchError((Object error) {
            actionsUnavailableOffline =
                classifyApiFailure(error) == ApiFailureKind.network;
            return null;
          }),
      _repository
          .fetchAudit(arg)
          .then<Object?>((v) => v)
          .catchError((_) => null),
    ]);

    final current = state;
    if (current is! WorkOrderDetailLoaded) return;
    state = current.copyWith(
      actions: results[0] as WorkOrderActionSet?,
      audit: results[1] as WorkOrderAudit?,
      actionsUnavailableOffline: actionsUnavailableOffline,
    );
  }

  Future<int?> startExecution() async {
    final current = state;
    if (current is! WorkOrderDetailLoaded) return null;

    state = current.copyWith(
        isTransitioning: true, actionMessage: 'Starting execution...');
    try {
      final recordId = await _repository.startExecution(arg);
      // Reload updated work order status. Keep the loaded actions/audit
      // through the copy (M10) — a fresh WorkOrderDetailLoaded would wipe the
      // enrichment until the refetch returns.
      final updatedWo = await _repository.fetchWorkOrderById(arg);
      final latest = state;
      if (latest is WorkOrderDetailLoaded) {
        state = latest.copyWith(
          workOrder: updatedWo,
          isTransitioning: false,
          actionMessage: 'Execution started.',
          errorMessage: null,
        );
      } else {
        state = WorkOrderDetailLoaded(workOrder: updatedWo);
      }
      // Refresh permitted actions/history for the new status.
      unawaited(loadActionsAndAudit());
      // Also refresh list
      unawaited(ref
          .read(workOrderListControllerProvider.notifier)
          .fetchWorkOrders(forceRefresh: true));
      return recordId;
    } on StartExecutionQueuedOffline catch (e) {
      // Queued for later, not a failure — stay on the detail view (there is
      // no real record id yet to navigate anywhere with) and surface it as
      // an informational message rather than a full error screen.
      state =
          current.copyWith(isTransitioning: false, actionMessage: e.toString());
      return null;
    } catch (e) {
      // Stay on Loaded with an inline message (consistent with
      // assign/verify/transition) so the detail is not lost on error.
      state = current.copyWith(
          isTransitioning: false,
          actionMessage: 'Failed to start execution: ${_readableError(e)}');
      return null;
    }
  }

  Future<List<Technician>> fetchAssignableTechnicians() {
    final current = state;
    final depotId =
        current is WorkOrderDetailLoaded ? current.workOrder.depotId : null;
    return _repository.fetchAssignableTechnicians(depotId: depotId);
  }

  /// PATCH `assigned_to` then transition to ASSIGNED — same order as the web client.
  Future<bool> assignAndActivate(int technicianId) async {
    final current = state;
    if (current is! WorkOrderDetailLoaded) return false;

    state = current.copyWith(
      isTransitioning: true,
      actionMessage: 'Assigning technician...',
    );
    try {
      await _repository.assignTechnician(arg, technicianId);
      final updatedWo = await _repository.transitionStatus(
        arg,
        status: 'ASSIGNED',
      );
      // M10: preserve the loaded actions/audit until the refetch returns.
      final latest = state;
      if (latest is WorkOrderDetailLoaded) {
        state = latest.copyWith(
          workOrder: updatedWo,
          isTransitioning: false,
          actionMessage: null,
          errorMessage: null,
        );
      } else {
        state = WorkOrderDetailLoaded(workOrder: updatedWo);
      }
      unawaited(loadActionsAndAudit());
      unawaited(
        ref.read(workOrderListControllerProvider.notifier).fetchWorkOrders(
              forceRefresh: true,
            ),
      );
      return true;
    } catch (e) {
      state = current.copyWith(
        isTransitioning: false,
        actionMessage: null,
        errorMessage: 'Failed to assign technician: ${_readableError(e)}',
      );
      return false;
    }
  }

  /// Dedicated verify action so the server records `verified_by`.
  Future<bool> verifyWorkOrder({String? remarks}) async {
    final current = state;
    if (current is! WorkOrderDetailLoaded) return false;

    state =
        current.copyWith(isTransitioning: true, actionMessage: 'Verifying...');
    try {
      final updatedWo =
          await _repository.verifyWorkOrder(arg, remarks: remarks);
      // M10: preserve the loaded actions/audit until the refetch returns.
      final latest = state;
      if (latest is WorkOrderDetailLoaded) {
        state = latest.copyWith(
          workOrder: updatedWo,
          isTransitioning: false,
          actionMessage: null,
          errorMessage: null,
        );
      } else {
        state = WorkOrderDetailLoaded(workOrder: updatedWo);
      }
      unawaited(loadActionsAndAudit());
      unawaited(
        ref.read(workOrderListControllerProvider.notifier).fetchWorkOrders(
              forceRefresh: true,
            ),
      );
      return true;
    } catch (e) {
      state = current.copyWith(
        isTransitioning: false,
        actionMessage: null,
        errorMessage: 'Verification failed: ${_readableError(e)}',
      );
      return false;
    }
  }

  Future<bool> transitionStatus({
    required String status,
    String? remarks,
    Map<String, dynamic>? checklist,
    List<int>? evidence,
  }) async {
    final current = state;
    if (current is! WorkOrderDetailLoaded) return false;

    state = current.copyWith(
        isTransitioning: true, actionMessage: 'Updating status...');
    try {
      final updatedWo = await _repository.transitionStatus(
        arg,
        status: status,
        remarks: remarks,
        checklist: checklist,
        evidence: evidence,
      );
      // M10: preserve the loaded actions/audit until the refetch returns.
      final latest = state;
      if (latest is WorkOrderDetailLoaded) {
        state = latest.copyWith(
          workOrder: updatedWo,
          isTransitioning: false,
          actionMessage: null,
          errorMessage: null,
        );
      } else {
        state = WorkOrderDetailLoaded(workOrder: updatedWo);
      }
      // The permitted transitions and history both change with the status, so
      // refresh them rather than leaving the previous status's buttons on screen.
      unawaited(loadActionsAndAudit());
      unawaited(ref
          .read(workOrderListControllerProvider.notifier)
          .fetchWorkOrders(forceRefresh: true));
      return true;
    } catch (e) {
      state = current.copyWith(
        isTransitioning: false,
        actionMessage: null,
        errorMessage: 'Status transition failed: ${_readableError(e)}',
      );
      return false;
    }
  }

  String _readableError(Object error) => workOrderReadableError(error);
}

// --- Checklist Controller ---
// H7: autoDispose — per-record checklist state (all lines, attachments,
// responses) must not be retained for visited records for the app lifetime.
final checklistControllerProvider = NotifierProvider.autoDispose
    .family<ChecklistController, ChecklistState, int>((arg) {
  return ChecklistController(arg);
});

class ChecklistController extends Notifier<ChecklistState> {
  ChecklistController(this.arg);

  final int arg;

  @override
  ChecklistState build() {
    return const ChecklistLoading();
  }

  IWorkOrderRepository get _repository => ref.read(workOrderRepositoryProvider);

  Future<void> loadRecord() async {
    state = const ChecklistLoading();
    try {
      final record = await _repository.fetchMaintenanceRecord(arg);
      state = ChecklistLoaded(record: record);
    } catch (e) {
      state = ChecklistError(userFacingError(e));
    }
  }

  void setActiveSubCategory(String? category) {
    if (state is ChecklistLoaded) {
      final current = state as ChecklistLoaded;
      state = current.copyWith(
        activeSubCategory: category,
        clearCategoryFilter: category == null,
      );
    }
  }

  /// Saves one checklist line.
  ///
  /// [value] is a plain string for scalar readings, or a `{R,Y,B}` /
  /// `{Volt,Amp}` map for the multi-part value types. `value` is always sent:
  /// the server assigns `recorded_value` unconditionally, so omitting the key
  /// would clear the reading on the server while the app still showed it.
  Future<bool> submitLineObservation({
    required int lineId,
    Object? value,
    String status = 'OK',
    int? statusOptionId,
    int? actionOptionId,
    String? remarks,
  }) async {
    final current = state;
    if (current is! ChecklistLoaded) return false;

    // An action taken is only valid for the status it hangs off; sending a
    // stale one is rejected by the backend, so drop it when it no longer
    // belongs to the selected status. Falling back to some other line here
    // (lines.first) would validate against the wrong line's status options —
    // if lineId genuinely isn't in this record (a race with a reload), skip
    // validation instead of guessing, so an actually-valid actionOptionId
    // isn't stripped (or a stale one wrongly kept) based on unrelated data.
    MaintenanceRecordLine? line;
    for (final l in current.record.lines) {
      if (l.id == lineId) {
        line = l;
        break;
      }
    }
    final validActionIds = (statusOptionId == null || line == null)
        ? const <int>[]
        : line.statusOptions
            .where((o) => o.id == statusOptionId)
            .expand((o) => o.actionOptions)
            .map((a) => a.id)
            .toList();
    final effectiveActionId =
        (actionOptionId != null && validActionIds.contains(actionOptionId))
            ? actionOptionId
            : null;

    final payload = <String, dynamic>{
      'line_id': lineId,
      'value': value,
      'status': status,
      'status_option': statusOptionId,
      'action_option': effectiveActionId,
      'remarks': remarks,
    };

    try {
      final outcome = await _repository.submitChecklistLine(arg, payload);

      // Re-read state now, not the pre-await `current`: another line's save
      // (an immediate one, or a debounced one on a different card) may have
      // completed while this request was in flight. Applying this update on
      // top of the stale snapshot would silently discard that other line's
      // already-server-confirmed change.
      final latest = state;
      if (latest is! ChecklistLoaded) return true;

      final updatedLines = latest.record.lines.map((l) {
        if (l.id == lineId) {
          return l.copyWith(
            recordedValue: value,
            status: status,
            statusOptionId: statusOptionId,
            actionOptionId: effectiveActionId,
            observationAction: remarks,
            isSaved: true,
            localSyncStatus: outcome == MutationOutcome.synced
                ? null : OutboxCommandStatus.pending,
          );
        }
        return l;
      }).toList();

      state = latest.copyWith(
        record: latest.record.copyWith(lines: updatedLines),
        successMessage: outcome == MutationOutcome.synced
            ? 'Saved'
            : 'Saved on this device. Will sync when a connection is available.',
      );
      return true;
    } catch (e) {
      final latest = state;
      if (latest is! ChecklistLoaded) return false;
      state = latest.copyWith(
          errorMessage: 'Could not save the reading: ${userFacingError(e)}');
      return false;
    }
  }

  /// True when the last [setGroupIncluded] failed because the server wants a
  /// reason (un-check at TECH_COMPLETED). The UI prompts and retries.
  bool groupReasonRequired = false;

  /// Checks an asset group out (`included: true`) or un-checks it. Online
  /// only: nothing is changed locally unless the server acknowledged.
  Future<bool> setGroupIncluded(
    ChecklistAssetGroup g,
    bool included, {
    String? reason,
  }) async {
    final current = state;
    if (current is! ChecklistLoaded) return false;
    if (current.savingGroupKeys.contains(g.key)) return false;

    groupReasonRequired = false;
    state = current.copyWith(
      savingGroupKeys: {...current.savingGroupKeys, g.key},
      successMessage: current.successMessage,
      errorMessage: current.errorMessage,
    );

    Set<String> without(ChecklistLoaded s) =>
        s.savingGroupKeys.where((k) => k != g.key).toSet();

    try {
      final result = await _repository.setGroupInclusion(
        arg,
        assetCategoryId: g.assetCategoryId,
        assetName: g.assetName,
        included: included,
        reason: reason,
      );

      final latest = state;
      if (latest is! ChecklistLoaded) return true;

      final name = g.assetName.trim().toLowerCase();
      final updatedLines = latest.record.lines.map((l) {
        if (l.assetCategoryId == g.assetCategoryId &&
            l.itemName.trim().toLowerCase() == name &&
            (!included || !l.isCheckedOut || l.excluded)) {
          return l.copyWith(
            checkedOut: result.checkedOut,
            checkoutSource: result.checkoutSource,
            excluded: result.excluded,
            exclusionReason: result.exclusionReason,
            applicability: result.applicability,
          );
        }
        return l;
      }).toList();

      state = latest.copyWith(
        record: latest.record.copyWith(lines: updatedLines),
        savingGroupKeys: without(latest),
        successMessage: result.returnedToTechnician
            ? 'Job Work returned to the technician for rework.'
            : (result.checkedOut
                ? '${g.displayTitle}: checked out'
                : '${g.displayTitle}: un-checked'),
      );
      return true;
    } catch (e) {
      final latest = state;
      if (latest is! ChecklistLoaded) return false;
      String message = 'Could not change group: ${userFacingError(e)}';
      if (e is DioException && e.response?.statusCode == 400) {
        final data = e.response?.data;
        // The server and this screen disagree about the group's state (it was
        // checked out by the supervisor, another device, or an earlier request
        // whose reply was lost). That is not a failure to report: re-read the
        // record so the toggle shows the server's truth.
        final conflict = _groupStateConflict(data, included);
        if (conflict) {
          return _resyncAfterGroupConflict(g, included, without);
        }
        if (data is Map && data['reason'] != null) {
          groupReasonRequired = true;
          final r = data['reason'];
          message = r is List ? r.join(' ') : '$r';
        }
      }
      state = latest.copyWith(
        savingGroupKeys: without(latest),
        errorMessage: groupReasonRequired ? null : message,
      );
      return false;
    }
  }

  /// True for the server's "already checked out" (check-out) and "not
  /// currently checked out" (un-check) 400s.
  static bool _groupStateConflict(Object? data, bool included) {
    if (data is! Map) return false;
    final err = '${data['error'] ?? ''}'.toLowerCase();
    return included
        ? err.contains('already checked out')
        : err.contains('not currently checked out');
  }

  /// Reloads the record after a group-state conflict. If the group is now in
  /// the requested state the request is treated as satisfied; otherwise the
  /// server holds a partial checkout for the group that this screen cannot
  /// resolve, and the user is told what to do instead of seeing a dead end.
  Future<bool> _resyncAfterGroupConflict(
    ChecklistAssetGroup g,
    bool included,
    Set<String> Function(ChecklistLoaded) without,
  ) async {
    try {
      final fresh = await _repository.fetchMaintenanceRecord(arg);
      final latest = state;
      if (latest is! ChecklistLoaded) return false;
      ChecklistAssetGroup? now;
      for (final candidate in fresh.assetGroups) {
        if (candidate.key == g.key) {
          now = candidate;
          break;
        }
      }
      final satisfied = now != null && now.checkedOut == included;
      state = latest.copyWith(
        record: fresh,
        savingGroupKeys: without(latest),
        successMessage: satisfied
            ? '${g.displayTitle}: ${included ? 'already checked out' : 'already un-checked'}'
            : null,
        errorMessage: satisfied
            ? null
            : '${g.displayTitle} is only partly checked out on the server, so '
                'it cannot be checked out from the app. Ask your supervisor '
                'to re-check it out, or report this to your administrator.',
      );
      return satisfied;
    } catch (_) {
      final latest = state;
      if (latest is! ChecklistLoaded) return false;
      state = latest.copyWith(
        savingGroupKeys: without(latest),
        errorMessage:
            'Could not change group: its state changed on the server. Pull to refresh and try again.',
      );
      return false;
    }
  }

  /// The server's minimum for TECH_COMPLETED remarks; enforced here so the
  /// technician is told before the round trip rather than after it fails.
  static const int minCompletionRemarksLength = 10;

  /// Finalises the record: uploads evidence first (so a rejected photo does not
  /// leave a completed record without its proof), then completes.
  Future<bool> completeExecution({
    required String technicianName,
    required String remarks,
    String? supervisorName,
    String? proofJpegPath,
    String? otherStaff,
  }) async {
    final current = state;
    if (current is! ChecklistLoaded) return false;

    if (remarks.trim().length < minCompletionRemarksLength) {
      state = current.copyWith(
        errorMessage:
            'Closing remarks must be at least $minCompletionRemarksLength characters.',
      );
      return false;
    }

    state = current.copyWith(isSubmitting: true);
    try {
      var evidenceOutcome = MutationOutcome.synced;
      if (proofJpegPath != null || otherStaff != null) {
        evidenceOutcome = await _repository.uploadEvidence(
          arg,
          proofJpegPath: proofJpegPath,
          remarks: remarks.trim(),
          otherStaff: otherStaff,
        );
      }

      // If the proof is waiting in the outbox, completion must wait behind
      // it (the outbox replays in order) — completing online now would leave
      // the record completed without its proof until the photo syncs.
      final completeOutcome = await _repository.completeMaintenanceRecord(
        arg,
        technicianName: technicianName,
        remarks: remarks.trim(),
        supervisorName: supervisorName,
        queueOnly: evidenceOutcome == MutationOutcome.queued,
      );
      state = ChecklistCompleted(
        queued: completeOutcome == MutationOutcome.queued,
      );
      return true;
    } catch (e) {
      // M11: re-read state, not the pre-await `current` — a line save or
      // attachment upload completing during the long round trip would be
      // silently discarded by copying the stale snapshot.
      final latest = state;
      if (latest is! ChecklistLoaded) return false;
      state = latest.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to complete execution: ${_readableError(e)}',
      );
      return false;
    }
  }

  EvidenceService get _evidenceService => ref.read(evidenceServiceProvider);
  SyncManager get _syncManager => ref.read(syncManagerProvider.notifier);

  bool _attachmentAllowed({required bool deleting, int? lineId}) {
    final current = state;
    if (current is! ChecklistLoaded) return false;
    if (current.record.id != arg ||
        (lineId != null &&
            !current.record.lines.any((line) => line.id == lineId))) {
      state = current.copyWith(
          errorMessage:
              'This photo does not belong to the open checklist. Refresh and try again.');
      return false;
    }
    final session = sessionFromAuth(ref.read(authControllerProvider));
    final allowed = deleting
        ? canDeleteChecklistAttachment(session)
        : canAddChecklistAttachment(session);
    if (!allowed || current.record.isPastTechCompleted) {
      state = current.copyWith(
          errorMessage: current.record.isPastTechCompleted
              ? 'Photos cannot be changed after technician completion.'
              : 'Photo ${deleting ? 'deletion' : 'upload'} is unavailable with your current access.');
      return false;
    }
    return true;
  }

  Future<bool> uploadLineAttachment({
    required int lineId,
    required String kind,
    required String imagePath,
    DateTime? capturedAt,
    String? source,
    double? latitude,
    double? longitude,
    double? locationAccuracyM,
    DateTime? locationRecordedAt,
  }) async {
    final current = state;
    if (current is! ChecklistLoaded) return false;

    if (!_attachmentAllowed(deleting: false, lineId: lineId)) return false;

    try {
      final attachment = await _repository.uploadLineAttachment(
        arg,
        lineId: lineId,
        kind: kind,
        imagePath: imagePath,
        capturedAt: capturedAt,
        source: source,
        latitude: latitude,
        longitude: longitude,
        locationAccuracyM: locationAccuracyM,
        locationRecordedAt: locationRecordedAt,
      );

      // Direct (online) success returns the server row — the local durable
      // copy is no longer needed. Queued placeholders carry no url, so their
      // file is kept for the outbox replay.
      if (attachment.url.isNotEmpty) {
        try {
          await _evidenceService.discard(imagePath);
        } catch (_) {}
      }

      final latest = state;
      if (latest is! ChecklistLoaded) return true;

      final updatedLines = latest.record.lines.map((l) {
        if (l.id == lineId) {
          return l.copyWith(
            attachments: [...l.attachments, attachment],
          );
        }
        return l;
      }).toList();

      state = latest.copyWith(
        record: latest.record.copyWith(lines: updatedLines),
      );
      return true;
    } catch (e) {
      final latest = state;
      if (latest is! ChecklistLoaded) return false;
      state = latest.copyWith(
          errorMessage: classifyApiFailure(e) == ApiFailureKind.permission
              ? 'Photo upload was denied. Your photo permission or job assignment may have changed. Sign in again to refresh access, or contact your administrator.'
              : 'Failed to upload photo: ${_readableError(e)}');
      return false;
    }
  }

  Future<bool> deleteLineAttachment({
    required int lineId,
    required int attachmentId,
    String? localPath,
    String? idempotencyKey,
  }) async {
    final current = state;
    if (current is! ChecklistLoaded) return false;

    if (!_attachmentAllowed(deleting: true, lineId: lineId)) return false;

    try {
      if (attachmentId > 0) {
        await _repository.deleteLineAttachment(
          arg,
          lineId: lineId,
          attachmentId: attachmentId,
        );
      }
      if (idempotencyKey != null) {
        await _syncManager.removeCommand(idempotencyKey);
      }
      if (localPath != null) {
        try {
          await _evidenceService.discard(localPath);
        } catch (_) {}
      }

      final latest = state;
      if (latest is! ChecklistLoaded) return true;

      final updatedLines = latest.record.lines.map((l) {
        if (l.id == lineId) {
          return l.copyWith(
            attachments:
                l.attachments.where((a) => a.id != attachmentId).toList(),
          );
        }
        return l;
      }).toList();

      state = latest.copyWith(
        record: latest.record.copyWith(lines: updatedLines),
      );
      return true;
    } catch (e) {
      final latest = state;
      if (latest is! ChecklistLoaded) return false;
      state = latest.copyWith(
          errorMessage: 'Failed to delete photo: ${_readableError(e)}');
      return false;
    }
  }

  /// Reconciles locally-queued photo placeholders with outbox + server truth.
  ///
  /// Called after an outbox drain settles. Placeholders whose command is gone
  /// from the outbox were uploaded — they are replaced by the fresh server
  /// rows. Placeholders whose command remains take its status/error, so a
  /// failed upload surfaces as a persistent per-thumbnail error (never only
  /// a transient SnackBar). Server rows always win for uploaded content.
  Future<void> reconcileAttachmentSyncState() async {
    final current = state;
    if (current is! ChecklistLoaded) return;
    try {
      final fresh = await _repository.fetchMaintenanceRecord(arg);
      final outbox =
          await ref.read(localCacheServiceProvider).getOutboxCommands();
      final byKey = <String, OutboxCommand>{};
      for (final cmd in outbox) {
        if (cmd.type == OutboxCommandType.uploadLineAttachment) {
          byKey[cmd.idempotencyKey] = cmd;
        }
      }
      final latest = state;
      if (latest is! ChecklistLoaded) return;
      final freshById = <int, MaintenanceRecordLine>{
        for (final l in fresh.lines) l.id: l,
      };
      final merged = latest.record.lines.map((line) {
        final serverLine = freshById[line.id];
        final serverAtts = serverLine?.attachments ?? const <LineAttachment>[];
        final keptPlaceholders = <LineAttachment>[];
        for (final local in line.attachments) {
          if (local.url.isNotEmpty) continue; // superseded by server rows
          final key = local.idempotencyKey;
          final cmd = key != null ? byKey[key] : null;
          if (cmd == null) continue; // uploaded (or dropped) — server row wins
          keptPlaceholders.add(local.copyWith(
            syncStatus: cmd.status,
            syncError: cmd.lastError,
            clearError: cmd.lastError == null,
          ));
        }
        return (serverLine ?? line).copyWith(
          attachments: [...serverAtts, ...keptPlaceholders],
        );
      }).toList();
      state = latest.copyWith(record: latest.record.copyWith(lines: merged));
    } catch (_) {}
  }

  Future<void> retryAttachment(LineAttachment attachment) async {
    if (!_attachmentAllowed(deleting: false)) return;
    final current = state as ChecklistLoaded;
    if (!current.record.lines.any((line) => line.attachments.any((a) =>
        a.id == attachment.id &&
        a.idempotencyKey == attachment.idempotencyKey))) {
      return;
    }
    if (attachment.idempotencyKey != null) {
      await _syncManager.retryCommand(attachment.idempotencyKey!);
      final latest = state;
      if (latest is ChecklistLoaded) {
        final updatedLines = latest.record.lines.map((l) {
          final updatedAtts = l.attachments.map((a) {
            if (a.idempotencyKey == attachment.idempotencyKey) {
              return a.copyWith(
                syncStatus: OutboxCommandStatus.pending,
                clearError: true,
              );
            }
            return a;
          }).toList();
          return l.copyWith(attachments: updatedAtts);
        }).toList();
        state = latest.copyWith(
            record: latest.record.copyWith(lines: updatedLines));
      }
    }
  }

  String _readableError(Object error) => workOrderReadableError(error);
}

/// User-facing text for any work-order failure (SSOT §6/§42). Kept as a named
/// entry point because several screens import it; the mapping lives in
/// [userFacingError].
String workOrderReadableError(Object error) => userFacingError(error);
