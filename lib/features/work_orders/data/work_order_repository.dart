import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
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
    int? zoneId,
    int? divisionId,
    int? depotId,
    int? stationId,
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
    String? dueDate,
  });
  Future<WorkOrderActionSet> fetchAllowedActions(int workOrderId);
  Future<WorkOrderAudit> fetchAudit(int workOrderId);
  Future<List<Technician>> fetchAssignableTechnicians({int? depotId});
  Future<WorkOrder> assignTechnician(int workOrderId, int technicianId);
  Future<WorkOrder> verifyWorkOrder(int workOrderId, {String? remarks});
  Future<VerificationWorkspace> fetchVerificationWorkspace(int workOrderId);
  Future<int> startExecution(int workOrderId);
  Future<WorkOrder> transitionStatus(
    int workOrderId, {
    required String status,
    String? remarks,
    Map<String, dynamic>? checklist,
    List<int>? evidence,
  });

  Future<MaintenanceRecord> fetchMaintenanceRecord(int recordId);
  Future<void> submitChecklistLine(int recordId, Map<String, dynamic> lineData);

  Future<void> uploadEvidence(
    int recordId, {
    String? proofJpegPath,
    String? remarks,
    String? otherStaff,
  });

  Future<void> completeMaintenanceRecord(
    int recordId, {
    required String technicianName,
    required String remarks,
    String? supervisorName,
  });

  Future<LineAttachment> uploadLineAttachment(
    int recordId, {
    required int lineId,
    required String kind,
    required String imagePath,
    DateTime? capturedAt,
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

  @override
  Future<List<WorkOrder>> fetchWorkOrders({
    String? status,
    String? type,
    String? dateFrom,
    String? dateTo,
    int? zoneId,
    int? divisionId,
    int? depotId,
    int? stationId,
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
        zoneId != null ||
        divisionId != null ||
        depotId != null ||
        stationId != null ||
        assignedToMe;
    try {
      final orders = await _apiService.getWorkOrders(
        status: status,
        type: type,
        dateFrom: dateFrom,
        dateTo: dateTo,
        zoneId: zoneId,
        divisionId: divisionId,
        depotId: depotId,
        stationId: stationId,
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
    String? dueDate,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      'type': type,
      'priority': priority,
      'source': 'MOBILE',
      if (depotId != null) 'depot': depotId,
      if (stationId != null) 'station': stationId,
      if (infrastructureId != null) 'infrastructure': infrastructureId,
      if (assetId != null) 'asset': assetId,
      if (dueDate != null) 'due_date': dueDate,
    };
    final order = await _apiService.createWorkOrder(payload);
    await _cacheService.cacheWorkOrderDetail(order);
    return order;
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
    final order = await _apiService.verifyWorkOrder(workOrderId, remarks: remarks);
    await _cacheService.cacheWorkOrderDetail(order);
    return order;
  }

  @override
  Future<VerificationWorkspace> fetchVerificationWorkspace(int workOrderId) {
    return _apiService.getVerificationWorkspace(workOrderId);
  }

  @override
  Future<int> startExecution(int workOrderId) async {
    try {
      final recordId = await _apiService.startExecution(workOrderId);
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
          idempotencyKey: 'start_exec_${workOrderId}_${DateTime.now().millisecondsSinceEpoch}',
          type: OutboxCommandType.startExecution,
          entityId: workOrderId,
          payload: const {},
          createdAt: DateTime.now(),
        );
        await _syncManager.enqueueCommand(cmd);
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
    try {
      final order = await _apiService.changeStatus(
        workOrderId,
        status: status,
        remarks: remarks,
        checklist: checklist,
        evidence: evidence,
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
          idempotencyKey: 'trans_${workOrderId}_${status}_${DateTime.now().millisecondsSinceEpoch}',
          type: OutboxCommandType.transitionStatus,
          entityId: workOrderId,
          payload: {
            'status': status,
            if (remarks != null) 'remarks': remarks,
            if (checklist != null) 'checklist': checklist,
            if (evidence != null) 'evidence': evidence,
          },
          createdAt: DateTime.now(),
        );
        await _syncManager.enqueueCommand(cmd);

        // Optimistic update in cache. `remarks` is the transition note, not
        // the work order's description — copyWith'ing it into `description`
        // overwrote the real description with e.g. a rework reason.
        final cached = await _cacheService.getCachedWorkOrderDetail(workOrderId);
        if (cached != null) {
          final updated = cached.copyWith(
            status: WorkOrderStatus.fromString(status),
            reportCompletedAt:
                status == 'TECH_COMPLETED' ? DateTime.now() : cached.reportCompletedAt,
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
    try {
      final record = await _apiService.getMaintenanceRecord(recordId);
      await _cacheService.cacheMaintenanceRecord(record);
      return record;
    } catch (e) {
      if (_isNetworkException(e)) {
        final cached = await _cacheService.getCachedMaintenanceRecord(recordId);
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  @override
  Future<void> submitChecklistLine(int recordId, Map<String, dynamic> lineData) async {
    try {
      await _apiService.submitLine(recordId, lineData);
    } catch (e) {
      if (_isNetworkException(e) && _syncManager != null) {
        final lineId = lineData['line_id'] ?? 0;
        final cmd = OutboxCommand(
          idempotencyKey: 'line_${recordId}_${lineId}_${DateTime.now().millisecondsSinceEpoch}',
          type: OutboxCommandType.submitLine,
          entityId: recordId,
          payload: lineData,
          createdAt: DateTime.now(),
        );
        await _syncManager.enqueueCommand(cmd);
        return;
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
  Future<void> uploadEvidence(
    int recordId, {
    String? proofJpegPath,
    String? remarks,
    String? otherStaff,
  }) async {
    try {
      await _apiService.uploadRecordEvidence(
        recordId,
        proofJpegPath: proofJpegPath,
        remarks: remarks,
        otherStaff: otherStaff,
      );
    } catch (e) {
      if (_isNetworkException(e) && _syncManager != null) {
        await _syncManager.enqueueCommand(OutboxCommand(
          idempotencyKey: 'evidence_${recordId}_${DateTime.now().millisecondsSinceEpoch}',
          type: OutboxCommandType.uploadEvidence,
          entityId: recordId,
          payload: {
            if (proofJpegPath != null) 'proof_path': proofJpegPath,
            if (remarks != null) 'remarks': remarks,
            if (otherStaff != null) 'other_staff': otherStaff,
          },
          createdAt: DateTime.now(),
        ));
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> completeMaintenanceRecord(
    int recordId, {
    required String technicianName,
    required String remarks,
    String? supervisorName,
  }) async {
    try {
      await _apiService.completeRecord(
        recordId,
        technicianName: technicianName,
        remarks: remarks,
        supervisorName: supervisorName,
      );
    } catch (e) {
      if (_isNetworkException(e) && _syncManager != null) {
        await _syncManager.enqueueCommand(OutboxCommand(
          idempotencyKey: 'complete_${recordId}_${DateTime.now().millisecondsSinceEpoch}',
          type: OutboxCommandType.completeRecord,
          entityId: recordId,
          payload: {
            'technician_name': technicianName,
            'remarks': remarks,
            if (supervisorName != null) 'supervisor_name': supervisorName,
          },
          createdAt: DateTime.now(),
        ));
        return;
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
  }) async {
    final idempotencyKey =
        'line_att_${recordId}_${lineId}_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final data = await _apiService.uploadLineAttachment(
        recordId,
        lineId: lineId,
        kind: kind,
        imagePath: imagePath,
        capturedAt: capturedAt,
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
            if (capturedAt != null) 'captured_at': capturedAt.toIso8601String(),
          },
          createdAt: DateTime.now(),
        );
        await _syncManager.enqueueCommand(cmd);

        return LineAttachment(
          id: -DateTime.now().millisecondsSinceEpoch,
          kind: kind.toUpperCase(),
          localPath: imagePath,
          capturedAt: capturedAt ?? DateTime.now(),
          syncStatus: OutboxCommandStatus.pending,
          idempotencyKey: idempotencyKey,
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
