import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

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
  group('WorkOrderApiService REST Contract Tests', () {
    late Dio dio;
    late WorkOrderApiService apiService;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://gssms.share.zrok.io'));
      apiService = WorkOrderApiService(dio);
    });

    test('getWorkOrders calls GET /api/v1/maintenance/work-orders/ with correct query params', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/work-orders/');
        expect(options.queryParameters['status'], 'ASSIGNED');
        expect(options.queryParameters['type'], 'PREVENTIVE');
        expect(options.queryParameters['date_from'], '2026-09-01');
        expect(options.queryParameters['date_to'], '2026-09-07');

        return _json([
          {
            'id': 101,
            'status': 'ASSIGNED',
            'type': 'PREVENTIVE',
            'title': 'Test WO',
          }
        ], 200);
      });

      final orders = await apiService.getWorkOrders(
        status: 'ASSIGNED',
        type: 'PREVENTIVE',
        dateFrom: '2026-09-01',
        dateTo: '2026-09-07',
      );
      expect(orders.length, 1);
      expect(orders[0].id, 101);
      expect(orders[0].status, WorkOrderStatus.assigned);
    });

    test('startExecution calls POST /api/v1/staff-workorders/{id}/execute/ and returns record_id', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/staff-workorders/101/execute/');
        expect(options.method, 'POST');
        return _json({'record_id': 55}, 200);
      });

      final recordId = await apiService.startExecution(101);
      expect(recordId, 55);
    });

    test('changeStatus calls POST /api/v1/maintenance/work-orders/{id}/change-status/', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/work-orders/101/change-status/');
        final data = options.data as Map<String, dynamic>;
        expect(data['status'], 'IN_PROGRESS');
        expect(data['remarks'], 'Starting execution');

        return _json({
          'id': 101,
          'status': 'IN_PROGRESS',
          'type': 'PREVENTIVE',
        }, 200);
      });

      final updated = await apiService.changeStatus(
        101,
        status: 'IN_PROGRESS',
        remarks: 'Starting execution',
      );
      expect(updated.status, WorkOrderStatus.inProgress);
    });

    test('assignTechnician PATCHes assigned_to on the work order', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/work-orders/101/');
        expect(options.method, 'PATCH');
        expect(options.data['assigned_to'], 4);
        return _json({
          'id': 101,
          'status': 'NEW',
          'type': 'PREVENTIVE',
          'assigned_to': 4,
          'assigned_to_name': 'tech_ramesh',
        }, 200);
      });

      final updated = await apiService.assignTechnician(101, 4);
      expect(updated.assignedToId, 4);
    });

    test('getAssignableTechnicians GETs /api/v1/users/?role=MAINTENANCE_STAFF', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/users/');
        expect(options.queryParameters['role'], 'MAINTENANCE_STAFF');
        return _json({
          'results': [
            {'id': 4, 'username': 'tech_ramesh', 'first_name': 'Ramesh'},
          ],
        }, 200);
      });

      final techs = await apiService.getAssignableTechnicians();
      expect(techs.single.id, 4);
      expect(techs.single.name, 'Ramesh');
    });

    test('getAssignableTechnicians passes depot when depotId is given', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.queryParameters['role'], 'MAINTENANCE_STAFF');
        expect(options.queryParameters['depot'], 7);
        return _json({'results': <dynamic>[]}, 200);
      });

      await apiService.getAssignableTechnicians(depotId: 7);
    });

    test('verifyWorkOrder POSTs /work-orders/{id}/verify/', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/work-orders/101/verify/');
        expect(options.method, 'POST');
        expect(options.data['remarks'], 'Looks good');
        return _json({
          'id': 101,
          'status': 'VERIFIED',
          'type': 'PREVENTIVE',
          'verified_by_name': 'incharge_kumar',
        }, 200);
      });

      final updated = await apiService.verifyWorkOrder(101, remarks: 'Looks good');
      expect(updated.status, WorkOrderStatus.verified);
      expect(updated.verifiedByName, 'incharge_kumar');
    });

    test('getVerificationWorkspace GETs verification-workspace', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(
          options.path,
          '/api/v1/maintenance/work-orders/101/verification-workspace/',
        );
        return _json({
          'can_verify': true,
          'disabled_reasons': <String>[],
          'deficiencies': <dynamic>[],
          'record': {'id': 55, 'work_order': 101, 'lines': <dynamic>[]},
        }, 200);
      });

      final workspace = await apiService.getVerificationWorkspace(101);
      expect(workspace.canVerify, isTrue);
      expect(workspace.record?.id, 55);
    });

    test('submitLine calls POST /api/v1/maintenance/records/{id}/submit_line/', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/records/55/submit_line/');
        final data = options.data as Map<String, dynamic>;
        expect(data['line_id'], 12);
        expect(data['value'], '230V');

        return _json({'status': 'updated'}, 200);
      });

      await apiService.submitLine(55, {'line_id': 12, 'value': '230V'});
    });

    test('createWorkOrder POSTs /api/v1/maintenance/work-orders/ with payload', () async {
      dio.httpClientAdapter = MockAdapter((options) async {
        expect(options.path, '/api/v1/maintenance/work-orders/');
        expect(options.method, 'POST');
        final data = options.data as Map<String, dynamic>;
        expect(data['title'], 'Station monthly maintenance');
        expect(data['type'], 'PREVENTIVE');
        expect(data['source'], 'MOBILE');
        return _json({
          'id': 202,
          'status': 'NEW',
          'type': 'PREVENTIVE',
          'title': 'Station monthly maintenance',
        }, 201);
      });

      final created = await apiService.createWorkOrder({
        'title': 'Station monthly maintenance',
        'type': 'PREVENTIVE',
        'source': 'MOBILE',
      });
      expect(created.id, 202);
      expect(created.status, WorkOrderStatus.newOrder);
    });
  });

  group('WP5 foundation endpoints', () {
    late Dio dio;
    late WorkOrderApiService apiService;
    late List<RequestOptions> seen;

    setUp(() {
      dio = Dio();
      apiService = WorkOrderApiService(dio);
    });

    void respond(dynamic body, [int code = 200]) {
      seen = [];
      dio.httpClientAdapter = MockAdapter((options) async {
        seen.add(options);
        return _json(body, code);
      });
    }

    test('reassignWorkOrder POSTs reassign/ with assigned_to + reason', () async {
      respond({'id': 7, 'status': 'ASSIGNED', 'type': 'PREVENTIVE'});
      final wo = await apiService.reassignWorkOrder(7,
          technicianId: 33, reason: 'Original technician on leave');
      expect(seen.single.method, 'POST');
      expect(seen.single.path, '/api/v1/maintenance/work-orders/7/reassign/');
      expect(seen.single.data,
          {'assigned_to': 33, 'reason': 'Original technician on leave'});
      expect(wo.id, 7);
    });

    test('prepareChecklist POSTs empty body and parses preview', () async {
      respond({
        'record_id': null,
        'created': false,
        'line_count': 12,
        'preview': true,
        'master_id': 5,
      });
      final r = await apiService.prepareChecklist(9);
      expect(seen.single.method, 'POST');
      expect(
          seen.single.path, '/api/v1/maintenance/work-orders/9/prepare-checklist/');
      expect(seen.single.data, isEmpty);
      expect(r.preview, isTrue);
      expect(r.recordId, isNull);
      expect(r.masterId, 5);
      expect(r.lineCount, 12);
    });

    test('getSupervisorMandates GETs a bare list', () async {
      respond([
        {
          'id': 1,
          'asset_category': 4,
          'asset_category_name': 'Pumps',
          'asset_name': '',
          'action': 'EXCLUDE',
          'reason': 'Out of service',
          'mandated_by_name': 'Sup',
          'updated_at': '2026-05-01T10:00:00Z',
        }
      ]);
      final list = await apiService.getSupervisorMandates(9);
      expect(seen.single.method, 'GET');
      expect(seen.single.path,
          '/api/v1/maintenance/work-orders/9/supervisor-mandate/');
      expect(list.single.isExclude, isTrue);
      expect(list.single.assetCategoryId, 4);
      expect(list.single.updatedAt, isNotNull);
    });

    test('setSupervisorMandate POSTs category/name/action/reason', () async {
      respond({'id': 2, 'action': 'INCLUDE', 'asset_name': 'DG'}, 201);
      final m = await apiService.setSupervisorMandate(9,
          assetName: 'DG', action: 'INCLUDE');
      expect(seen.single.method, 'POST');
      expect(seen.single.data, {
        'asset_category': null,
        'asset_name': 'DG',
        'action': 'INCLUDE',
        'reason': '',
      });
      expect(m.isExclude, isFalse);
    });

    test('getMasterChecklistGroups counts points + parameters', () async {
      respond({
        'id': 5,
        'groups': [
          {
            'asset_category': 3,
            'asset_category_name': 'UPS',
            'asset_name': '',
            'points': [{}, {}],
            'parameters': [{}],
          },
          {
            'asset_category': null,
            'asset_category_name': null,
            'asset_name': '',
            'points': [{}],
            'parameters': [],
          },
        ],
      });
      final groups = await apiService.getMasterChecklistGroups(5);
      expect(seen.single.method, 'GET');
      expect(seen.single.path, '/api/v1/maintenance/masters/5/workspace/');
      expect(groups[0].itemCount, 3);
      expect(groups[0].title, 'UPS');
      expect(groups[0].canMandate, isTrue);
      expect(groups[1].title, 'General Items');
      expect(groups[1].canMandate, isFalse);
    });

    test('setGroupInclusion sends keys and omits empty reason', () async {
      respond({
        'included': true,
        'checked_out': true,
        'excluded': false,
        'exclusion_reason': '',
        'applicability': 'REQUIRED',
        'checkout_source': 'TECHNICIAN',
        'returned_to_technician': false,
      });
      final r = await apiService.setGroupInclusion(70,
          assetCategoryId: 3, assetName: 'UPS', included: true);
      expect(seen.single.method, 'POST');
      expect(seen.single.path,
          '/api/v1/maintenance/records/70/group-inclusion/');
      expect(seen.single.data,
          {'asset_category': 3, 'asset_name': 'UPS', 'included': true});
      expect(r.checkedOut, isTrue);
      expect(r.checkoutSource, 'TECHNICIAN');

      respond({'included': false, 'checked_out': false, 'returned_to_technician': true});
      final r2 = await apiService.setGroupInclusion(70,
          assetName: 'UPS', included: false, reason: ' wrong asset ');
      expect((seen.single.data as Map)['reason'], 'wrong asset');
      expect(r2.returnedToTechnician, isTrue);
    });

    test('getDeficiencySeverities filters active and accepts {results}', () async {
      respond({
        'results': [
          {'id': 1, 'code': 'HIGH', 'label': 'High', 'display_order': 1}
        ]
      });
      final list = await apiService.getDeficiencySeverities();
      expect(seen.single.method, 'GET');
      expect(seen.single.path, '/api/v1/deficiency-severities/');
      expect(seen.single.queryParameters['is_active'], 'true');
      expect(list.single.label, 'High');
    });

    test('updateDeficiencySeverity PATCHes severity + expected_version', () async {
      respond({'id': 8, 'severity': 2, 'severity_label': 'Low', 'version': 4});
      final u = await apiService.updateDeficiencySeverity(8,
          severityId: 2, expectedVersion: 3);
      expect(seen.single.method, 'PATCH');
      expect(seen.single.path, '/api/v1/deficiencies/8/');
      expect(seen.single.data, {'severity': 2, 'expected_version': 3});
      expect(u.version, 4);
      expect(u.severityLabel, 'Low');
    });

    test('flag/unflag remark deficiency', () async {
      respond({
        'id': 11,
        'remark_index': 1,
        'version': 1,
        'severity_id': 2,
        'severity_label': 'Low',
        'asset_label': 'A',
        'status': 'OPEN',
      });
      final f = await apiService.flagRemarkDeficiency(70, remarkIndex: 1);
      expect(seen.single.method, 'POST');
      expect(seen.single.path,
          '/api/v1/maintenance/records/70/flag-remark-deficiency/');
      expect(seen.single.data, {'remark_index': 1});
      expect(f.id, 11);

      respond({'remark_index': 1, 'unflagged': true});
      await apiService.flagRemarkDeficiency(70,
          remarkIndex: 2, assetUniqueId: 'AST-1', severityId: 5);
      expect(seen.single.data,
          {'remark_index': 2, 'asset_unique_id': 'AST-1', 'severity_id': 5});

      respond({'remark_index': 1, 'unflagged': true});
      await apiService.unflagRemarkDeficiency(70, remarkIndex: 1);
      expect(seen.single.path,
          '/api/v1/maintenance/records/70/unflag-remark-deficiency/');
      expect(seen.single.data, {'remark_index': 1});
    });

    test('schedule alternatives, skip and checklist-change requests', () async {
      respond({
        'template': {
          'alternatives': [
            {'id': 3, 'name': 'Alt A', 'schedule_type': 'ASSET_TEMPLATE'}
          ]
        }
      });
      final alts = await apiService.getScheduleAlternatives(21);
      expect(seen.single.method, 'GET');
      expect(seen.single.path,
          '/api/v1/maintenance/schedules/21/conversion-context/');
      expect(alts.single.name, 'Alt A');

      respond({'id': 1, 'request_type': 'SKIP', 'status': 'PENDING'}, 201);
      final skip = await apiService.requestPmSkip(21,
          reasonCode: 'ASSET_UNAVAILABLE', remarks: 'Asset under repair');
      expect(seen.single.method, 'POST');
      expect(seen.single.path,
          '/api/v1/maintenance/schedules/21/skip-request/');
      expect(seen.single.data,
          {'reason_code': 'ASSET_UNAVAILABLE', 'remarks': 'Asset under repair'});
      expect(skip.status, 'PENDING');

      respond({'id': 2, 'request_type': 'TEMPLATE_CHANGE', 'status': 'PENDING'}, 201);
      final change = await apiService.requestChecklistChange(21,
          maintenanceMasterId: 3, remarks: 'Better fit');
      expect(seen.single.path,
          '/api/v1/maintenance/schedules/21/template-change-request/');
      expect(seen.single.data,
          {'maintenance_master_id': 3, 'remarks': 'Better fit'});
      expect(change.requestType, 'TEMPLATE_CHANGE');
    });
  });

}
