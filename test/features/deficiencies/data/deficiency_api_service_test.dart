import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/deficiencies/data/deficiency_api_service.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';

class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(dynamic data, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  group('DeficiencyApiService REST Contract Tests', () {
    late Dio dio;
    late DeficiencyApiService apiService;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://gssms.example.com'));
      apiService = DeficiencyApiService(dio);
    });

    test('getPendingDeficiencies queries /api/v1/deficiencies/pending/',
        () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/deficiencies/pending/');
        expect(options.queryParameters['depot'], 5);
        return _json([
          {
            'id': 10,
            'code': 'DEF-010',
            'description': 'Oil leak at valve',
            'status': 'OPEN',
            'severity_label': 'CRITICAL',
            'asset': 42,
            'asset_unique_id': 'AST-42',
            'equipment_name': 'Transformer T1',
            'depot_name': 'VRI Depot',
          }
        ], 200);
      });

      final results = await apiService.getPendingDeficiencies(depotId: 5);
      expect(results.length, 1);
      final d = results.first;
      expect(d.id, 10);
      expect(d.code, 'DEF-010');
      expect(d.status, DeficiencyStatus.open);
      expect(d.severityLabel, 'CRITICAL');
      expect(d.assetId, 42);
    });

    test('getPendingDeficiencies parses active remedial work order', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        return _json([
          {
            'id': 11,
            'code': 'DEF-011',
            'description': 'Crack on mount',
            'status': 'IN_PROGRESS',
            'active_remedial_work_order': {
              'id': 99,
              'status': 'IN_PROGRESS',
              'assigned_to_name': 'krishna',
            },
          }
        ], 200);
      });

      final results = await apiService.getPendingDeficiencies();
      expect(results.length, 1);
      expect(results.first.id, 11);
      expect(results.first.status, DeficiencyStatus.inProgress);
      expect(results.first.hasActiveRemedial, isTrue);
      expect(results.first.activeRemedialWorkOrderId, 99);
      expect(results.first.activeRemedialWorkOrderStatus, 'IN_PROGRESS');
      expect(results.first.activeRemedialWorkOrderAssignedToName, 'krishna');
    });

    test('active remedial assignee is null when absent or blank', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        return _json([
          {
            'id': 12,
            'description': 'Worn contact',
            'status': 'ASSIGNED',
            'active_remedial_work_order': {
              'id': 100,
              'status': 'ASSIGNED',
            },
          },
          {
            'id': 13,
            'description': 'Loose terminal',
            'status': 'ASSIGNED',
            'active_remedial_work_order': {
              'id': 101,
              'status': 'ASSIGNED',
              'assigned_to_name': '  ',
            },
          }
        ], 200);
      });

      final results = await apiService.getPendingDeficiencies();
      expect(results.length, 2);
      expect(results[0].activeRemedialWorkOrderAssignedToName, isNull);
      expect(results[1].activeRemedialWorkOrderAssignedToName, isNull);
    });

    test('getDeficienciesForAsset queries /api/v1/deficiencies/ with asset param',
        () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/deficiencies/');
        expect(options.queryParameters['asset'], 77);
        return _json([], 200);
      });

      final results = await apiService.getDeficienciesForAsset(77);
      expect(results, isEmpty);
    });
  });
}
