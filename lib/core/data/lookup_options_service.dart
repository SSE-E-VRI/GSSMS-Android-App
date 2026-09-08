import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/domain/lookup_option.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';

final lookupOptionsServiceProvider = Provider<LookupOptionsService>((ref) {
  return LookupOptionsService(ref.watch(authenticatedDioProvider));
});

/// Options for one lookup-options domain — the same registry-backed dropdown
/// source web's `LookupSelect`/`useLookupOptions` reads (e.g.
/// `complaint_department` on the Log New Complaint form). Requires only
/// `IsAuthenticated` server-side, no extra permission code.
class LookupOptionsService {
  LookupOptionsService(this._dio);

  final Dio _dio;

  Future<List<LookupOption>> fetchOptions(String domain) async {
    final response = await _dio.get<dynamic>('/api/v1/lookup-options/$domain/');
    final data = response.data;
    final raw = data is Map ? data['options'] : null;
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(LookupOption.fromJson)
        .where((o) => o.key.isNotEmpty)
        .toList();
  }
}
