import 'package:dio/dio.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
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
    int? depotId,
    int? stationId,
    bool assignedToMe = false,
  }) async {
    final queryParams = <String, dynamic>{};
    if (status != null && status.isNotEmpty) queryParams['status'] = status;
    if (type != null && type.isNotEmpty) queryParams['type'] = type;
    if (dateFrom != null && dateFrom.isNotEmpty) queryParams['date_from'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) queryParams['date_to'] = dateTo;
    if (depotId != null) queryParams['depot_id'] = depotId;
    if (stationId != null) queryParams['station_id'] = stationId;

    final response = await _dio.get(
      assignedToMe ? '$_staffWorkOrders/' : '$_workOrders/',
      queryParameters: queryParams,
    );

    return _asList(response.data)
        .whereType<Map<String, dynamic>>()
        .map(WorkOrder.fromJson)
        .toList();
  }

  Future<WorkOrder> getWorkOrder(int id) async {
    final response = await _dio.get('$_workOrders/$id/');
    return WorkOrder.fromJson(response.data as Map<String, dynamic>);
  }

  /// Transitions the server currently permits for this work order.
  Future<WorkOrderActionSet> getAllowedActions(int workOrderId) async {
    final response = await _dio.get('$_workOrders/$workOrderId/allowed-actions/');
    return WorkOrderActionSet.fromJson(response.data as Map<String, dynamic>);
  }

  /// Full status history for the work order.
  Future<WorkOrderAudit> getAudit(int workOrderId) async {
    final response = await _dio.get('$_workOrders/$workOrderId/audit/');
    return WorkOrderAudit.fromJson(response.data as Map<String, dynamic>);
  }

  /// Starts execution and returns the maintenance record id to open.
  Future<int> startExecution(int workOrderId) async {
    final response = await _dio.post('$_staffWorkOrders/$workOrderId/execute/');
    final data = response.data;
    if (data is Map && data['record_id'] != null) {
      return data['record_id'] as int;
    }
    throw Exception('Failed to obtain maintenance record id from execute endpoint.');
  }

  Future<WorkOrder> changeStatus(
    int workOrderId, {
    required String status,
    String? remarks,
    Map<String, dynamic>? checklist,
    List<int>? evidence,
    int? failureCodeId,
  }) async {
    final payload = <String, dynamic>{'status': status};
    if (remarks != null && remarks.isNotEmpty) payload['remarks'] = remarks;
    if (checklist != null) payload['checklist'] = checklist;
    if (evidence != null) payload['evidence'] = evidence;
    if (failureCodeId != null) payload['failure_code'] = failureCodeId;

    final response = await _dio.post(
      '$_workOrders/$workOrderId/change-status/',
      data: payload,
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
    return MaintenanceRecord.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> submitLine(int recordId, Map<String, dynamic> lineData) async {
    await _dio.post('$_records/$recordId/submit_line/', data: lineData);
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
  }) async {
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

    await _dio.patch('$_records/$recordId/', data: form);
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
  }) async {
    await _dio.post('$_records/$recordId/complete/', data: {
      'technician_name': technicianName,
      'technician_signature': technicianSignature,
      'remarks': remarks,
      if (supervisorName != null) 'supervisor_name': supervisorName,
      if (supervisorSignature != null) 'supervisor_signature': supervisorSignature,
    });
  }
}
