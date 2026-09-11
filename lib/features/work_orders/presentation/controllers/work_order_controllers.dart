import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
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
  return WorkOrderRepository(api, cacheService: cache, syncManager: syncManager);
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

  Future<void> fetchWorkOrders({bool forceRefresh = false}) async {
    final previous = _resolvePrevious();
    if (previous == null || forceRefresh) {
      state = const WorkOrderListLoading();
    }

    try {
      final scope = previous?.orgScope ?? OrgScopeSelection.empty;
      final orders = await _repository.fetchWorkOrders(
        dateFrom: formatApiDate(previous?.dateFrom),
        dateTo: formatApiDate(previous?.dateTo),
        zoneId: scope.zoneId,
        divisionId: scope.divisionId,
        depotId: scope.depotId,
        stationId: scope.stationId,
      );
      // Carry the active filter and search term across the refresh. Rebuilding
      // the state from scratch would clear them while the search field on screen
      // still shows the query, leaving the list contradicting the visible filter.
      state = previous != null
          ? previous.copyWith(workOrders: orders)
          : WorkOrderListLoaded(workOrders: orders);
    } catch (e) {
      state = WorkOrderListError(e.toString(), previousLoaded: previous);
    }
  }

  void setStatusFilter(WorkOrderStatus? status) {
    if (state is WorkOrderListLoaded) {
      final current = state as WorkOrderListLoaded;
      state = current.copyWith(
        selectedStatusFilter: status,
        clearStatusFilter: status == null,
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
    if (state is WorkOrderListLoaded) {
      final current = state as WorkOrderListLoaded;
      state = current.copyWith(searchQuery: query);
    }
  }

  /// Server-side date filter. Unlike status chips this is not applied in memory:
  /// the list can be unbounded, so the range is sent as `date_from`/`date_to`
  /// (main register) or `start_date`/`end_date` (staff-scoped "My Work" —
  /// see WorkOrderApiService.getWorkOrders).
  Future<void> setDateRange(DateTime? from, DateTime? to) async {
    final previous = _resolvePrevious();
    final scope = previous?.orgScope ?? OrgScopeSelection.empty;
    try {
      final orders = await _repository.fetchWorkOrders(
        dateFrom: formatApiDate(from),
        dateTo: formatApiDate(to),
        zoneId: scope.zoneId,
        divisionId: scope.divisionId,
        depotId: scope.depotId,
        stationId: scope.stationId,
      );
      state = WorkOrderListLoaded(
        workOrders: orders,
        selectedStatusFilter: previous?.selectedStatusFilter,
        searchQuery: previous?.searchQuery ?? '',
        dateFrom: from,
        dateTo: to,
        orgScope: scope,
      );
    } catch (e) {
      state = WorkOrderListError(e.toString(), previousLoaded: previous);
    }
  }

  /// Server-side Zone/Division/Depot/Station filter, same reasoning as
  /// [setDateRange] — not an in-memory filter, sent as query params.
  Future<void> setOrgScope(OrgScopeSelection scope) async {
    final previous = _resolvePrevious();
    try {
      final orders = await _repository.fetchWorkOrders(
        dateFrom: formatApiDate(previous?.dateFrom),
        dateTo: formatApiDate(previous?.dateTo),
        zoneId: scope.zoneId,
        divisionId: scope.divisionId,
        depotId: scope.depotId,
        stationId: scope.stationId,
      );
      state = WorkOrderListLoaded(
        workOrders: orders,
        selectedStatusFilter: previous?.selectedStatusFilter,
        searchQuery: previous?.searchQuery ?? '',
        dateFrom: previous?.dateFrom,
        dateTo: previous?.dateTo,
        orgScope: scope,
      );
    } catch (e) {
      state = WorkOrderListError(e.toString(), previousLoaded: previous);
    }
  }
}

// --- Work Order Detail Controller ---
final workOrderDetailControllerProvider =
    NotifierProvider.family<WorkOrderDetailController, WorkOrderDetailState, int>(() {
  return WorkOrderDetailController();
});

class WorkOrderDetailController extends FamilyNotifier<WorkOrderDetailState, int> {
  @override
  WorkOrderDetailState build(int arg) {
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
      state = WorkOrderDetailError(e.toString());
    }
  }

  /// Loads server-permitted transitions and the audit trail into the current
  /// detail state, ignoring failures of either.
  Future<void> loadActionsAndAudit() async {
    final results = await Future.wait([
      _repository.fetchAllowedActions(arg).then<Object?>((v) => v).catchError((_) => null),
      _repository.fetchAudit(arg).then<Object?>((v) => v).catchError((_) => null),
    ]);

    final current = state;
    if (current is! WorkOrderDetailLoaded) return;
    state = current.copyWith(
      actions: results[0] as WorkOrderActionSet?,
      audit: results[1] as WorkOrderAudit?,
    );
  }

  Future<int?> startExecution() async {
    final current = state;
    if (current is! WorkOrderDetailLoaded) return null;

    state = current.copyWith(isTransitioning: true, actionMessage: 'Starting execution...');
    try {
      final recordId = await _repository.startExecution(arg);
      // Reload updated work order status
      final updatedWo = await _repository.fetchWorkOrderById(arg);
      state = WorkOrderDetailLoaded(workOrder: updatedWo);
      // Also refresh list
      unawaited(ref.read(workOrderListControllerProvider.notifier).fetchWorkOrders(forceRefresh: true));
      return recordId;
    } on StartExecutionQueuedOffline catch (e) {
      // Queued for later, not a failure — stay on the detail view (there is
      // no real record id yet to navigate anywhere with) and surface it as
      // an informational message rather than a full error screen.
      state = current.copyWith(isTransitioning: false, actionMessage: e.toString());
      return null;
    } catch (e) {
      state = current.copyWith(isTransitioning: false, actionMessage: null);
      state = WorkOrderDetailError('Failed to start execution: ${_readableError(e)}');
      return null;
    }
  }

  Future<List<Technician>> fetchAssignableTechnicians() {
    final current = state;
    final depotId = current is WorkOrderDetailLoaded ? current.workOrder.depotId : null;
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
      state = WorkOrderDetailLoaded(workOrder: updatedWo);
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

    state = current.copyWith(isTransitioning: true, actionMessage: 'Verifying...');
    try {
      final updatedWo = await _repository.verifyWorkOrder(arg, remarks: remarks);
      state = WorkOrderDetailLoaded(workOrder: updatedWo);
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

    state = current.copyWith(isTransitioning: true, actionMessage: 'Updating status...');
    try {
      final updatedWo = await _repository.transitionStatus(
        arg,
        status: status,
        remarks: remarks,
        checklist: checklist,
        evidence: evidence,
      );
      state = WorkOrderDetailLoaded(workOrder: updatedWo);
      // The permitted transitions and history both change with the status, so
      // refresh them rather than leaving the previous status's buttons on screen.
      unawaited(loadActionsAndAudit());
      unawaited(ref.read(workOrderListControllerProvider.notifier).fetchWorkOrders(forceRefresh: true));
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
final checklistControllerProvider =
    NotifierProvider.family<ChecklistController, ChecklistState, int>(() {
  return ChecklistController();
});

class ChecklistController extends FamilyNotifier<ChecklistState, int> {
  @override
  ChecklistState build(int arg) {
    return const ChecklistLoading();
  }

  IWorkOrderRepository get _repository => ref.read(workOrderRepositoryProvider);

  Future<void> loadRecord() async {
    state = const ChecklistLoading();
    try {
      final record = await _repository.fetchMaintenanceRecord(arg);
      state = ChecklistLoaded(record: record);
    } catch (e) {
      state = ChecklistError('Failed to load checklist: $e');
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
      await _repository.submitChecklistLine(arg, payload);

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
          );
        }
        return l;
      }).toList();

      state = latest.copyWith(
        record: latest.record.copyWith(lines: updatedLines),
        successMessage: 'Saved',
      );
      return true;
    } catch (e) {
      final latest = state;
      if (latest is! ChecklistLoaded) return false;
      state = latest.copyWith(errorMessage: 'Failed to save observation: $e');
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
      if (proofJpegPath != null || otherStaff != null) {
        await _repository.uploadEvidence(
          arg,
          proofJpegPath: proofJpegPath,
          remarks: remarks.trim(),
          otherStaff: otherStaff,
        );
      }

      await _repository.completeMaintenanceRecord(
        arg,
        technicianName: technicianName,
        remarks: remarks.trim(),
        supervisorName: supervisorName,
      );
      state = const ChecklistCompleted();
      return true;
    } catch (e) {
      state = current.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to complete execution: ${_readableError(e)}',
      );
      return false;
    }
  }

  EvidenceService get _evidenceService => ref.read(evidenceServiceProvider);
  SyncManager get _syncManager => ref.read(syncManagerProvider.notifier);

  Future<bool> uploadLineAttachment({
    required int lineId,
    required String kind,
    required String imagePath,
    DateTime? capturedAt,
  }) async {
    final current = state;
    if (current is! ChecklistLoaded) return false;

    try {
      final attachment = await _repository.uploadLineAttachment(
        arg,
        lineId: lineId,
        kind: kind,
        imagePath: imagePath,
        capturedAt: capturedAt,
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
      state = latest.copyWith(errorMessage: 'Failed to upload photo: ${_readableError(e)}');
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

    try {
      if (idempotencyKey != null) {
        await _syncManager.removeCommand(idempotencyKey);
      }
      if (localPath != null) {
        try {
          await _evidenceService.discard(localPath);
        } catch (_) {}
      }
      if (attachmentId > 0) {
        await _repository.deleteLineAttachment(
          arg,
          lineId: lineId,
          attachmentId: attachmentId,
        );
      }

      final latest = state;
      if (latest is! ChecklistLoaded) return true;

      final updatedLines = latest.record.lines.map((l) {
        if (l.id == lineId) {
          return l.copyWith(
            attachments: l.attachments.where((a) => a.id != attachmentId).toList(),
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
      state = latest.copyWith(errorMessage: 'Failed to delete photo: ${_readableError(e)}');
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
      final outbox = await ref.read(localCacheServiceProvider).getOutboxCommands();
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

  Future<void> retryAttachment(LineAttachment attachment) async {    if (attachment.idempotencyKey != null) {
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
        state = latest.copyWith(record: latest.record.copyWith(lines: updatedLines));
      }
    }
  }

  String _readableError(Object error) => workOrderReadableError(error);
}

/// Surfaces the server's own validation message instead of a raw exception
/// dump (SSOT §6: Android must NOT display raw Dio exceptions such as
/// "DioException [receive timeout]: ..." — production UI gets a concise
/// message; the structured detail is for development logging only).
///
/// The previous version only handled the case where a server response body
/// came back (`error.response?.data`) and fell through to `error.toString()`
/// otherwise — which is exactly the raw Dio dump this function exists to
/// prevent, and is what happens on every network-level failure (timeout,
/// no connectivity, connection refused) since those never get a response at
/// all. Those cases are handled explicitly first, before touching the
/// response body.
String workOrderReadableError(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to respond. Please check your connection and try again.';
      case DioExceptionType.connectionError:
        return 'Unable to reach the server. Please check your connection and try again.';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      case DioExceptionType.badCertificate:
        return 'A secure connection to the server could not be established.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break; // Fall through to the response-body parsing below.
      default:
        break; // Other/future Dio exception types: same fallback.
    }

    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'] ?? data['error'];
      if (detail != null) return detail.toString();
      if (data.values.isNotEmpty) {
        final first = data.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        if (first != null) return first.toString();
      }
    }
    if (data is List && data.isNotEmpty) return data.first.toString();
    if (data is String && data.isNotEmpty) return data;

    // `unknown` with no response body — e.g. a SocketException surfaced
    // outside the explicit connectionError case above. Still must not leak
    // the raw DioException string.
    if (error.response == null) {
      return 'Unable to reach the server. Please check your connection and try again.';
    }
    return 'The server reported a problem (HTTP ${error.response?.statusCode ?? 'error'}). Please try again.';
  }
  // Not a DioException — e.g. a repository-thrown business exception
  // (`Exception('A technician must be assigned')`, `ArgumentError`, etc.)
  // whose message is already human-authored, not a raw network/HTTP dump.
  // SSOT §6 is specifically about not leaking raw *Dio* exceptions; a plain
  // Dart exception's toString() is exactly what should reach the user here.
  return error.toString();
}

