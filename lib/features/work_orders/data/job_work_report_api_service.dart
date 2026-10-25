import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';

final jobWorkReportApiServiceProvider =
    Provider<JobWorkReportApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return JobWorkReportApiService(dio);
});

/// Read-only endpoints behind the technician Job Work report. Returns raw
/// JSON maps; shaping lives in `job_work_report.dart`.
class JobWorkReportApiService {
  JobWorkReportApiService(this._dio);
  final Dio _dio;

  String _staff(int woId) => '/api/v1/staff-workorders/$woId/';

  Map<String, dynamic>? _asObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  List<dynamic>? _asList(dynamic data) {
    if (data is List) return data;
    final obj = _asObject(data);
    final results = obj?['results'];
    if (results is List) return results;
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

  Future<Map<String, dynamic>> _getObject(String path, String what) async {
    final response = await _dio.get(path);
    final data = _asObject(response.data);
    if (data == null) _badPayload(response, what);
    return data;
  }

  Future<Map<String, dynamic>?> _firstRecord(
    Map<String, dynamic> query,
  ) async {
    final response = await _dio.get(
      '/api/v1/maintenance/records/',
      queryParameters: query,
    );
    final list = _asList(response.data);
    if (list == null) _badPayload(response, 'maintenance records');
    for (final e in list) {
      final obj = _asObject(e);
      if (obj != null) return obj;
    }
    return null;
  }

  /// Checklist record for a Job Work. Must use the list form with
  /// `?work_order=` - only that path attaches `verification` (the detail
  /// endpoint returns `verification: null`). Falls back to the schedule
  /// (legacy rows) and returns null when neither finds a record.
  Future<Map<String, dynamic>?> fetchChecklistRecord(
    int woId, {
    int? scheduleId,
  }) async {
    final byWorkOrder = await _firstRecord({'work_order': woId});
    if (byWorkOrder != null) return byWorkOrder;
    if (scheduleId == null) return null;
    return _firstRecord({'schedule': scheduleId});
  }

  /// Job Work detail (carries `original_complaint_details` /
  /// `original_deficiency_details`).
  Future<Map<String, dynamic>> fetchWorkOrder(int woId) =>
      _getObject('/api/v1/maintenance/work-orders/$woId/', 'job work');

  Future<Map<String, dynamic>> fetchComplaintExecution(int woId) =>
      _getObject('${_staff(woId)}complaint-execution/', 'complaint execution');

  Future<Map<String, dynamic>> fetchInspectionExecution(int woId) =>
      _getObject(
          '${_staff(woId)}inspection-execution/', 'inspection execution');

  Future<Map<String, dynamic>> fetchRectification(int woId) =>
      _getObject('${_staff(woId)}rectification/', 'rectification');

  /// Protected-media rewrite (mirrors web `ProtectedImage.getFetchUrl`): an
  /// absolute URL whose path starts with `/media/` becomes `path?query` so it
  /// goes through the configured API base URL (and the Bearer token);
  /// anything else is returned unchanged.
  static String mediaFetchUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.path.startsWith('/media/')) {
      return url.trim();
    }
    return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  }

  /// Accept header for photo downloads. The media endpoint is a DRF view
  /// with JSON renderers only, and DRF answers 406 to a request that accepts
  /// nothing but `image/*` — before it even serves the file — so every report
  /// photo came back as "No photo". `*/*` keeps the request satisfiable.
  static const String photoAccept = 'image/*, */*';

  Future<Uint8List> fetchPhotoBytes(String url) async {
    final response = await _dio.get<List<int>>(
      mediaFetchUrl(url),
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Accept': photoAccept},
      ),
    );
    final data = response.data;
    if (data == null) _badPayload(response, 'photo');
    return data is Uint8List ? data : Uint8List.fromList(data);
  }
}
