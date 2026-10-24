import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/mutation_outcome.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/batch_convert_result.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/deficiency_severity_option.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/group_inclusion_result.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_master.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/pm_approval_request.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/supervisor_mandate.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/technician.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';

/// Thrown by [WorkOrderRepository.startExecution] when the device is offline:
/// the request is queued for the server to actually create the maintenance
/// record once connectivity returns, so there is no real record id to give
/// the caller yet. Callers should show a "queued, will start once online"
/// message and skip navigating anywhere, rather than treat this as a
/// generic failure or invent a placeholder id.
class StartExecutionQueuedOffline implements Exception {
  const StartExecutionQueuedOffline();

  @override
  String toString() =>
      'Execution start has been queued and will begin automatically once the connection is restored.';
}

/// VERIFIED / CLOSED must not be queued offline (SSOT §8.3).
class OnlineRequiredException implements Exception {
  const OnlineRequiredException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class IWorkOrderRepository {
  Future<List<WorkOrder>> fetchWorkOrders({
    String? status,
    String? type,
    String? dateFrom,
    String? dateTo,
    String? updatedFrom,
    String? updatedTo,
    String? completionFrom,
    String? completionTo,
    int? zoneId,
    int? divisionId,
    int? depotId,
    int? stationId,
    int? lcGateId,
    int? serviceBuildingId,
    int? staffQuarterId,
    String? infraType,
    bool assignedToMe = false,
  });

  Future<WorkOrder> fetchWorkOrderById(int id);
  Future<WorkOrder> createWorkOrder({
    required String title,
    String? description,
    String type = 'PREVENTIVE',
    String priority = 'MEDIUM',
    int? depotId,
    int? stationId,
    int? infrastructureId,
    int? assetId,
    String? scheduledDate,
    int? maintenanceMasterId,
  });
  Future<List<MaintenanceMaster>> fetchMaintenanceMasters();
  Future<BatchConvertResult> createWorkOrdersFromComplaints(
      List<int> complaintIds);
  Future<BatchConvertResult> createWorkOrdersFromInspections(
      List<int> inspectionIds);
  Future<BatchConvertResult> createRectification(
    List<int> deficiencyIds, {
    bool onePerDeficiency = false,
  });
  Future<WorkOrderActionSet> fetchAllowedActions(int workOrderId);
  Future<WorkOrderAudit> fetchAudit(int workOrderId);
  Future<List<Technician>> fetchAssignableTechnicians({int? depotId});
  Future<WorkOrder> assignTechnician(int workOrderId, int technicianId);
  Future<WorkOrder> verifyWorkOrder(int workOrderId, {String? remarks});
  Future<VerificationWorkspace> fetchVerificationWorkspace(int workOrderId);

  // Online-only mutations/reads (no outbox): errors are rethrown to the UI.
  Future<WorkOrder> reassignWorkOrder(
    int workOrderId, {
    required int technicianId,
    required String reason,
  });
  Future<PrepareChecklistResult> prepareChecklist(int workOrderId);
  Future<List<SupervisorMandate>> getSupervisorMandates(int workOrderId);
  Future<SupervisorMandate> setSupervisorMandate(
    int workOrderId, {
    int? assetCategoryId,
    required String assetName,
    required String action,
    String reason = '',
  });
  Future<List<ChecklistGroupPreview>> getMasterChecklistGroups(int masterId);
  Future<GroupInclusionResult> setGroupInclusion(
    int recordId, {
    int? assetCategoryId,
    required String assetName,
    required bool included,
    String? reason,
  });
  Future<List<DeficiencySeverityOption>> getDeficiencySeverities();
  Future<DeficiencySeverityUpdate> updateDeficiencySeverity(
    int deficiencyId, {
    required int severityId,
    required int expectedVersion,
  });
  Future<RemarkFlagResult> flagRemarkDeficiency(
    int recordId, {
    required int remarkIndex,
    String? assetUniqueId,
    int? severityId,
  });
  Future<void> unflagRemarkDeficiency(int recordId, {required int remarkIndex});
  Future<Map<String, dynamic>> getScheduleApprovalState(int scheduleId);
  Future<List<ScheduleAlternative>> getScheduleAlternatives(int scheduleId);
  Future<ApprovalRequestSummary> requestPmSkip(
    int scheduleId, {
    required String reasonCode,
    required String remarks,
  });
  Future<ApprovalRequestSummary> requestChecklistChange(
    int scheduleId, {
    required int maintenanceMasterId,
    required String remarks,
  });
  Future<int> startExecution(int workOrderId);
  Future<WorkOrder> transitionStatus(
    int workOrderId, {
    required String status,
    String? remarks,
    Map<String, dynamic>? checklist,
    List<int>? evidence,
  });

  Future<MaintenanceRecord> fetchMaintenanceRecord(int recordId);

  /// Raw record rows for report resolution (`?work_order=` then `?schedule=`
  /// fallback, mirroring web ReportsView). Returns decoded maps because
  /// report shaping consumes the raw nested lines/options.
  Future<List<Map<String, dynamic>>> fetchMaintenanceRecords({
    int? workOrderId,
    int? scheduleId,
  });
  Future<MutationOutcome> submitChecklistLine(
      int recordId, Map<String, dynamic> lineData);

  Future<MutationOutcome> uploadEvidence(
    int recordId, {
    String? proofJpegPath,
    String? remarks,
    String? otherStaff,
  });

  /// [queueOnly] enqueues without trying the network first — used when the
  /// record's evidence was itself queued, so completion replays after it.
  Future<MutationOutcome> completeMaintenanceRecord(
    int recordId, {
    required String technicianName,
    required String remarks,
    String? supervisorName,
    bool queueOnly = false,
  });

  Future<LineAttachment> uploadLineAttachment(
    int recordId, {
    required int lineId,
    required String kind,
    required String imagePath,
    DateTime? capturedAt,
    String? source,
    double? latitude,
    double? longitude,
    double? locationAccuracyM,
    DateTime? locationRecordedAt,
  });

  Future<void> deleteLineAttachment(
    int recordId, {
    required int lineId,
    required int attachmentId,
  });
}

class WorkOrderRepository implements IWorkOrderRepository {
  WorkOrderRepository(
    this._apiService, {
    ILocalCacheService? cacheService,
    SyncManager? syncManager,
  })  : _cacheService = cacheService ?? LocalCacheService(),
        _syncManager = syncManager;

  final WorkOrderApiService _apiService;
  final ILocalCacheService _cacheService;
  final SyncManager? _syncManager;
  Future<void> _lineSaves = Future<void>.value();

  bool _isNetworkException(dynamic e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return true;
      }
      // On Android, airplane-mode/DNS failures typically surface as
      // `unknown` wrapping a SocketException — without this the offline
      // cache fallback and outbox enqueue never trigger.
      if (e.type == DioExceptionType.unknown && e.error is SocketException) {
        return true;
      }
      if (e.error is SocketException) return true;
    }
    return false;
  }

  /// Enqueue unless an identical PENDING command is already queued
  /// (double-tap offline must not create two idempotency keys for the same
  /// logical write — the server would apply it twice).
  /// Returns true when a new command was enqueued, false on dedup-hit.
  ///
  /// H4: the read/check/save runs atomically inside SyncManager's lock via
  /// [SyncManager.enqueueDeduped] — a check outside the lock let two
  /// near-simultaneous calls both pass and enqueue duplicates.
  Future<bool> _enqueueDeduped(
    OutboxCommand cmd, {
    bool Function(OutboxCommand existing)? matches,
  }) async {
    final sync = _syncManager;
    if (sync == null) return false;
    return sync.enqueueDeduped(
      cmd,
      isDuplicate: (existing) {
        // Same logical write only: same command type + entity, and any
        // caller-supplied content match.
        if (existing.type != cmd.type || existing.entityId != cmd.entityId) {
          return false;
        }
        if (matches != null) return matches(existing);
        return true;
      },
    );
  }

  @override
  Future<List<WorkOrder>> fetchWorkOrders({
    String? status,
    String? type,
    String? dateFrom,
    String? dateTo,
    String? updatedFrom,
    String? updatedTo,
    String? completionFrom,
    String? completionTo,
    int? zoneId,
    int? divisionId,
    int? depotId,
    int? stationId,
    int? lcGateId,
    int? serviceBuildingId,
    int? staffQuarterId,
    String? infraType,
    bool assignedToMe = false,
  }) async {
    // Only the unfiltered list is cached/restored — caching per filter
    // combination isn't worth the key-space, but that means the cache must
    // never be offered as a substitute for a *filtered* request below: it
    // would silently show whatever the last unfiltered (or differently
    // filtered) fetch was, with no indication the requested filters never
    // actually applied.
    final hasFilters = status != null ||
        type != null ||
        dateFrom != null ||
        dateTo != null ||
        updatedFrom != null ||
        updatedTo != null ||
        completionFrom != null ||
        completionTo != null ||
        zoneId != null ||
        divisionId != null ||
        depotId != null ||
        stationId != null ||
        lcGateId != null ||
        serviceBuildingId != null ||
        staffQuarterId != null ||
        infraType != null ||
        assignedToMe;
    try {
      final orders = await _apiService.getWorkOrders(
        status: status,
        type: type,
        dateFrom: dateFrom,
        dateTo: dateTo,
        updatedFrom: updatedFrom,
        updatedTo: updatedTo,
        completionFrom: completionFrom,
        completionTo: completionTo,
        zoneId: zoneId,
        divisionId: divisionId,
        depotId: depotId,
        stationId: stationId,
        lcGateId: lcGateId,
        serviceBuildingId: serviceBuildingId,
        staffQuarterId: staffQuarterId,
        infraType: infraType,
        assignedToMe: assignedToMe,
      );
      if (!hasFilters) await _cacheService.cacheWorkOrders(orders);
      return orders;
    } catch (e) {
      if (_isNetworkException(e) && !hasFilters) {
        final cached = await _cacheService.getCachedWorkOrders();
        if (cached.isNotEmpty) return cached;
      }
      rethrow;
    }
  }

  @override
  Future<WorkOrder> fetchWorkOrderById(int id) async {
    try {
      final order = await _apiService.getWorkOrder(id);
      await _cacheService.cacheWorkOrderDetail(order);
      return order;
    } catch (e) {
      if (_isNetworkException(e)) {
        final cached = await _cacheService.getCachedWorkOrderDetail(id);
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  @override
  Future<WorkOrder> createWorkOrder({
    required String title,
    String? description,
    String type = 'PREVENTIVE',
    String priority = 'MEDIUM',
    int? depotId,
    int? stationId,
    int? infrastructureId,
    int? assetId,
    String? scheduledDate,
    int? maintenanceMasterId,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      'type': type,
      'priority': priority,
      // No `source` — omit so the backend default (MANUAL_ENTRY) applies
      // (SSOT §14). `scheduled_date` is the creation field; `due_date` is a
      // read-only server-derived field (SSOT §15) and must not be sent here.
      if (depotId != null) 'depot': depotId,
      if (stationId != null) 'station': stationId,
      if (infrastructureId != null) 'infrastructure': infrastructureId,
      if (assetId != null) 'asset': assetId,
      if (scheduledDate != null) 'scheduled_date': scheduledDate,
      // Optional checklist template — `maintenance_master` is a plain
      // writable FK on WorkOrderSerializer (not in read_only_fields), same
      // field the web "New Job Work" template picker sends.
      if (maintenanceMasterId != null)
        'maintenance_master': maintenanceMasterId,
    };
    final order = await _apiService.createWorkOrder(payload);
    await _cacheService.cacheWorkOrderDetail(order);
    return order;
  }

  @override
  Future<List<MaintenanceMaster>> fetchMaintenanceMasters() {
    return _apiService.getMaintenanceMasters();
  }

  @override
  Future<BatchConvertResult> createWorkOrdersFromComplaints(
      List<int> complaintIds) {
    return _apiService.createWorkOrdersFromComplaints(complaintIds);
  }

  @override
  Future<BatchConvertResult> createWorkOrdersFromInspections(
      List<int> inspectionIds) {
    return _apiService.createWorkOrdersFromInspections(inspectionIds);
  }

  @override
  Future<BatchConvertResult> createRectification(
    List<int> deficiencyIds, {
    bool onePerDeficiency = false,
  }) {
    return _apiService.createRectification(
      deficiencyIds,
      onePerDeficiency: onePerDeficiency,
    );
  }

  /// Transitions the server permits right now. These are deliberately not
  /// cached: an offline client cannot know whether a transition is still
  /// allowed, and showing a stale action invites a write that will be rejected.
  @override
  Future<WorkOrderActionSet> fetchAllowedActions(int workOrderId) async {
    return _apiService.getAllowedActions(workOrderId);
  }

  @override
  Future<WorkOrderAudit> fetchAudit(int workOrderId) async {
    return _apiService.getAudit(workOrderId);
  }

  @override
  Future<List<Technician>> fetchAssignableTechnicians({int? depotId}) {
    return _apiService.getAssignableTechnicians(depotId: depotId);
  }

  @override
  Future<WorkOrder> assignTechnician(int workOrderId, int technicianId) async {
    final order = await _apiService.assignTechnician(workOrderId, technicianId);
    await _cacheService.cacheWorkOrderDetail(order);
    return order;
  }

  @override
  Future<WorkOrder> verifyWorkOrder(int workOrderId, {String? remarks}) async {
    final order =
        await _apiService.verifyWorkOrder(workOrderId, remarks: remarks);
    await _cacheService.cacheWorkOrderDetail(order);
    return order;
  }

  @override
  Future<VerificationWorkspace> fetchVerificationWorkspace(int workOrderId) {
    return _apiService.getVerificationWorkspace(workOrderId);
  }

  @override
  Future<WorkOrder> reassignWorkOrder(
    int workOrderId, {
    required int technicianId,
    required String reason,
  }) async {
    final order = await _apiService.reassignWorkOrder(
      workOrderId,
      technicianId: technicianId,
      reason: reason,
    );
    await _cacheService.cacheWorkOrderDetail(order);
    return order;
  }

  @override
  Future<PrepareChecklistResult> prepareChecklist(int workOrderId) =>
      _apiService.prepareChecklist(workOrderId);

  @override
  Future<List<SupervisorMandate>> getSupervisorMandates(int workOrderId) =>
      _apiService.getSupervisorMandates(workOrderId);

  @override
  Future<SupervisorMandate> setSupervisorMandate(
    int workOrderId, {
    int? assetCategoryId,
    required String assetName,
    required String action,
    String reason = '',
  }) =>
      _apiService.setSupervisorMandate(
        workOrderId,
        assetCategoryId: assetCategoryId,
        assetName: assetName,
        action: action,
        reason: reason,
      );

  @override
  Future<List<ChecklistGroupPreview>> getMasterChecklistGroups(int masterId) =>
      _apiService.getMasterChecklistGroups(masterId);

  @override
  Future<GroupInclusionResult> setGroupInclusion(
    int recordId, {
    int? assetCategoryId,
    required String assetName,
    required bool included,
    String? reason,
  }) =>
      _apiService.setGroupInclusion(
        recordId,
        assetCategoryId: assetCategoryId,
        assetName: assetName,
        included: included,
        reason: reason,
      );

  @override
  Future<List<DeficiencySeverityOption>> getDeficiencySeverities() =>
      _apiService.getDeficiencySeverities();

  @override
  Future<DeficiencySeverityUpdate> updateDeficiencySeverity(
    int deficiencyId, {
    required int severityId,
    required int expectedVersion,
  }) =>
      _apiService.updateDeficiencySeverity(
        deficiencyId,
        severityId: severityId,
        expectedVersion: expectedVersion,
      );

  @override
  Future<RemarkFlagResult> flagRemarkDeficiency(
    int recordId, {
    required int remarkIndex,
    String? assetUniqueId,
    int? severityId,
  }) =>
      _apiService.flagRemarkDeficiency(
        recordId,
        remarkIndex: remarkIndex,
        assetUniqueId: assetUniqueId,
        severityId: severityId,
      );

  @override
  Future<void> unflagRemarkDeficiency(int recordId,
          {required int remarkIndex}) =>
      _apiService.unflagRemarkDeficiency(recordId, remarkIndex: remarkIndex);

  @override
  Future<Map<String, dynamic>> getScheduleApprovalState(int scheduleId) =>
      _apiService.getScheduleApprovalState(scheduleId);

  @override
  Future<List<ScheduleAlternative>> getScheduleAlternatives(int scheduleId) =>
      _apiService.getScheduleAlternatives(scheduleId);

  @override
  Future<ApprovalRequestSummary> requestPmSkip(
    int scheduleId, {
    required String reasonCode,
    required String remarks,
  }) =>
      _apiService.requestPmSkip(
        scheduleId,
        reasonCode: reasonCode,
        remarks: remarks,
      );

  @override
  Future<ApprovalRequestSummary> requestChecklistChange(
    int scheduleId, {
    required int maintenanceMasterId,
    required String remarks,
  }) =>
      _apiService.requestChecklistChange(
        scheduleId,
        maintenanceMasterId: maintenanceMasterId,
        remarks: remarks,
      );

  @override
  Future<int> startExecution(int workOrderId) async {
    // Key is created BEFORE the first attempt and reused for the queued
    // command, so a request that reached the server but timed out client-side
    // is deduplicated on replay. (If an existing pending duplicate is kept by
    // enqueueDeduped, that older command's key is used instead - acceptable.)
    final idempotencyKey =
        'start_exec_${workOrderId}_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final recordId = await _apiService.startExecution(
        workOrderId,
        idempotencyKey: idempotencyKey,
      );
      return recordId;
    } catch (e) {
      if (_isNetworkException(e) && _syncManager != null) {
        // Queue the mutation so execution starts server-side once back
        // online, but do NOT hand back a fabricated record id — the server
        // hasn't created the MaintenanceRecord yet, so a work-order id
        // pretending to be one would send the caller to ChecklistScreen
        // against the wrong entity (`/records/{workOrderId}/`, not a real
        // record). Throw a distinct, recognizable exception instead so the
        // caller can tell "queued for later" apart from a genuine failure
        // and skip navigation rather than guess an id.
        final cmd = OutboxCommand(
          idempotencyKey: idempotencyKey,
          type: OutboxCommandType.startExecution,
          entityId: workOrderId,
          payload: const {},
          createdAt: DateTime.now(),
        );
        await _enqueueDeduped(cmd);
        throw const StartExecutionQueuedOffline();
      }
      rethrow;
    }
  }

  @override
  Future<WorkOrder> transitionStatus(
    int workOrderId, {
    required String status,
    String? remarks,
    Map<String, dynamic>? checklist,
    List<int>? evidence,
  }) async {
    // Key is created BEFORE the first attempt and reused for the queued
    // command, so a request that reached the server but timed out client-side
    // is deduplicated on replay. (If an existing pending duplicate is kept by
    // enqueueDeduped, that older command's key is used instead - acceptable.)
    final idempotencyKey =
        'trans_${workOrderId}_${status}_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final order = await _apiService.changeStatus(
        workOrderId,
        status: status,
        remarks: remarks,
        checklist: checklist,
        evidence: evidence,
        idempotencyKey: idempotencyKey,
      );
      await _cacheService.cacheWorkOrderDetail(order);
      return order;
    } catch (e) {
      if (_isNetworkException(e) && _syncManager != null) {
        final normalized = status.trim().toUpperCase();
        if (normalized == 'VERIFIED' || normalized == 'CLOSED') {
          throw const OnlineRequiredException(
            'Verification and closure require a live connection. Connect to the network and try again.',
          );
        }
        final cmd = OutboxCommand(
          idempotencyKey: idempotencyKey,
          type: OutboxCommandType.transitionStatus,
          entityId: workOrderId,
          payload: {
            'status': status,
            if (status == 'TECH_COMPLETED')
              'device_completed_at': DateTime.now().toIso8601String(),
            if (remarks != null) 'remarks': remarks,
            if (checklist != null) 'checklist': checklist,
            if (evidence != null) 'evidence': evidence,
          },
          createdAt: DateTime.now(),
        );
        await _enqueueDeduped(cmd,
            matches: (c) => c.payload['status'] == status);

        // Optimistic update in cache. `remarks` is the transition note, not
        // the work order's description — copyWith'ing it into `description`
        // overwrote the real description with e.g. a rework reason.
        final cached =
            await _cacheService.getCachedWorkOrderDetail(workOrderId);
        if (cached != null) {
          final updated = cached.copyWith(
            status: WorkOrderStatus.fromString(status),
            reportCompletedAt: status == 'TECH_COMPLETED'
                ? DateTime.now()
                : cached.reportCompletedAt,
          );
          await _cacheService.cacheWorkOrderDetail(updated);
          return updated;
        }
      }
      rethrow;
    }
  }

  @override
  Future<MaintenanceRecord> fetchMaintenanceRecord(int recordId) async {
    MaintenanceRecord record;
    try {
      record = await _apiService.getMaintenanceRecord(recordId);
      await _cacheService.cacheMaintenanceRecord(record);
    } catch (e) {
      if (_isNetworkException(e)) {
        final cached = await _cacheService.getCachedMaintenanceRecord(recordId);
        if (cached != null) return _overlayQueuedLines(cached);
      }
      rethrow;
    }
    return _overlayQueuedLines(record);
  }

  /// The cache remains server truth. Outstanding assignments are a read-time
  /// overlay, reconstructed from the existing queue even after a restart.
  Future<MaintenanceRecord> _overlayQueuedLines(
      MaintenanceRecord record) async {
    final owner = await _cacheService.getCacheOwnerUserId();
    if (owner == null) return record;
    final commands = await _cacheService.getOutboxCommands();
    // Ownership may change while storage is being read.
    if (await _cacheService.getCacheOwnerUserId() != owner) return record;
    final latestByLine = <int, OutboxCommand>{};
    for (final command in commands) {
      if (command.ownerUserId != owner ||
          command.entityId != record.id ||
          command.type != OutboxCommandType.submitLine ||
          command.status == OutboxCommandStatus.synced ||
          command.status == OutboxCommandStatus.draft) {
        continue;
      }
      final lineId = int.tryParse('${command.payload['line_id']}');
      if (lineId != null) latestByLine[lineId] = command;
    }
    return record.copyWith(
        lines: record.lines.map((line) {
      final queued = latestByLine[line.id];
      if (queued == null) return line;
      final payload = queued.payload;
      var updated = line.copyWith(localSyncStatus: queued.status);
      if (payload.containsKey('value')) {
        updated = updated.copyWith(recordedValue: payload['value']);
      }
      if (payload['status'] is String) {
        updated = updated.copyWith(status: payload['status'] as String);
      }
      if (payload.containsKey('status_option')) {
        updated = updated.copyWith(
            statusOptionId: int.tryParse('${payload['status_option']}'));
      }
      if (payload.containsKey('action_option')) {
        updated = updated.copyWith(
            actionOptionId: int.tryParse('${payload['action_option']}'));
      }
      if (payload.containsKey('remarks')) {
        updated = updated.copyWith(observationAction: payload['remarks']);
      }
      return updated;
    }).toList());
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMaintenanceRecords({
    int? workOrderId,
    int? scheduleId,
  }) {
    // Report resolution is online-only (like the Register export itself):
    // a stale cached record must never render as a signed report.
    return _apiService.fetchMaintenanceRecords(
      workOrderId: workOrderId,
      scheduleId: scheduleId,
    );
  }

  @override
  Future<MutationOutcome> submitChecklistLine(
      int recordId, Map<String, dynamic> lineData) {
    // Keep autosaves in invocation order even if network attempts complete
    // out of order. A failed save must not block subsequent edits.
    final payload = Map<String, dynamic>.from(lineData);
    final save =
        _lineSaves.then((_) => _submitChecklistLine(recordId, payload));
    _lineSaves = save.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return save;
  }

  Future<MutationOutcome> _submitChecklistLine(
      int recordId, Map<String, dynamic> lineData) async {
    final lineId = lineData['line_id'] ?? 0;
    // Key is created BEFORE the first attempt and reused for the queued
    // command, so a request that reached the server but timed out client-side
    // can reuse its identity on retry. Backend deduplication is a separate
    // requirement; a newer assignment receives its own key and payload.
    final idempotencyKey =
        'line_${recordId}_${lineId}_${DateTime.now().microsecondsSinceEpoch}';
    final owner = await _cacheService.getCacheOwnerUserId();
    final outstanding = await _cacheService.getOutboxCommands();
    // Do not send a newer value directly while an older queued assignment
    // could subsequently replay over it when connectivity returns.
    if (_syncManager != null &&
        outstanding.any((c) =>
            c.ownerUserId == owner &&
            c.type == OutboxCommandType.submitLine &&
            c.entityId == recordId &&
            c.payload['line_id'] == lineId &&
            c.status == OutboxCommandStatus.pending)) {
      await _enqueueDeduped(
          OutboxCommand(
            idempotencyKey: idempotencyKey,
            type: OutboxCommandType.submitLine,
            entityId: recordId,
            payload: lineData,
            createdAt: DateTime.now(),
          ),
          matches: (c) => c.payload['line_id'] == lineId);
      return MutationOutcome.queued;
    }
    try {
      await _apiService.submitLine(recordId, lineData,
          idempotencyKey: idempotencyKey);
      return MutationOutcome.synced;
    } catch (e) {
      if (_isNetworkException(e) && _syncManager != null) {
        final cmd = OutboxCommand(
          idempotencyKey: idempotencyKey,
          type: OutboxCommandType.submitLine,
          entityId: recordId,
          payload: lineData,
          createdAt: DateTime.now(),
        );
        await _enqueueDeduped(cmd,
            matches: (c) => c.payload['line_id'] == lineId);
        return MutationOutcome.queued;
      }
      rethrow;
    }
  }

  @override

  /// Uploads proof of execution, queueing it when offline.
  ///
  /// The queued command keeps the file path rather than the bytes: the photo
  /// already lives in the app's documents directory, so the outbox stays small
  /// and the image survives until the upload succeeds.
  @override
  Future<MutationOutcome> uploadEvidence(
    int recordId, {
    String? proofJpegPath,
    String? remarks,
    String? otherStaff,
  }) async {
    // Key is created BEFORE the first attempt and reused for the queued
    // command, so a request that reached the server but timed out client-side
    // is deduplicated on replay. (If an existing pending duplicate is kept by
    // enqueueDeduped, that older command's key is used instead - acceptable.)
    final idempotencyKey =
        'evidence_${recordId}_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await _apiService.uploadRecordEvidence(
        recordId,
        proofJpegPath: proofJpegPath,
        remarks: remarks,
        otherStaff: otherStaff,
        idempotencyKey: idempotencyKey,
      );
      return MutationOutcome.synced;
    } catch (e) {
      if (_isNetworkException(e) && _syncManager != null) {
        await _enqueueDeduped(
            OutboxCommand(
              idempotencyKey: idempotencyKey,
              type: OutboxCommandType.uploadEvidence,
              entityId: recordId,
              payload: {
                if (proofJpegPath != null) 'proof_path': proofJpegPath,
                if (remarks != null) 'remarks': remarks,
                if (otherStaff != null) 'other_staff': otherStaff,
              },
              createdAt: DateTime.now(),
            ), matches: (c) {
          // H6: match on proof_path only when caller sent one. When no
          // photo was attached, `null == null` would treat a *different*
          // no-photo submission (different remarks/staff) as a duplicate
          // and silently drop it — compare the other fields instead.
          if (proofJpegPath != null) {
            return c.payload['proof_path'] == proofJpegPath;
          }
          final existingProof = c.payload['proof_path'];
          if (existingProof is String && existingProof.isNotEmpty) {
            return false;
          }
          return c.payload['remarks'] == remarks &&
              c.payload['other_staff'] == otherStaff;
        });
        return MutationOutcome.queued;
      }
      rethrow;
    }
  }

  @override
  Future<MutationOutcome> completeMaintenanceRecord(
    int recordId, {
    required String technicianName,
    required String remarks,
    String? supervisorName,
    bool queueOnly = false,
  }) async {
    final syncManager = _syncManager;
    // Key is created BEFORE the first attempt and reused for the queued
    // command, so a request that reached the server but timed out client-side
    // is deduplicated on replay. (If an existing pending duplicate is kept by
    // enqueueDeduped, that older command's key is used instead - acceptable.)
    final idempotencyKey =
        'complete_${recordId}_${DateTime.now().millisecondsSinceEpoch}';
    Future<MutationOutcome> enqueue(SyncManager sync) async {
      await _enqueueDeduped(OutboxCommand(
        idempotencyKey: idempotencyKey,
        type: OutboxCommandType.completeRecord,
        entityId: recordId,
        payload: {
          'technician_name': technicianName,
          'remarks': remarks,
          if (supervisorName != null) 'supervisor_name': supervisorName,
        },
        createdAt: DateTime.now(),
      ));
      return MutationOutcome.queued;
    }

    if (queueOnly && syncManager != null) return enqueue(syncManager);
    try {
      await _apiService.completeRecord(
        recordId,
        technicianName: technicianName,
        remarks: remarks,
        supervisorName: supervisorName,
        idempotencyKey: idempotencyKey,
      );
      return MutationOutcome.synced;
    } catch (e) {
      if (_isNetworkException(e) && syncManager != null) {
        return enqueue(syncManager);
      }
      rethrow;
    }
  }

  @override
  Future<LineAttachment> uploadLineAttachment(
    int recordId, {
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
    final idempotencyKey =
        'line_att_${recordId}_${lineId}_${DateTime.now().millisecondsSinceEpoch}';
    // Capture the provenance ONCE, here. The outbox payload is frozen with
    // these exact values, so an offline retry never re-derives source,
    // captured_at or a replacement GPS fix (audit §9.2 ME-02/ME-04).
    final resolvedSource = (source ?? 'UNKNOWN').toUpperCase();
    try {
      final data = await _apiService.uploadLineAttachment(
        recordId,
        lineId: lineId,
        kind: kind,
        imagePath: imagePath,
        capturedAt: capturedAt,
        source: resolvedSource,
        latitude: latitude,
        longitude: longitude,
        locationAccuracyM: locationAccuracyM,
        locationRecordedAt: locationRecordedAt,
        idempotencyKey: idempotencyKey,
      );
      return LineAttachment.fromJson(data);
    } catch (e) {
      if (_isNetworkException(e) && _syncManager != null) {
        final cmd = OutboxCommand(
          idempotencyKey: idempotencyKey,
          type: OutboxCommandType.uploadLineAttachment,
          entityId: recordId,
          payload: {
            'line_id': lineId,
            'kind': kind,
            'file_path': imagePath,
            // Frozen provenance — replayed verbatim by SyncManager.
            'source': resolvedSource,
            if (capturedAt != null) 'captured_at': capturedAt.toIso8601String(),
            if (latitude != null &&
                longitude != null &&
                locationAccuracyM != null &&
                locationRecordedAt != null) ...{
              'latitude': latitude,
              'longitude': longitude,
              'location_accuracy_m': locationAccuracyM,
              'location_recorded_at': locationRecordedAt.toIso8601String(),
            },
          },
          createdAt: DateTime.now(),
        );
        await _enqueueDeduped(cmd,
            matches: (c) =>
                c.payload['line_id'] == lineId &&
                c.payload['kind'] == kind &&
                c.payload['file_path'] == imagePath);

        return LineAttachment(
          id: -DateTime.now().millisecondsSinceEpoch,
          kind: kind.toUpperCase(),
          source: resolvedSource,
          localPath: imagePath,
          capturedAt: capturedAt,
          syncStatus: OutboxCommandStatus.pending,
          idempotencyKey: idempotencyKey,
          latitude: latitude,
          longitude: longitude,
          locationAccuracyM: locationAccuracyM,
          locationRecordedAt: locationRecordedAt,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteLineAttachment(
    int recordId, {
    required int lineId,
    required int attachmentId,
  }) async {
    await _apiService.deleteLineAttachment(
      recordId,
      lineId: lineId,
      attachmentId: attachmentId,
    );
  }
}
