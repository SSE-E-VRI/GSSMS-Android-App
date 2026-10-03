import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/network/paginated_fetch.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';

final complaintApiServiceProvider = Provider<ComplaintApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return ComplaintApiService(dio);
});

class ComplaintApiService {
  ComplaintApiService(this._dio);

  final Dio _dio;

  Future<List<Complaint>> getComplaints({
    String? status,
    String? excludeStatus,
    int? zoneId,
    int? divisionId,
    int? depotId,
    String? dateFrom,
    String? dateTo,
  }) async {
    final query = <String, dynamic>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (excludeStatus != null && excludeStatus.isNotEmpty) {
      query['exclude_status'] = excludeStatus;
    }
    // No `severity` filter — per SSOT §10.6 the backend Complaint API has no
    // severity field/filter.
    // depot/division/zone are mutually exclusive server-side (ComplaintViewSet
    // .get_queryset: depot wins over division wins over zone) — no `_id`
    // suffix here, unlike WorkOrderViewSet's zone_id/division_id/depot_id.
    if (depotId != null) {
      query['depot'] = depotId;
    } else if (divisionId != null) {
      query['division'] = divisionId;
    } else if (zoneId != null) {
      query['zone'] = zoneId;
    }
    if (dateFrom != null && dateFrom.isNotEmpty) query['start_date'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) query['end_date'] = dateTo;

    // ComplaintViewSet sets no pagination_class, so this returns in one
    // request today; the bounded walk is here so it stays correct if
    // pagination is ever switched on server-side.
    final page = await fetchAllPages(_dio, '/api/v1/complaints/', queryParameters: query);
    return page.items
        .whereType<Map>()
        .map((e) => Complaint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Map<String, dynamic>? _asObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<Complaint> getComplaint(int id) async {
    final response = await _dio.get('/api/v1/complaints/$id/');
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected complaint payload',
      );
    }
    return Complaint.fromJson(data);
  }

  Future<Complaint> createComplaint(Map<String, dynamic> complaintData) async {
    final response = await _dio.post(
      '/api/v1/complaints/',
      data: complaintData,
    );
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected complaint payload',
      );
    }
    return Complaint.fromJson(data);
  }

  /// Convert complaint to work order — POST
  /// /api/v1/complaints/{id}/convert_to_work_order/. Same ConversionService
  /// backing (and response shape: `{message, work_order_id}`) as the
  /// inspection conversion endpoint.
  Future<Map<String, dynamic>> convertToWorkOrder(int complaintId) async {
    final response =
        await _dio.post('/api/v1/complaints/$complaintId/convert_to_work_order/');
    final data = _asObject(response.data);
    return data ?? const {};
  }

  /// Direct close/reject with no Job Work — POST
  /// /api/v1/complaints/{id}/close/ {closure_reason, closure_remarks}.
  /// DEPOT_INCHARGE only server-side; OPEN complaints only (else 409).
  Future<Complaint> closeComplaint(
    int complaintId, {
    required String closureReason,
    required String closureRemarks,
  }) async {
    final response = await _dio.post(
      '/api/v1/complaints/$complaintId/close/',
      data: {
        'closure_reason': closureReason,
        'closure_remarks': closureRemarks,
      },
    );
    final data = _asObject(response.data);
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'Unexpected close payload',
      );
    }
    return Complaint.fromJson(data);
  }

  /// Upload a registration-time evidence photo (JPEG, OPEN complaints only,
  /// max 5 server-side). Returns the created photo; duplicate content
  /// returns the existing row (201) server-side.
  Future<ComplaintPhoto> uploadPhoto({
    required int complaintId,
    required MultipartFile file,
  }) async {
    final form = FormData.fromMap({'image': file});
    final response = await _dio.post(
      '/api/v1/complaints/$complaintId/photos/',
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
    return ComplaintPhoto.fromJson(data);
  }

  /// Remove a registration-time evidence photo (OPEN complaints only).
  Future<void> deletePhoto({
    required int complaintId,
    required int photoId,
  }) async {
    await _dio.delete('/api/v1/complaints/$complaintId/photos/$photoId/');
  }

  Future<void> deleteComplaint(int complaintId) async {
    await _dio.delete('/api/v1/complaints/$complaintId/');
  }
}
