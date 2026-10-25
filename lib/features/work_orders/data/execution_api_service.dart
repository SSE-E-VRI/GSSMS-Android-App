import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';

final executionApiServiceProvider = Provider<ExecutionApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return ExecutionApiService(dio);
});

/// Technician execution endpoints for the non-checklist execution modes.
///
/// Paths mirror web's `api.js` on `StaffWorkOrderViewSet`
/// (`staff-workorders/{id}/…`). The server owns completeness — every submit
/// surfaces the backend's own 400 text, so client-side checks stay advisory.
class ExecutionApiService {
  ExecutionApiService(this._dio);
  final Dio _dio;

  static const int maxPhotoBytes = 15 * 1024 * 1024;

  String _wo(int workOrderId) => '/api/v1/staff-workorders/$workOrderId/';

  Map<String, dynamic>? _asObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Never _badPayload(Response response, String what) {
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      message: 'Unexpected $what payload',
    );
  }

  /// JPEG multipart file shared by all execution photo uploads.
  Future<MultipartFile> photoFile(String imagePath) async {
    final lower = imagePath.toLowerCase();
    if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) {
      throw ArgumentError('Only JPEG photos are allowed.');
    }
    final file = File(imagePath);
    if (!await file.exists()) {
      throw ArgumentError('Photo not found at $imagePath');
    }
    if (await file.length() > maxPhotoBytes) {
      throw ArgumentError('Photo exceeds the 15 MB limit.');
    }
    final filename = imagePath.split(Platform.pathSeparator).last;
    return MultipartFile.fromFile(
      imagePath,
      filename: filename.isNotEmpty ? filename : 'evidence.jpg',
      contentType: DioMediaType('image', 'jpeg'),
    );
  }

  // ——— Complaint (Breakdown) mode ———

  /// Breakdown details and current status from the Job Work detail.
  Future<BreakdownInfo> getBreakdownInfo(int workOrderId) async {
    final response =
        await _dio.get('/api/v1/maintenance/work-orders/$workOrderId/');
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'job work');
    return BreakdownInfo.fromWorkOrderJson(data);
  }

  Future<ComplaintExecution> getComplaintExecution(int workOrderId) async {
    final response = await _dio.get('${_wo(workOrderId)}complaint-execution/');
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'complaint execution');
    return ComplaintExecution.fromJson(data);
  }

  /// PATCH draft: any subset of initial_findings / action_taken /
  /// final_remarks / parameters.
  Future<ComplaintExecution> saveComplaintDraft(
    int workOrderId,
    Map<String, dynamic> fields,
  ) async {
    final response = await _dio.patch(
      '${_wo(workOrderId)}complaint-execution/',
      data: fields,
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'complaint execution');
    return ComplaintExecution.fromJson(data);
  }

  Future<ExecutionPhoto> uploadComplaintPhoto(
    int workOrderId, {
    required String kind,
    required MultipartFile file,
  }) async {
    final form = FormData.fromMap({'kind': kind, 'image': file});
    final response = await _dio.post(
      '${_wo(workOrderId)}complaint-execution/photos/',
      data: form,
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'execution photo');
    return ExecutionPhoto.fromJson(data);
  }

  Future<void> deleteComplaintPhoto(int workOrderId, int photoId) async {
    await _dio.delete(
        '${_wo(workOrderId)}complaint-execution/photos/$photoId/');
  }

  /// Sign & Submit — transitions to TECH_COMPLETED. Mirrors web's submit
  /// (remarks default to final remarks; digital-signature marker).
  Future<ComplaintExecution> submitComplaintExecution(
    int workOrderId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post(
      '${_wo(workOrderId)}complaint-execution/submit/',
      data: payload,
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'complaint execution');
    return ComplaintExecution.fromJson(data);
  }

  // ——— Rectification mode ———

  Future<RectificationPayload> getRectification(int workOrderId) async {
    final response = await _dio.get('${_wo(workOrderId)}rectification/');
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'rectification');
    return RectificationPayload.fromJson(data);
  }

  /// PATCH draft: any subset of final_remarks / other_staff / items
  /// ([{id, action_taken?, outcome?, reason?}]).
  Future<RectificationPayload> saveRectificationDraft(
    int workOrderId,
    Map<String, dynamic> fields,
  ) async {
    final response = await _dio.patch(
      '${_wo(workOrderId)}rectification/',
      data: fields,
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'rectification');
    return RectificationPayload.fromJson(data);
  }

  Future<ExecutionPhoto> uploadRectificationPhoto(
    int workOrderId,
    int itemId, {
    required String kind,
    required MultipartFile file,
  }) async {
    final form = FormData.fromMap({'kind': kind, 'image': file});
    final response = await _dio.post(
      '${_wo(workOrderId)}rectification/items/$itemId/photos/',
      data: form,
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'rectification photo');
    return ExecutionPhoto.fromJson(data);
  }

  Future<void> deleteRectificationPhoto(
    int workOrderId,
    int itemId,
    int photoId,
  ) async {
    await _dio.delete(
        '${_wo(workOrderId)}rectification/items/$itemId/photos/$photoId/');
  }

  Future<RectificationPayload> submitRectification(
    int workOrderId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post(
      '${_wo(workOrderId)}rectification/submit/',
      data: payload,
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'rectification');
    return RectificationPayload.fromJson(data);
  }

  // ——— Inspection mode ———

  Future<PointwiseInspectionExecution> getInspectionExecution(
    int workOrderId,
  ) async {
    final response =
        await _dio.get('${_wo(workOrderId)}inspection-execution/');
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'inspection execution');
    return PointwiseInspectionExecution.fromJson(data);
  }

  /// Creates empty per-point rows (and the header record) so PATCH/submit
  /// have something to write to. Idempotent server-side.
  Future<PointwiseInspectionExecution> initializeInspectionExecution(
    int workOrderId,
  ) async {
    final response = await _dio.post(
      '${_wo(workOrderId)}inspection-execution/initialize/',
      data: const {},
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'inspection execution');
    return PointwiseInspectionExecution.fromJson(data);
  }

  /// PATCH draft: pointwise `point_executions` (or legacy header fields).
  Future<PointwiseInspectionExecution> saveInspectionDraft(
    int workOrderId,
    Map<String, dynamic> fields,
  ) async {
    final response = await _dio.patch(
      '${_wo(workOrderId)}inspection-execution/',
      data: fields,
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'inspection execution');
    return PointwiseInspectionExecution.fromJson(data);
  }

  Future<ExecutionPhoto> uploadInspectionPhoto(
    int workOrderId, {
    int? pointJobWorkId,
    required String photoType,
    String? caption,
    required MultipartFile file,
  }) async {
    final form = FormData.fromMap({
      'photo_type': photoType,
      if (pointJobWorkId != null) 'point_job_work_id': pointJobWorkId,
      if (caption != null && caption.trim().isNotEmpty)
        'caption': caption.trim(),
      'image': file,
    });
    final response = await _dio.post(
      '${_wo(workOrderId)}inspection-execution/photos/',
      data: form,
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'inspection photo');
    return ExecutionPhoto.fromJson(data);
  }

  Future<void> deleteInspectionPhoto(int workOrderId, int photoId) async {
    await _dio
        .delete('${_wo(workOrderId)}inspection-execution/photos/$photoId/');
  }

  Future<PointwiseInspectionExecution> submitInspectionExecution(
    int workOrderId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post(
      '${_wo(workOrderId)}inspection-execution/submit/',
      data: payload,
    );
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, 'inspection execution');
    return PointwiseInspectionExecution.fromJson(data);
  }
}
