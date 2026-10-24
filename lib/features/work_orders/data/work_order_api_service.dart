import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gssms_mobile/core/network/paginated_fetch.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';
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

  /// Multipart photo uploads override the 15s global Dio timeouts.
  static const Duration _uploadTimeout = Duration(seconds: 120);

  static const String _workOrders = '/api/v1/maintenance/work-orders';
  static const String _records = '/api/v1/maintenance/records';
  static const String _staffWorkOrders = '/api/v1/staff-workorders';
  static const String _masters = '/api/v1/maintenance/masters';
  static const String _schedules = '/api/v1/maintenance/schedules';

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
  /// [status] accepts a single value or a comma-separated list (backend
  /// `status__in`). [completionFrom]/[completionTo] filter the
  /// `report_completed_at` range (web Register query); [updatedFrom]/
  /// [updatedTo] filter `updated_at`. Infra id params mirror
  /// `filter_legacy_infrastructure_params` (`station_id`, `lc_gate_id`,
  /// `service_building_id`, `staff_quarter_id`) plus the `infra_type`
  /// fallback web sends.
  Future<List<WorkOrder>> getWorkOrders({
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
    final queryParams = <String, dynamic>{};
    if (status != null && status.isNotEmpty) queryParams['status'] = status;
    if (type != null && type.isNotEmpty) queryParams['type'] = type;
    // SSOT §20 / FIX-007: the staff-scoped endpoint
    // (`/api/v1/staff-workorders/`) reads `start_date`/`end_date`, while the
    // main WorkOrderViewSet reads `date_from`/`date_to` — both filter
    // `created_at`. Sending the wrong names is silently ignored server-side,
    // so "My Work" date filters previously did nothing.
    if (assignedToMe) {
      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['start_date'] = dateFrom;
      }
      if (dateTo != null && dateTo.isNotEmpty) queryParams['end_date'] = dateTo;
    } else {
      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['date_from'] = dateFrom;
      }
      if (dateTo != null && dateTo.isNotEmpty) queryParams['date_to'] = dateTo;
    }
    if (updatedFrom != null && updatedFrom.isNotEmpty) {
      queryParams['updated_from'] = updatedFrom;
    }
    if (updatedTo != null && updatedTo.isNotEmpty) {
      queryParams['updated_to'] = updatedTo;
    }
    if (completionFrom != null && completionFrom.isNotEmpty) {
      queryParams['completion_from'] = completionFrom;
    }
    if (completionTo != null && completionTo.isNotEmpty) {
      queryParams['completion_to'] = completionTo;
    }
    // depot_id/division_id/zone_id are mutually exclusive server-side (most
    // specific wins — WorkOrderViewSet.get_queryset), so sending all three
    // that are set is harmless; the server picks the narrowest.
    if (zoneId != null) queryParams['zone_id'] = zoneId;
    if (divisionId != null) queryParams['division_id'] = divisionId;
    if (depotId != null) queryParams['depot_id'] = depotId;
    if (stationId != null) queryParams['station_id'] = stationId;
    if (lcGateId != null) queryParams['lc_gate_id'] = lcGateId;
    if (serviceBuildingId != null) {
      queryParams['service_building_id'] = serviceBuildingId;
    }
    if (staffQuarterId != null) {
      queryParams['staff_quarter_id'] = staffQuarterId;
    }
    if (infraType != null && infraType.isNotEmpty) {
      queryParams['infra_type'] = infraType;
    }

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

  /// Creates a Job Work. Payload keys follow the complaint/inspection
  /// convention (`station`/`infrastructure`/`depot`/`asset` ids, `type`,
  /// `priority`, `scheduled_date` yyyy-MM-dd). `source` is omitted so the
  /// backend default (MANUAL_ENTRY) applies (SSOT §14); `due_date` is a
  /// read-only derived field, never sent on create (SSOT §15). The server
  /// owns validation — 400/403 surface as DioException for the UI to render.
  Future<WorkOrder> createWorkOrder(Map<String, dynamic> payload) async {
    final response = await _dio.post('$_workOrders/', data: payload);
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

  /// Batch-converts open Complaints into Work Orders in one all-or-nothing
  /// request — POST /work-orders/create_from_complaints/ {ids}. Response
  /// shape: `{work_order_ids, work_order_id, count, message}`.
  Future<BatchConvertResult> createWorkOrdersFromComplaints(
      List<int> ids) async {
    final response = await _dio.post(
      '$_workOrders/create_from_complaints/',
      data: {'ids': ids},
    );
    return BatchConvertResult.fromJson(_asObject(response.data) ?? const {});
  }

  /// Same as [createWorkOrdersFromComplaints] for Inspections — POST
  /// /work-orders/create_from_inspections/ {ids}.
  Future<BatchConvertResult> createWorkOrdersFromInspections(
      List<int> ids) async {
    final response = await _dio.post(
      '$_workOrders/create_from_inspections/',
      data: {'ids': ids},
    );
    return BatchConvertResult.fromJson(_asObject(response.data) ?? const {});
  }

  /// Creates deficiency rectification Job Work(s) — POST
  /// Creates deficiency rectification Job Work(s) — POST
  /// /work-orders/create_rectification/ {deficiency_ids, one_per_deficiency}.
  /// Grouped one Job Work per location by default; one per deficiency when
  /// [onePerDeficiency] is true. All-or-nothing, Depot Incharge/User only.
  /// Response shape matches the other batch endpoints
  /// (`{work_order_ids, work_order_id, count, results, message}`), so
  /// [BatchConvertResult] fits.
  Future<BatchConvertResult> createRectification(
    List<int> deficiencyIds, {
    bool onePerDeficiency = false,
  }) async {
    final response = await _dio.post(
      '$_workOrders/create_rectification/',
      data: {
        'deficiency_ids': deficiencyIds,
        'one_per_deficiency': onePerDeficiency,
      },
    );
    return BatchConvertResult.fromJson(_asObject(response.data) ?? const {});
  }

  /// Checklist templates available to attach to a Job Work at creation time
  /// (`maintenance_master`). Mirrors the web client's `getMaintenanceMasters`
  /// call — the endpoint has no server-side `schedule_type`/`template_kind`
  /// filter today, so schedule/category filtering happens client-side over
  /// this full list, same as `MaintenanceMasterList.jsx` does.
  Future<List<MaintenanceMaster>> getMaintenanceMasters() async {
    final response = await _dio.get('$_masters/');
    return _asList(response.data)
        .whereType<Map>()
        .map((e) => MaintenanceMaster.fromJson(Map<String, dynamic>.from(e)))
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
    final response =
        await _dio.get('$_workOrders/$workOrderId/allowed-actions/');
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

  Future<VerificationWorkspace> getVerificationWorkspace(
      int workOrderId) async {
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
      options: _writeOptions(idempotencyKey),
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
    if (status.toUpperCase() == 'CANCELLED') {
      payload['meta_data'] = {'cancellation_category': 'USER_ERROR'};
    }
    if (remarks != null && remarks.isNotEmpty) payload['remarks'] = remarks;
    if (checklist != null) payload['checklist'] = checklist;
    if (evidence != null) payload['evidence'] = evidence;

    final response = await _dio.post(
      '$_workOrders/$workOrderId/change-status/',
      data: payload,
      options: _writeOptions(idempotencyKey),
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

  /// Raw maintenance-record rows for report resolution — `GET
  /// /api/v1/maintenance/records/` with `?work_order=ID` and/or
  /// `?schedule=ID` (same filters web's ReportsView uses to resolve a Job
  /// Work's record, including the verification context on work_order
  /// queries). Returns decoded maps (not [MaintenanceRecord]) because
  /// report shaping consumes the raw nested lines/options.
  Future<List<Map<String, dynamic>>> fetchMaintenanceRecords({
    int? workOrderId,
    int? scheduleId,
  }) async {
    final query = <String, dynamic>{};
    if (workOrderId != null) query['work_order'] = workOrderId;
    if (scheduleId != null) query['schedule'] = scheduleId;
    final response = await _dio.get(
      '$_records/',
      queryParameters: query.isEmpty ? null : query,
    );
    return _asList(response.data)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> submitLine(int recordId, Map<String, dynamic> lineData,
      {String? idempotencyKey}) async {
    await _dio.post(
      '$_records/$recordId/submit_line/',
      data: lineData,
      options: _writeOptions(idempotencyKey),
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
      options: _writeOptions(idempotencyKey, upload: true),
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
        if (supervisorSignature != null)
          'supervisor_signature': supervisorSignature,
      },
      options: _writeOptions(idempotencyKey),
    );
  }

  /// Uploads a line-scoped evidence photo (BEFORE, DURING, AFTER).
  ///
  /// The server accepts JPEG only, up to 5 MB. `source` (ME-01) and, for
  /// CAMERA only, the capture-time GPS columns (ME-02/ME-05 — the server
  /// rejects partial location metadata and location on non-camera uploads)
  /// travel alongside the image as multipart text fields.
  Future<Map<String, dynamic>> uploadLineAttachment(
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
    String? idempotencyKey,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw ArgumentError('Attachment photo not found at $imagePath');
    }
    if (await file.length() > 5 * 1024 * 1024) {
      throw ArgumentError('Attachment photo exceeds the 5 MB server limit');
    }

    final isCamera = (source ?? '').toUpperCase() == 'CAMERA';
    final hasLocation = isCamera &&
        latitude != null &&
        longitude != null &&
        locationAccuracyM != null &&
        locationRecordedAt != null;
    final filename = imagePath.split(Platform.pathSeparator).last;
    final form = FormData.fromMap({
      'kind': kind.toUpperCase(),
      if (source != null) 'source': source.toUpperCase(),
      // ME-04: only a camera capture-flow time; never invented for gallery.
      if (isCamera && capturedAt != null)
        'captured_at': capturedAt.toIso8601String(),
      if (hasLocation)
        ...{
          'latitude': latitude.toString(),
          'longitude': longitude.toString(),
          'location_accuracy_m': locationAccuracyM.toString(),
          'location_recorded_at': locationRecordedAt.toIso8601String(),
        },
      'image': await MultipartFile.fromFile(
        imagePath,
        filename: filename.isNotEmpty ? filename : 'attachment.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });

    final response = await _dio.post(
      '$_records/$recordId/lines/$lineId/attachments/',
      data: form,
      options: _writeOptions(idempotencyKey, upload: true),
    );

    if (response.data is Map<String, dynamic>) {
      return response.data as Map<String, dynamic>;
    }
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const {};
  }

  /// Deletes a line-scoped evidence photo.
  /// Allowed only while the record is pre-TECH_COMPLETED.
  Future<void> deleteLineAttachment(
    int recordId, {
    required int lineId,
    required int attachmentId,
  }) async {
    await _dio.delete(
      '$_records/$recordId/lines/$lineId/attachments/$attachmentId/',
    );
  }

  Never _badPayload(Response<dynamic> response, String what) {
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      message: 'Unexpected $what payload',
    );
  }

  /// Reassigns the technician of an ASSIGNED Job Work (`reassign/`).
  Future<WorkOrder> reassignWorkOrder(
    int workOrderId, {
    required int technicianId,
    required String reason,
  }) async {
    final response = await _dio.post(
      '$_workOrders/$workOrderId/reassign/',
      data: {'assigned_to': technicianId, 'reason': reason},
    );
    final data = _asObject(response.data);
    if (data == null || data['id'] == null) {
      _badPayload(response, 'reassign');
    }
    return WorkOrder.fromJson(data);
  }

  /// Pre-START checklist preparation / preview (`prepare-checklist/`).
  Future<PrepareChecklistResult> prepareChecklist(int workOrderId) async {
    final response = await _dio.post(
      '$_workOrders/$workOrderId/prepare-checklist/',
      data: const {},
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'prepare-checklist');
    return PrepareChecklistResult.fromJson(data);
  }

  Future<List<SupervisorMandate>> getSupervisorMandates(int workOrderId) async {
    final response =
        await _dio.get('$_workOrders/$workOrderId/supervisor-mandate/');
    return SupervisorMandate.listFromJson(response.data);
  }

  /// Upserts the mandate for (category, name). [action] is `INCLUDE` or
  /// `EXCLUDE`.
  Future<SupervisorMandate> setSupervisorMandate(
    int workOrderId, {
    int? assetCategoryId,
    required String assetName,
    required String action,
    String reason = '',
  }) async {
    final response = await _dio.post(
      '$_workOrders/$workOrderId/supervisor-mandate/',
      data: {
        'asset_category': assetCategoryId,
        'asset_name': assetName,
        'action': action,
        'reason': reason,
      },
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'supervisor-mandate');
    return SupervisorMandate.fromJson(data);
  }

  /// Asset groups of a checklist master for the pre-START preview.
  Future<List<ChecklistGroupPreview>> getMasterChecklistGroups(
    int masterId,
  ) async {
    final response = await _dio.get('$_masters/$masterId/workspace/');
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'master workspace');
    final groups = data['groups'];
    if (groups is! List) return const [];
    return groups
        .whereType<Map>()
        .map(
            (e) => ChecklistGroupPreview.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Checks an asset group out / un-checks it (`group-inclusion/`). [reason]
  /// is omitted when null or empty.
  Future<GroupInclusionResult> setGroupInclusion(
    int recordId, {
    int? assetCategoryId,
    required String assetName,
    required bool included,
    String? reason,
  }) async {
    final response = await _dio.post(
      '$_records/$recordId/group-inclusion/',
      data: {
        'asset_category': assetCategoryId,
        'asset_name': assetName,
        'included': included,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'group-inclusion');
    return GroupInclusionResult.fromJson(data);
  }

  Future<List<DeficiencySeverityOption>> getDeficiencySeverities() async {
    final response = await _dio.get(
      '/api/v1/deficiency-severities/',
      queryParameters: const {'is_active': 'true'},
    );
    return DeficiencySeverityOption.listFromJson(response.data);
  }

  /// Changes a deficiency's severity. [expectedVersion] is the row's
  /// `deficiency_version`; a stale version yields 409.
  Future<DeficiencySeverityUpdate> updateDeficiencySeverity(
    int deficiencyId, {
    required int severityId,
    required int expectedVersion,
  }) async {
    final response = await _dio.patch(
      '/api/v1/deficiencies/$deficiencyId/',
      data: {'severity': severityId, 'expected_version': expectedVersion},
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'deficiency');
    return DeficiencySeverityUpdate.fromJson(data);
  }

  Future<RemarkFlagResult> flagRemarkDeficiency(
    int recordId, {
    required int remarkIndex,
    String? assetUniqueId,
    int? severityId,
  }) async {
    final response = await _dio.post(
      '$_records/$recordId/flag-remark-deficiency/',
      data: {
        'remark_index': remarkIndex,
        if (assetUniqueId != null) 'asset_unique_id': assetUniqueId,
        if (severityId != null) 'severity_id': severityId,
      },
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'flag-remark-deficiency');
    return RemarkFlagResult.fromJson(data);
  }

  Future<void> unflagRemarkDeficiency(
    int recordId, {
    required int remarkIndex,
  }) async {
    await _dio.post(
      '$_records/$recordId/unflag-remark-deficiency/',
      data: {'remark_index': remarkIndex},
    );
  }

  /// Authoritative eligibility and lock flags for an approval request.
  Future<Map<String, dynamic>> getScheduleApprovalState(int scheduleId) async {
    final response = await _dio.get('$_schedules/$scheduleId/');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Alternative checklist templates from the conversion context.
  Future<List<ScheduleAlternative>> getScheduleAlternatives(
    int scheduleId,
  ) async {
    final response =
        await _dio.get('$_schedules/$scheduleId/conversion-context/');
    final data = _asObject(response.data);
    final template = data?['template'];
    final alternatives = template is Map ? template['alternatives'] : null;
    if (alternatives is! List) return const [];
    return alternatives
        .whereType<Map>()
        .map((e) => ScheduleAlternative.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Raises a PM skip approval request. [reasonCode] is a key of
  /// [kSkipReasonChoices].
  Future<ApprovalRequestSummary> requestPmSkip(
    int scheduleId, {
    required String reasonCode,
    required String remarks,
  }) async {
    final response = await _dio.post(
      '$_schedules/$scheduleId/skip-request/',
      data: {'reason_code': reasonCode, 'remarks': remarks},
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'skip-request');
    return ApprovalRequestSummary.fromJson(data);
  }

  /// Raises a checklist-change approval request for a schedule occurrence.
  Future<ApprovalRequestSummary> requestChecklistChange(
    int scheduleId, {
    required int maintenanceMasterId,
    required String remarks,
  }) async {
    final response = await _dio.post(
      '$_schedules/$scheduleId/template-change-request/',
      data: {'maintenance_master_id': maintenanceMasterId, 'remarks': remarks},
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'template-change-request');
    return ApprovalRequestSummary.fromJson(data);
  }

  /// Per-request options for mutating calls: idempotency headers (when a key
  /// is given) and, for multipart uploads, generous send/receive timeouts
  /// (the global Dio receiveTimeout is 15s, too short for photo uploads on
  /// slow rail-side connections).
  Options? _writeOptions(String? key, {bool upload = false}) {
    if (key == null && !upload) return null;
    return Options(
      headers: key == null
          ? null
          : {'X-Idempotency-Key': key, 'Idempotency-Key': key},
      sendTimeout: upload ? _uploadTimeout : null,
      receiveTimeout: upload ? _uploadTimeout : null,
    );
  }
}
