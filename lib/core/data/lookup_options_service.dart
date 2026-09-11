import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/domain/lookup_option.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';

final lookupOptionsServiceProvider = Provider<LookupOptionsService>((ref) {
  return LookupOptionsService(ref.watch(authenticatedDioProvider));
});

/// Options for one lookup domain, fetched once and shared by every screen
/// that shows or edits it (e.g. the complaint form and complaint detail both
/// need `complaint_department`). Lookup domains are backend-owned reference
/// data, so one request per session is enough; a failed fetch is not cached
/// forever — callers can `ref.invalidate` it to retry.
final lookupOptionsProvider =
    FutureProvider.family<List<LookupOption>, String>((ref, domain) {
  return ref.watch(lookupOptionsServiceProvider).fetchOptions(domain);
});

/// Display label for a lookup [key] (SSOT §9: the key is the API value, the
/// label is display-only). Falls back to a humanised key when the options are
/// not loaded or the key is unknown.
String lookupLabel(List<LookupOption>? options, String key) {
  for (final o in options ?? const <LookupOption>[]) {
    if (o.key == key) return o.label;
  }
  final words = key.replaceAll('_', ' ').toLowerCase();
  return words.isEmpty ? key : words[0].toUpperCase() + words.substring(1);
}

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
