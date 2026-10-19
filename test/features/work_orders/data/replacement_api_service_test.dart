import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/replacement_requests.dart';

class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<List<int>>? requestStream, Future<void>? cancelFuture) =>
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

DioException _badResponse(int status, dynamic data) {
  final ro = RequestOptions(path: '/x');
  return DioException(
    requestOptions: ro,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: ro, statusCode: status, data: data),
  );
}

void main() {
  late Dio dio;
  late ReplacementApiService api;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
    api = ReplacementApiService(dio);
  });

  group('ReplacementApiService', () {
    test('replaceAsset posts the web payload with blank serial as empty string',
        () async {
      RequestOptions? seen;
      dio.httpClientAdapter = MockAdapter((o) async {
        seen = o;
        return _json({'status': 'replaced'}, 200);
      });
      await api.replaceAsset(
        501,
        AssetReplacementRequest(
          workOrderId: 123,
          newMake: ' Siemens ',
          replacementDate: DateTime(2026, 3, 7),
          reason: ' Burnt out ',
        ),
      );
      expect(seen!.method, 'POST');
      expect(seen!.path, '/api/v1/assets/501/replace_asset/');
      expect(seen!.data, {
        'new_make': 'Siemens',
        'new_model': '',
        'new_serial_number': '',
        'new_warranty_expiry_date': '',
        'replacement_date': '2026-03-07',
        'reason': 'Burnt out',
        'remarks': '',
        'work_order_id': 123,
      });
    });

    test('replaceInstalledComponent posts C2 body, omitting blank model/code',
        () async {
      RequestOptions? seen;
      dio.httpClientAdapter = MockAdapter((o) async {
        seen = o;
        return _json({'predecessor': {}, 'successor': {}}, 200);
      });
      await api.replaceInstalledComponent(
        '77',
        const InstalledComponentReplacementRequest(
          workOrderId: 10,
          reason: 'Burnt out',
          componentCode: 'LAMP-01',
          name: 'Indication Lamp',
          make: 'New Make',
          serialNumber: 'NEW-001',
        ),
      );
      expect(seen!.method, 'POST');
      expect(seen!.path, '/api/v1/installed-components/77/replace/');
      expect(seen!.data, {
        'replacement_work_order': 10,
        'replacement_reason': 'Burnt out',
        'new_component': {
          'component_code': 'LAMP-01',
          'name': 'Indication Lamp',
          'make': 'New Make',
          'serial_number': 'NEW-001',
        },
      });

      const noCode = InstalledComponentReplacementRequest(
        workOrderId: 10,
        reason: 'r',
        componentCode: '  ',
        name: 'n',
        make: 'm',
        model: 'M1',
        serialNumber: 's',
      );
      final nc = noCode.toJson()['new_component'] as Map;
      expect(nc.containsKey('component_code'), isFalse);
      expect(nc['model'], 'M1');
    });

    test('logJobWorkReplacement omits the warranty key when null', () async {
      RequestOptions? seen;
      dio.httpClientAdapter = MockAdapter((o) async {
        seen = o;
        return _json({'id': 1}, 200);
      });
      await api.logJobWorkReplacement(
        10,
        const JobWorkComponentReplacementRequest(
          assetReference: 'Legacy CLS Panel',
          componentName: 'Indication Lamp',
          newMake: 'Siemens',
          newSerialNumber: 'LAMP-2026-001',
          reason: 'Lamp failed',
        ),
      );
      expect(seen!.method, 'POST');
      expect(seen!.path,
          '/api/v1/maintenance/work-orders/10/log_replacement/');
      final body = seen!.data as Map;
      expect(body.containsKey('new_warranty_expiry_date'), isFalse);
      expect(body['asset_reference'], 'Legacy CLS Panel');
      expect(body['component_name'], 'Indication Lamp');
      expect(body['new_serial_number'], 'LAMP-2026-001');
      expect(body['old_make'], '');
    });

    test('warranty date is serialised when set', () {
      final body = JobWorkComponentReplacementRequest(
        assetReference: 'a',
        componentName: 'c',
        newMake: 'm',
        newSerialNumber: 's',
        reason: 'r',
        newWarrantyExpiry: DateTime(2027, 1, 2),
      ).toJson();
      expect(body['new_warranty_expiry_date'], '2027-01-02');
    });

    test('a non-2xx response throws', () async {
      dio.httpClientAdapter = MockAdapter(
          (o) async => _json({'error': 'Archived assets cannot be replaced.'}, 409));
      await expectLater(
        api.replaceAsset(
          1,
          AssetReplacementRequest(
            workOrderId: 1,
            newMake: 'm',
            replacementDate: DateTime(2026, 1, 1),
            reason: 'r',
          ),
        ),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('replacementErrorText', () {
    test('maps the three Job Work codes', () {
      expect(
        replacementErrorText(_badResponse(
            400, {'detail': 'x', 'code': 'WORK_ORDER_REQUIRED'})),
        contains('not linked to a Job Work'),
      );
      expect(
        replacementErrorText(_badResponse(403, {
          'detail': 'WorkOrder is not assigned for this asset.',
          'code': 'WORK_ORDER_SCOPE_DENIED'
        })),
        startsWith('Only the asset this Job Work was raised for'),
      );
      expect(
        replacementErrorText(
            _badResponse(409, {'detail': 'x', 'code': 'WORK_ORDER_TERMINAL'})),
        'This Job Work is already completed, closed or cancelled.',
      );
    });

    test('rewrites WorkOrder / work order wording', () {
      final t = replacementErrorText(_badResponse(
          403, {'detail': 'WorkOrder is not assigned for this asset.'}));
      expect(t, 'Job Work is not assigned for this asset.');
      final t2 = replacementErrorText(_badResponse(400,
          {'replacement_work_order': 'Work order asset does not match the parent asset.'}));
      expect(t2.toLowerCase(), isNot(contains('work order')));
      expect(t2, contains('Job Work'));
    });

    test('receive timeout warns about a possible duplicate', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.receiveTimeout,
      );
      expect(replacementErrorText(e), contains('Replacement History'));
    });
  });

  group('ReplacementJobWork.fromRecord', () {
    test('null without a Job Work id, populated otherwise', () {
      expect(ReplacementJobWork.fromRecord(const MaintenanceRecord(id: 1)), isNull);
      final jw = ReplacementJobWork.fromRecord(const MaintenanceRecord(
        id: 5,
        workOrderId: 10,
        stationId: 9,
        infrastructureId: 4,
        stationName: 'VRI',
        jobWorkAssetId: 501,
        jobWorkAssetUniqueId: 'STN-001',
        jobWorkAssetName: 'Panel',
      ))!;
      expect(jw.recordId, 5);
      expect(jw.workOrderId, 10);
      expect(jw.stationId, 9);
      expect(jw.infrastructureId, 4);
      expect(jw.stationName, 'VRI');
      expect(jw.assetId, 501);
      expect(jw.assetUniqueId, 'STN-001');
      expect(jw.assetName, 'Panel');
    });
  });
}
