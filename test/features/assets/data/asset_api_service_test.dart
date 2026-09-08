import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';

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
  group('AssetApiService REST Contract Tests', () {
    late Dio dio;
    late AssetApiService apiService;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      apiService = AssetApiService(dio);
    });

    test('getAssets calls GET /api/v1/assets/ with query params', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/assets/');
        expect(options.queryParameters['search'], 'TR-01');
        return _json([
          {
            'id': 1,
            'unique_id': 'TR-01',
            'asset_type_name': 'Transformer',
            'criticality': 'CRITICAL',
          }
        ], 200);
      });

      final page = await apiService.getAssets(search: 'TR-01');
      expect(page.truncated, isFalse);
      expect(page.assets.length, 1);
      expect(page.assets[0].uniqueId, 'TR-01');
      expect(page.assets[0].criticality, AssetCriticality.critical);
    });

    test('findAssetByCode resolves a scan through the search endpoint', () async {
      // There is no by_code endpoint on the backend, so a lookup searches the
      // register and then requires an exact identifier match.
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/assets/');
        expect(options.queryParameters['search'], 'VRI-STN-CLS-MAIN-001');
        return _json([
          {
            'id': 42,
            'unique_id': 'VRI-STN-CLS-MAIN-001',
            'asset_type_name': 'Main Panel',
          },
        ], 200);
      });

      final asset = await apiService.findAssetByCode('VRI-STN-CLS-MAIN-001');
      expect(asset, isNotNull);
      expect(asset?.id, 42);
      expect(asset?.uniqueId, 'VRI-STN-CLS-MAIN-001');
    });

    test('findAssetByCode returns null when the search only partially matches',
        () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        return _json([
          {'id': 43, 'unique_id': 'VRI-STN-CLS-MAIN-002'},
          {'id': 44, 'unique_id': 'VRI-STN-CLS-MAIN-003'},
        ], 200);
      });

      expect(
        await apiService.findAssetByCode('VRI-STN-CLS'),
        isNull,
        reason: 'a scan must identify exactly one asset, not the first partial hit',
      );
    });
  });
}
