import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/network/paginated_fetch.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_evidence_photo.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_point.dart';

final inspectionApiServiceProvider = Provider<InspectionApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return InspectionApiService(dio);
});

class InspectionApiService {
  InspectionApiService(this._dio);
  final Dio _dio;

  Future<List<Inspection>> getInspections({
    String? status,
    int? zoneId,
    int? divisionId,
    int? depotId,
    String? dateFrom,
    String? dateTo,
    bool? pendingConversion,
    String? search,
    String? inspectionNumber,
    int? assetId,
    String? excludeStatus,
  }) async {
    final query = <String, dynamic>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    // No `priority` filter — the backend Inspection model has no priority
    // column, so InspectionViewSet ignores it. Status/date/scope filtering is
    // server-side; anything finer stays client-side.
    if (pendingConversion != null) {
      query['pending_conversion'] = pendingConversion.toString();
    }
    // depot/division/zone are mutually exclusive server-side
    // (InspectionViewSet.get_queryset), no `_id` suffix.
    if (depotId != null) {
      query['depot'] = depotId;
    } else if (divisionId != null) {
      query['division'] = divisionId;
    } else if (zoneId != null) {
      query['zone'] = zoneId;
    }
    if (dateFrom != null && dateFrom.isNotEmpty) query['start_date'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) query['end_date'] = dateTo;
    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }
    if (inspectionNumber != null && inspectionNumber.trim().isNotEmpty) {
      query['inspection_number'] = inspectionNumber.trim();
    }
    if (assetId != null) query['asset'] = assetId;
    if (excludeStatus != null && excludeStatus.isNotEmpty) {
      query['exclude_status'] = excludeStatus;
    }

    // InspectionViewSet uses PageNumberPagination (page_size=100); the bounded
    // walk handles both paginated and bare-list shapes.
    final page = await fetchAllPages(_dio, '/api/v1/inspections/',
        queryParameters: query);
    return page.items
        .whereType<Map>()
        .map((e) => Inspection.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Map<String, dynamic>? _asObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<Inspection> getInspection(int id) async {
    final response = await _dio.get('/api/v1/inspections/$id/');
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected inspection payload',
      );
    }
    return Inspection.fromJson(data);
  }

  Future<List<InspectionPoint>> getInspectionPoints({
    required int inspectionId,
    String? dispositionStatus,
    String? priority,
  }) async {
    final query = <String, dynamic>{'inspection': inspectionId};
    if (dispositionStatus != null && dispositionStatus.isNotEmpty) {
      query['disposition_status'] = dispositionStatus;
    }
    if (priority != null && priority.isNotEmpty) query['priority'] = priority;
    final page = await fetchAllPages(
        _dio, '/api/v1/inspection-points/',
        queryParameters: query);
    return page.items
        .whereType<Map>()
        .map((e) => InspectionPoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<InspectionPoint> getInspectionPoint(int pointId) async {
    final response = await _dio.get('/api/v1/inspection-points/$pointId/');
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected inspection point payload',
      );
    }
    return InspectionPoint.fromJson(data);
  }

  Future<Inspection> createInspection(Map<String, dynamic> payload) async {
    final response = await _dio.post('/api/v1/inspections/', data: payload);
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected inspection payload',
      );
    }
    return Inspection.fromJson(data);
  }

  /// Legacy whole-inspection conversion. Backend 400s with
  /// STRUCTURED_CONVERSION_FORBIDDEN for point-ful inspections — callers must
  /// surface that and route to point-wise create-job-work instead. A null
  /// body still means success, so return an empty map rather than throwing.
  Future<Map<String, dynamic>> convertToWorkOrder(int inspectionId) async {
    final response = await _dio
        .post('/api/v1/inspections/$inspectionId/convert_to_work_order/');
    final data = _asObject(response.data);
    return data ?? const {};
  }

  /// Point-wise Job Work creation (Slice I2/I7.6): JW-001 or JW-002.
  Future<Map<String, dynamic>> createInspectionJobWork(
    int inspectionId, {
    required List<int> pointIds,
    required String priority,
    int? assignedTo,
    String? scheduledDate,
    String? title,
    String? description,
  }) async {
    final payload = <String, dynamic>{
      'point_ids': pointIds,
      'priority': priority,
      if (assignedTo != null) 'assigned_to': assignedTo,
      if (scheduledDate != null && scheduledDate.isNotEmpty)
        'scheduled_date': scheduledDate,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    };
    final response = await _dio.post(
        '/api/v1/inspections/$inspectionId/create-job-work/',
        data: payload);
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected create-job-work payload',
      );
    }
    return data;
  }

  Future<Inspection> closeInspection(int inspectionId) async {
    final response =
        await _dio.post('/api/v1/inspections/$inspectionId/close/', data: {});
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected close payload',
      );
    }
    return Inspection.fromJson(data);
  }

  // ——— Point disposition (Slice I5/I7.5) ———

  Future<InspectionPoint> resolveInspectionPoint(
    int pointId, {
    required String remarks,
  }) async {
    final response = await _dio.post(
        '/api/v1/inspection-points/$pointId/resolve/',
        data: {'remarks': remarks});
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected resolve payload',
      );
    }
    return InspectionPoint.fromJson(data);
  }

  Future<InspectionPoint> disposeInspectionPoint(
    int pointId, {
    required String reason,
    required String remarks,
  }) async {
    final response = await _dio.post(
        '/api/v1/inspection-points/$pointId/dispose/',
        data: {'reason': reason, 'remarks': remarks});
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected dispose payload',
      );
    }
    return InspectionPoint.fromJson(data);
  }

  Future<InspectionPoint> markUnresolvedInspectionPoint(
    int pointId, {
    required String reason,
    required String remarks,
  }) async {
    final response = await _dio.post(
        '/api/v1/inspection-points/$pointId/mark-unresolved/',
        data: {'reason': reason, 'remarks': remarks});
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected mark-unresolved payload',
      );
    }
    return InspectionPoint.fromJson(data);
  }

  Future<InspectionPoint> approveJw2InspectionPoint(
    int pointId, {
    String remarks = '',
  }) async {
    final response = await _dio.post(
        '/api/v1/inspection-points/$pointId/approve-jw2/',
        data: {'remarks': remarks});
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected approve-jw2 payload',
      );
    }
    return InspectionPoint.fromJson(data);
  }

  Future<Map<String, dynamic>> escalateInspectionPoint(
    int pointId, {
    String type = 'BREAKDOWN',
    String? priority,
    String? title,
    String? description,
    String? reason,
    String? remarks,
    String? breakdownTime,
    int? assignedTo,
  }) async {
    final payload = <String, dynamic>{'type': type};
    if (priority != null && priority.isNotEmpty) payload['priority'] = priority;
    if (title != null && title.trim().isNotEmpty) {
      payload['title'] = title.trim();
    }
    if (description != null && description.trim().isNotEmpty) {
      payload['description'] = description.trim();
    }
    if (reason != null && reason.trim().isNotEmpty) {
      payload['reason'] = reason.trim();
    }
    if (remarks != null && remarks.trim().isNotEmpty) {
      payload['remarks'] = remarks.trim();
    }
    if (breakdownTime != null && breakdownTime.isNotEmpty) {
      payload['breakdown_time'] = breakdownTime;
    }
    if (assignedTo != null) payload['assigned_to'] = assignedTo;
    final response = await _dio.post(
        '/api/v1/inspection-points/$pointId/escalate-breakdown/',
        data: payload);
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected escalate payload',
      );
    }
    return data;
  }

  // ——— Evidence photos (Slice I6, JPEG-only ≤15MB) ———

  Future<InspectionEvidencePhoto> uploadGeneralPhoto({
    required int inspectionId,
    required MultipartFile file,
    String caption = '',
  }) async {
    final form = FormData.fromMap({
      'file': file,
      if (caption.trim().isNotEmpty) 'caption': caption.trim(),
    });
    final response = await _dio.post(
      '/api/v1/inspections/$inspectionId/evidence-photos/',
      data: form,
    );
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected photo payload',
      );
    }
    return InspectionEvidencePhoto.fromJson(data);
  }

  Future<InspectionEvidencePhoto> uploadPointPhoto({
    required int pointId,
    required MultipartFile file,
    String caption = '',
  }) async {
    final form = FormData.fromMap({
      'file': file,
      if (caption.trim().isNotEmpty) 'caption': caption.trim(),
    });
    final response = await _dio.post(
      '/api/v1/inspection-points/$pointId/evidence-photos/',
      data: form,
    );
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected photo payload',
      );
    }
    return InspectionEvidencePhoto.fromJson(data);
  }
}
