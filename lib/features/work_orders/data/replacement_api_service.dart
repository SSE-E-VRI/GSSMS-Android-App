import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/replacement_requests.dart';

final replacementApiServiceProvider = Provider<ReplacementApiService>((ref) {
  return ReplacementApiService(ref.watch(authenticatedDioProvider));
});

/// Replacement writes. None of these endpoints is idempotent, so they are
/// online-only: no outbox, no retry. Dio throws on non-2xx, so a call that
/// returns has succeeded.
class ReplacementApiService {
  ReplacementApiService(this._dio);
  final Dio _dio;

  /// `POST /assets/{id}/replace_asset/`
  Future<void> replaceAsset(int assetId, AssetReplacementRequest request) async {
    await _dio.post('/api/v1/assets/$assetId/replace_asset/', data: request.toJson());
  }

  /// `POST /installed-components/{id}/replace/`
  Future<void> replaceInstalledComponent(
    String installedComponentId,
    InstalledComponentReplacementRequest request,
  ) async {
    await _dio.post(
      '/api/v1/installed-components/$installedComponentId/replace/',
      data: request.toJson(),
    );
  }

  /// `POST /maintenance/work-orders/{id}/log_replacement/`
  Future<void> logJobWorkReplacement(
    int workOrderId,
    JobWorkComponentReplacementRequest request,
  ) async {
    await _dio.post(
      '/api/v1/maintenance/work-orders/$workOrderId/log_replacement/',
      data: request.toJson(),
    );
  }
}

/// User-facing text for a failed replacement call: maps the backend's
/// Job Work error codes and keeps server wording on "Job Work".
String replacementErrorText(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      switch (data['code']?.toString()) {
        case 'WORK_ORDER_REQUIRED':
          return 'This checklist is not linked to a Job Work, so the replacement cannot be recorded.';
        case 'WORK_ORDER_SCOPE_DENIED':
          return 'Only the asset this Job Work was raised for can be replaced, and only by the technician it is assigned to.';
        case 'WORK_ORDER_TERMINAL':
          return 'This Job Work is already completed, closed or cancelled.';
      }
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return "The server did not respond in time. The replacement may already have been recorded. Check the asset's Replacement History before trying again.";
    }
  }
  return userFacingError(e)
      .replaceAll(RegExp(r'\bwork ?orders?\b', caseSensitive: false), 'Job Work');
}
