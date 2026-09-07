import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/domain/org_option.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';

final orgScopeOptionsServiceProvider = Provider<OrgScopeOptionsService>((ref) {
  return OrgScopeOptionsService(ref.watch(authenticatedDioProvider));
});

/// Option lists for [OrgScopeFilterBar]'s Zone/Division/Depot/Station
/// dropdowns. Each endpoint already scopes its results to what the caller is
/// permitted to see (`ScopeService.filter_queryset` server-side) and accepts
/// its parent's id for cascading — a Division Admin calling `/depots/` with
/// no params already gets only their division's depots, so this service adds
/// no client-side scope logic of its own, only the parent-id param.
class OrgScopeOptionsService {
  OrgScopeOptionsService(this._dio);

  final Dio _dio;

  List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    return const [];
  }

  Future<List<OrgOption>> _fetch(String path, Map<String, dynamic> query) async {
    final response = await _dio.get<dynamic>(path, queryParameters: query);
    return _asList(response.data)
        .whereType<Map<String, dynamic>>()
        .map(OrgOption.fromJson)
        .where((o) => o.id > 0)
        .toList();
  }

  Future<List<OrgOption>> fetchZones() => _fetch('/api/v1/zones/', const {});

  Future<List<OrgOption>> fetchDivisions({int? zoneId}) => _fetch(
        '/api/v1/divisions/',
        {if (zoneId != null) 'zone': zoneId},
      );

  Future<List<OrgOption>> fetchDepots({int? zoneId, int? divisionId}) => _fetch(
        '/api/v1/depots/',
        {
          if (divisionId != null) 'division': divisionId,
          if (divisionId == null && zoneId != null) 'zone': zoneId,
        },
      );

  Future<List<OrgOption>> fetchStations({int? depotId}) => _fetch(
        '/api/v1/stations/',
        {if (depotId != null) 'depot': depotId},
      );
}
