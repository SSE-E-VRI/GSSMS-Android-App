import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/reports/data/infrastructure_options_service.dart';
import 'package:gssms_mobile/features/reports/data/reports_api_service.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';

class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(dynamic data, int statusCode) => ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  late Dio dio;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
  });

  test('register_report sends station_id for Station filters', () async {
    final api = ReportsApiService(dio);
    dio.httpClientAdapter = MockAdapter((options) async {
      expect(options.path, '/api/v1/maintenance/records/register_report/');
      expect(options.queryParameters['start_date'], '2026-09-01');
      expect(options.queryParameters['end_date'], '2026-09-07');
      expect(options.queryParameters['station_id'], 12);
      return _json(<dynamic>[], 200);
    });

    await api.getMaintenanceRegister(
      startDate: '2026-09-01',
      endDate: '2026-09-07',
      infraType: InfraFilterType.station,
      infraId: 12,
    );
  });

  // Regression: a type chosen with no specific item ("All LC Gates") used to
  // send no filter param at all, since the id param is only present when an
  // item is picked. The server's infra_type fallback only applies when no id
  // param is present, so this is what makes a type-only selection filter.
  test('register_report sends infra_type when only a type is selected (no item)', () async {
    final api = ReportsApiService(dio);
    dio.httpClientAdapter = MockAdapter((options) async {
      expect(options.queryParameters['infra_type'], 'LC_GATE');
      expect(options.queryParameters.containsKey('lc_gate_id'), isFalse);
      return _json(<dynamic>[], 200);
    });

    await api.getMaintenanceRegister(
      startDate: '2026-09-01',
      endDate: '2026-09-07',
      infraType: InfraFilterType.lcGate,
    );
  });

  test('register_report sends both infra_type and the specific id when an item is picked', () async {
    final api = ReportsApiService(dio);
    dio.httpClientAdapter = MockAdapter((options) async {
      expect(options.queryParameters['infra_type'], 'SERVICE_BUILDING');
      expect(options.queryParameters['service_building_id'], 8);
      return _json(<dynamic>[], 200);
    });

    await api.getMaintenanceRegister(
      startDate: '2026-09-01',
      endDate: '2026-09-07',
      infraType: InfraFilterType.serviceBuilding,
      infraId: 8,
    );
  });

  test('register_report sends no infra filter param when type is "all"', () async {
    final api = ReportsApiService(dio);
    dio.httpClientAdapter = MockAdapter((options) async {
      expect(options.queryParameters.containsKey('infra_type'), isFalse);
      expect(options.queryParameters.keys.any((k) => k.endsWith('_id')), isFalse);
      return _json(<dynamic>[], 200);
    });

    await api.getMaintenanceRegister(
      startDate: '2026-09-01',
      endDate: '2026-09-07',
    );
  });

  test('stations options come from GET /api/v1/stations/', () async {
    final api = InfrastructureOptionsService(dio);
    dio.httpClientAdapter = MockAdapter((options) async {
      expect(options.path, '/api/v1/stations/');
      return _json({
        'results': [
          {'id': 3, 'name': 'Sendurai'},
        ],
      }, 200);
    });

    final options = await api.fetchOptions(InfraFilterType.station);
    expect(options.single.id, 3);
    expect(options.single.name, 'Sendurai');
  });

  test('LC options come from GET /api/v1/infrastructure/?type_code=LC', () async {
    final api = InfrastructureOptionsService(dio);
    dio.httpClientAdapter = MockAdapter((options) async {
      expect(options.path, '/api/v1/infrastructure/');
      expect(options.queryParameters['type_code'], 'LC');
      return _json([
        {'id': 8, 'name': 'LC-12'},
      ], 200);
    });

    final options = await api.fetchOptions(InfraFilterType.lcGate);
    expect(options.single.id, 8);
  });
}
