import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gssms_mobile/core/network/paginated_fetch.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/technician.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';

/// REST calls for work orders and maintenance execution.
///
/// Paths follow the Django URL configuration: the maintenance app is mounted
/// under `/api/v1/maintenance/`, while the technician-scoped work order views
/// live under `/api/v1/staff-workorders/`. Detail actions use the slug Django
/// registered — note `submit_line` keeps its underscore, unlike the explicitly
/// hyphenated `change-status` and `allowed-actions`.
class WorkOrderApiService {
  WorkOrderApiService(this._dio);

  final Dio _dio;

  static const String _workOrders = '/api/v1/maintenance/work-orders';
  static const String _records = '/api/v1/maintenance/records';
  static const String _staffWorkOrders = '/api/v1/staff-workorders';

  Map<String, dynamic>? _asObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    return const [];
  }

  /// Work orders visible to the caller.
  ///
  /// [assignedToMe] uses the staff-scoped endpoint, which returns only the
  /// technician's own work — the mobile equivalent of the web "My Work Orders".
  Future<List<WorkOrder>> getWorkOrders({
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
    final queryParams = <String, dynamic>{};
    if (status != null && status.isNotEmpty) queryParams['status'] = status;
    if (type != null && type.isNotEmpty) queryParams['type'] = type;
    if (dateFrom != null && dateFrom.isNotEmpty) queryParams['date_from'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) queryParams['date_to'] = dateTo;
    // depot_id/division_id/zone_id are mutually exclusive server-side (most
    // specific wins — WorkOrderViewSet.get_queryset), so sending all three
    // that are set is harmless; the server picks the narrowest.
    if (zoneId != null) queryParams['zone_id'] = zoneId;
    if (divisionId != null) queryParams['division_id'] = divisionId;
    if (depotId != null) queryParams['depot_id'] = depotId;
    if (stationId != null) queryParams['station_id'] = stationId;

    // Walk `next` links like the other CMMS lists so a paginated register is
    // not silently truncated to page 1. Single-shot envelopes still work:
    // fetchAllPages handles both `{results:[...]}` and bare lists.
    final page = await fetchAllPages(
      _dio,
      assignedToMe ? '$_staffWorkOrders/' : '$_workOrders/',
      queryParameters: queryParams,
    );
    return page.items
        .whereType<Map>()
        .map((e) => WorkOrder.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<WorkOrder> getWorkOrder(int id) async {
    final response = await _dio.get('$_workOrders/$id/');
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected work-order payload',
      );
    }
    return WorkOrder.fromJson(data);
  }

  /// Transitions the server currently permits for this work order.
  Future<WorkOrderActionSet> getAllowedActions(int workOrderId) async {
    final response = await _dio.get('$_workOrders/$workOrderId/allowed-actions/');
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected allowed-actions payload',
      );
    }
    return WorkOrderActionSet.fromJson(data);
  }

  /// Full status history for the work order.
  Future<WorkOrderAudit> getAudit(int workOrderId) async {
    final response = await _dio.get('$_workOrders/$workOrderId/audit/');
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected audit payload',
      );
    }
    return WorkOrderAudit.fromJson(data);
  }

  /// Depot-scoped maintenance staff the caller may assign (server filters by role).
  ///
  /// [depotId] pins the result to the work order's own depot. Without it the
  /// server falls back to ScopeService's implicit scoping of the *caller*,
  /// which is wrong whenever the caller's own scope (e.g. a division/zone
  /// admin, or a user whose primary depot differs) doesn't line up with the
  /// depot the work order actually belongs to — the technician list then
  /// comes back empty even though staff exist at that depot.
  Future<List<Technician>> getAssignableTechnicians({int? depotId}) async {
    final response = await _dio.get(
      '/api/v1/users/',
      queryParameters: {
        'role': 'MAINTENANCE_STAFF',
        if (depotId != null) 'depot': depotId,
      },
    );
    return _asList(response.data)
        .whereType<Map>()
        .map((e) => Technician.fromJson(Map<String, dynamic>.from(e)))
        .where((t) => t.id > 0)
        .toList();
  }

  /// Sets `assigned_to` on the work order. Must succeed before NEW → ASSIGNED.
  Future<WorkOrder> assignTechnician(int workOrderId, int technicianId) async {
    final response = await _dio.patch(
      '$_workOrders/$workOrderId/',
      data: {'assigned_to': technicianId},
    );
    final data = response.data;
    if (data is Map<String, dynamic> && data['id'] != null) {
      return WorkOrder.fromJson(data);
    }
    return getWorkOrder(workOrderId);
  }

  /// Supervisor verify. The generic change-status path does not write `verified_by`.
  Future<WorkOrder> verifyWorkOrder(
    int workOrderId, {
    String? remarks,
  }) async {
    final payload = <String, dynamic>{};
    if (remarks != null && remarks.isNotEmpty) payload['remarks'] = remarks;

    final response = await _dio.post(
      '$_workOrders/$workOrderId/verify/',
      data: payload,
    );
    final data = response.data;
    if (data is Map<String, dynamic> && data['id'] != null) {
      return WorkOrder.fromJson(data);
    }
    return getWorkOrder(workOrderId);
  }

  Future<VerificationWorkspace> getVerificationWorkspace(int workOrderId) async {
    final response =
        await _dio.get('$_workOrders/$workOrderId/verification-workspace/');
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected verification-workspace payload',
      );
    }
    return VerificationWorkspace.fromJson(data);
  }

  /// Starts execution and returns the maintenance record id to open.
  Future<int> startExecution(int workOrderId, {String? idempotencyKey}) async {
    final response = await _dio.post(
      '$_staffWorkOrders/$workOrderId/execute/',
      options: idempotencyKey != null
          ? Options(headers: {'X-Idempotency-Key': idempotencyKey, 'Idempotency-Key': idempotencyKey})
          : null,
    );
    final data = response.data;
    if (data is Map) {
      final record = data['record'];
      final recordId = asJsonInt(data['record_id']) ??
          asJsonInt(data['id']) ??
          (record is Map ? asJsonInt(record['id']) : null);
      if (recordId != null) return recordId;
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      message: 'Failed to obtain maintenance record id from execute endpoint.',
    );
  }

  Future<WorkOrder> changeStatus(
    int workOrderId, {
    required String status,
    String? remarks,
    Map<String, dynamic>? checklist,
    List<int>? evidence,
    String? idempotencyKey,
  }) async {
    final payload = <String, dynamic>{'status': status};
    if (remarks != null && remarks.isNotEmpty) payload['remarks'] = remarks;
    if (checklist != null) payload['checklist'] = checklist;
    if (evidence != null) payload['evidence'] = evidence;

    final response = await _dio.post(
      '$_workOrders/$workOrderId/change-status/',
      data: payload,
      options: idempotencyKey != null
          ? Options(headers: {'X-Idempotency-Key': idempotencyKey, 'Idempotency-Key': idempotencyKey})
          : null,
    );

    final data = response.data;
    if (data is Map<String, dynamic> && data['id'] != null) {
      return WorkOrder.fromJson(data);
    }
    // Some transitions return only a status envelope; re-read the work order so
    // callers always get the authoritative post-transition state.
    return getWorkOrder(workOrderId);
  }

  Future<MaintenanceRecord> getMaintenanceRecord(int recordId) async {
    final response = await _dio.get('$_records/$recordId/');
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected maintenance-record payload',
      );
    }
    return MaintenanceRecord.fromJson(data);
  }

  Future<void> submitLine(int recordId, Map<String, dynamic> lineData, {String? idempotencyKey}) async {
    await _dio.post(
      '$_records/$recordId/submit_line/',
      data: lineData,
      options: idempotencyKey != null
          ? Options(headers: {'X-Idempotency-Key': idempotencyKey, 'Idempotency-Key': idempotencyKey})
          : null,
    );
  }

  /// Attaches proof of execution and closing notes to the record.
  ///
  /// Mirrors the web client: a multipart PATCH on the record itself, with the
  /// photo under `proof_of_execution_upload`. The server accepts JPEG only, up
  /// to 5 MB.
  Future<void> uploadRecordEvidence(
    int recordId, {
    String? proofJpegPath,
    String? remarks,
    String? otherStaff,
    String? idempotencyKey,
  }) async {
    if (proofJpegPath != null) {
      final file = File(proofJpegPath);
      if (!await file.exists()) {
        throw ArgumentError('Proof photo not found at $proofJpegPath');
      }
      if (await file.length() > 5 * 1024 * 1024) {
        throw ArgumentError('Proof photo exceeds the 5 MB server limit');
      }
    }
    final form = FormData.fromMap({
      if (remarks != null) 'remarks': remarks,
      if (otherStaff != null) 'other_staff': otherStaff,
      if (proofJpegPath != null)
        'proof_of_execution_upload': await MultipartFile.fromFile(
          proofJpegPath,
          filename: 'proof_of_execution.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
    });

    await _dio.patch(
      '$_records/$recordId/',
      data: form,
      options: idempotencyKey != null
          ? Options(headers: {'X-Idempotency-Key': idempotencyKey, 'Idempotency-Key': idempotencyKey})
          : null,
    );
  }

  /// Finalises the record.
  ///
  /// The server only writes a signature row when `technician_signature` is
  /// present, and the lifecycle rejects the resulting TECH_COMPLETED transition
  /// unless `remarks` is at least 10 characters, so both are required here.
  Future<void> completeRecord(
    int recordId, {
    required String technicianName,
    required String remarks,
    String technicianSignature = 'SIGNED_DIGITALLY',
    String? supervisorName,
    String? supervisorSignature,
    String? idempotencyKey,
  }) async {
    if (remarks.trim().length < 10) {
      throw ArgumentError('Closing remarks must be at least 10 characters');
    }
    await _dio.post(
      '$_records/$recordId/complete/',
      data: {
        'technician_name': technicianName,
        'technician_signature': technicianSignature,
        'remarks': remarks,
        if (supervisorName != null) 'supervisor_name': supervisorName,
        if (supervisorSignature != null) 'supervisor_signature': supervisorSignature,
      },
      options: idempotencyKey != null
          ? Options(headers: {'X-Idempotency-Key': idempotencyKey, 'Idempotency-Key': idempotencyKey})
          : null,
    );
  }
}
