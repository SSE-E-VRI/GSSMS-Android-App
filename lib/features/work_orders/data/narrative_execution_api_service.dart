import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/narrative_execution.dart';

final narrativeExecutionApiServiceProvider = Provider<NarrativeExecutionApiService>((ref) {
  return NarrativeExecutionApiService(ref.watch(authenticatedDioProvider));
});

/// REST calls for the narrative execution form (findings, action taken,
/// parameters, Before/After photos, final remarks, Sign & Submit).
///
/// Online only: unlike the checklist these writes are not queued in the
/// outbox. The endpoints are the technician-scoped `staff-workorders` ones the
/// web form already uses (`complaint-execution/...`; the name is historical,
/// the same record serves every narrative-mode Job Work).
class NarrativeExecutionApiService {
  NarrativeExecutionApiService(this._dio);

  final Dio _dio;

  static const String _records = '/api/v1/maintenance/records';
  static const String _staffWorkOrders = '/api/v1/staff-workorders';

  Map<String, dynamic> _object(Response<dynamic> response, String what) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      message: 'Unexpected $what payload',
    );
  }

  /// Loads the record behind an execution to learn the Job Work's form mode.
  Future<NarrativeContext> getContext(int recordId) async {
    final response = await _dio.get('$_records/$recordId/');
    return NarrativeContext.fromRecordJson(_object(response, 'maintenance record'));
  }

  Future<NarrativeExecution> getExecution(int workOrderId) async {
    final response = await _dio.get('$_staffWorkOrders/$workOrderId/complaint-execution/');
    return NarrativeExecution.fromJson(_object(response, 'execution'));
  }

  /// Partial draft save: only the fields present in [fields] are written.
  Future<NarrativeExecution> saveDraft(int workOrderId, Map<String, dynamic> fields) async {
    final response = await _dio.patch(
      '$_staffWorkOrders/$workOrderId/complaint-execution/',
      data: fields,
    );
    return NarrativeExecution.fromJson(_object(response, 'execution'));
  }

  Future<NarrativePhoto> uploadPhoto(
    int workOrderId,
    NarrativePhotoKind kind,
    String filePath,
  ) async {
    final form = FormData.fromMap({
      'kind': kind.code,
      'image': await MultipartFile.fromFile(
        filePath,
        filename: filePath.split(RegExp(r'[\\/]')).last,
      ),
    });
    final response = await _dio.post(
      '$_staffWorkOrders/$workOrderId/complaint-execution/photos/',
      data: form,
    );
    return NarrativePhoto.fromJson(_object(response, 'photo'));
  }

  Future<void> deletePhoto(int workOrderId, int photoId) async {
    await _dio.delete('$_staffWorkOrders/$workOrderId/complaint-execution/photos/$photoId/');
  }

  Future<void> submit(
    int workOrderId, {
    required String remarks,
    required String technicianName,
  }) async {
    await _dio.post(
      '$_staffWorkOrders/$workOrderId/complaint-execution/submit/',
      data: {
        'remarks': remarks,
        'technician_name': technicianName,
        'technician_signature': 'SIGNED_DIGITALLY',
      },
    );
  }
}
