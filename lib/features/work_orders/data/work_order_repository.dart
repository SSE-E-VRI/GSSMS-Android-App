import 'package:dio/dio.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';

abstract class IWorkOrderRepository {
  Future<List<WorkOrder>> fetchWorkOrders({
    String? status,
    String? type,
    String? dateFrom,
    String? dateTo,
  });

  Future<WorkOrder> fetchWorkOrderById(int id);
  Future<WorkOrderActionSet> fetchAllowedActions(int workOrderId);
  Future<WorkOrderAudit> fetchAudit(int workOrderId);
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
      return e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
    }
    return false;
  }

  @override
  Future<List<WorkOrder>> fetchWorkOrders({
    String? status,
    String? type,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final orders = await _apiService.getWorkOrders(
        status: status,
        type: type,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      await _cacheService.cacheWorkOrders(orders);
      return orders;
    } catch (e) {
      if (_isNetworkException(e)) {
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
  Future<int> startExecution(int workOrderId) async {
    try {
      final recordId = await _apiService.startExecution(workOrderId);
      return recordId;
    } catch (e) {
      if (_isNetworkException(e) && _syncManager != null) {
        // Enqueue offline start execution mutation
        final cmd = OutboxCommand(
          idempotencyKey: 'start_exec_${workOrderId}_${DateTime.now().millisecondsSinceEpoch}',
          type: OutboxCommandType.startExecution,
          entityId: workOrderId,
          payload: const {},
          createdAt: DateTime.now(),
        );
        await _syncManager.enqueueCommand(cmd);
        return workOrderId; // Fallback to work order ID as temporary record ID
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

        // Optimistic update in cache
        final cached = await _cacheService.getCachedWorkOrderDetail(workOrderId);
        if (cached != null) {
          final updated = cached.copyWith(
            status: WorkOrderStatus.fromString(status),
            description: remarks,
            reportCompletedAt:
                status == 'TECH_COMPLETED' ? DateTime.now() : null,
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
}
