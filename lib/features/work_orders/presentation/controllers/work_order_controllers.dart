import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
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

  Future<void> fetchWorkOrders({bool forceRefresh = false}) async {
    final current = state;
    if (current is! WorkOrderListLoaded || forceRefresh) {
      state = const WorkOrderListLoading();
    }

    try {
      final orders = await _repository.fetchWorkOrders();
      // Carry the active filter and search term across the refresh. Rebuilding
      // the state from scratch would clear them while the search field on screen
      // still shows the query, leaving the list contradicting the visible filter.
      final previous = state is WorkOrderListLoaded
          ? state as WorkOrderListLoaded
          : (current is WorkOrderListLoaded ? current : null);
      state = previous != null
          ? previous.copyWith(workOrders: orders)
          : WorkOrderListLoaded(workOrders: orders);
    } catch (e) {
      state = WorkOrderListError(e.toString());
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

  void setSearchQuery(String query) {
    if (state is WorkOrderListLoaded) {
      final current = state as WorkOrderListLoaded;
      state = current.copyWith(searchQuery: query);
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
    } catch (e) {
      state = current.copyWith(isTransitioning: false, actionMessage: null);
      state = WorkOrderDetailError('Failed to start execution: $e');
      return null;
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
      state = current.copyWith(isTransitioning: false, actionMessage: null);
      state = WorkOrderDetailError('Status transition failed: $e');
      return false;
    }
  }
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
    // belongs to the selected status.
    final line = current.record.lines.firstWhere(
      (l) => l.id == lineId,
      orElse: () => current.record.lines.first,
    );
    final validActionIds = statusOptionId == null
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

      final updatedLines = current.record.lines.map((l) {
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

      state = current.copyWith(
        record: current.record.copyWith(lines: updatedLines),
        successMessage: 'Saved',
      );
      return true;
    } catch (e) {
      state = current.copyWith(errorMessage: 'Failed to save observation: $e');
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

  /// Surfaces the server's own validation message (incomplete checklist, no
  /// group checked out, ...) instead of a raw exception dump.
  String _readableError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final detail = data['detail'] ?? data['error'];
        if (detail != null) return detail.toString();
        final first = data.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        if (first != null) return first.toString();
      }
      if (data is List && data.isNotEmpty) return data.first.toString();
      if (data is String && data.isNotEmpty) return data;
    }
    return error.toString();
  }
}
