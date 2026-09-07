import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/data/org_scope_options_service.dart';

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
  late OrgScopeOptionsService service;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
    service = OrgScopeOptionsService(dio);
  });

  test('fetchZones GETs /api/v1/zones/ with no params', () async {
    dio.httpClientAdapter = MockAdapter((options) async {
      expect(options.path, '/api/v1/zones/');
      expect(options.queryParameters, isEmpty);
      return _json([
        {'id': 1, 'name': 'Southern Railway'},
      ], 200);
    });

    final zones = await service.fetchZones();
    expect(zones.single.id, 1);
    expect(zones.single.name, 'Southern Railway');
  });

  test('fetchDivisions GETs /api/v1/divisions/?zone=<id>', () async {
    dio.httpClientAdapter = MockAdapter((options) async {
      expect(options.path, '/api/v1/divisions/');
      expect(options.queryParameters['zone'], 5);
      return _json({
        'results': [
          {'id': 2, 'name': 'Tiruchchirappalli Division'},
        ],
      }, 200);
    });

    final divisions = await service.fetchDivisions(zoneId: 5);
    expect(divisions.single.name, 'Tiruchchirappalli Division');
  });

  test('fetchDepots prefers division over zone (matches DepotViewSet.get_queryset)', () async {
    dio.httpClientAdapter = MockAdapter((options) async {
      expect(options.path, '/api/v1/depots/');
      expect(options.queryParameters['division'], 2);
      expect(options.queryParameters.containsKey('zone'), isFalse);
      return _json(<dynamic>[], 200);
    });

    await service.fetchDepots(zoneId: 5, divisionId: 2);
  });

  test('fetchDepots falls back to zone when no division is given', () async {
    dio.httpClientAdapter = MockAdapter((options) async {
      expect(options.queryParameters['zone'], 5);
      expect(options.queryParameters.containsKey('division'), isFalse);
      return _json(<dynamic>[], 200);
    });

    await service.fetchDepots(zoneId: 5);
  });

  test('fetchStations GETs /api/v1/stations/?depot=<id>', () async {
    dio.httpClientAdapter = MockAdapter((options) async {
      expect(options.path, '/api/v1/stations/');
      expect(options.queryParameters['depot'], 9);
      return _json([
        {'id': 3, 'name': 'Sendurai'},
      ], 200);
    });

    final stations = await service.fetchStations(depotId: 9);
    expect(stations.single.name, 'Sendurai');
  });

  test('drops rows with a non-positive id', () async {
    dio.httpClientAdapter = MockAdapter((options) async {
      return _json([
        {'id': 0, 'name': 'Bad row'},
        {'id': 4, 'name': 'Good row'},
      ], 200);
    });

    final zones = await service.fetchZones();
    expect(zones.length, 1);
    expect(zones.single.name, 'Good row');
  });
}
