import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/data/execution_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/complaint_execution_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/inspection_execution_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/rectification_execution_screen.dart';

import '../../../helpers/fake_auth.dart';

class _FakeExecApi extends ExecutionApiService {
  _FakeExecApi() : super(Dio());

  ComplaintExecution complaint = const ComplaintExecution(id: 1);
  PointwiseInspectionExecution inspection =
      const PointwiseInspectionExecution();
  RectificationPayload rectification = const RectificationPayload();
  final List<Map<String, dynamic>> complaintDraftSaves = [];
  final List<Map<String, dynamic>> complaintSubmissions = [];
  final List<Map<String, dynamic>> rectificationDraftSaves = [];
  final List<Map<String, dynamic>> rectificationSubmissions = [];

  @override
  Future<ComplaintExecution> saveComplaintDraft(
    int workOrderId,
    Map<String, dynamic> fields,
  ) async {
    complaintDraftSaves.add(fields);
    return complaint;
  }

  @override
  Future<ComplaintExecution> submitComplaintExecution(
    int workOrderId,
    Map<String, dynamic> payload,
  ) async {
    complaintSubmissions.add(payload);
    return complaint;
  }

  @override
  Future<ComplaintExecution> getComplaintExecution(int workOrderId) async =>
      complaint;

  BreakdownInfo? breakdownInfo =
      const BreakdownInfo(status: 'IN_PROGRESS', ticket: 'UMG-202610-0020');

  @override
  Future<BreakdownInfo> getBreakdownInfo(int workOrderId) async {
    final info = breakdownInfo;
    if (info == null) throw StateError('work order unavailable');
    return info;
  }

  @override
  Future<PointwiseInspectionExecution> initializeInspectionExecution(
          int workOrderId) async =>
      inspection;

  @override
  Future<RectificationPayload> getRectification(int workOrderId) async =>
      rectification;

  @override
  Future<RectificationPayload> saveRectificationDraft(
    int workOrderId,
    Map<String, dynamic> fields,
  ) async {
    rectificationDraftSaves.add(fields);
    return rectification;
  }

  @override
  Future<RectificationPayload> submitRectification(
    int workOrderId,
    Map<String, dynamic> payload,
  ) async {
    rectificationSubmissions.add(payload);
    return rectification;
  }
}

Widget _harness(
  Widget home,
  _FakeExecApi api, {
  List<String> permissions = const ['maintenance.view', 'maintenance.edit'],
}) {
  return ProviderScope(
    overrides: [
      executionApiServiceProvider.overrideWithValue(api),
      authControllerProvider.overrideWith(
        () => FakeAuthenticatedController(
          fakeSession(
            role: AuthRole.maintenanceStaff,
            userId: 1,
            permissions: permissions,
          ),
        ),
      ),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: home),
  );
}

void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('Execution screens', () {
    testWidgets('ComplaintExecutionScreen fills fields from the server',
        (tester) async {
      final api = _FakeExecApi()
        ..complaint = const ComplaintExecution(
          id: 9,
          initialFindings: 'Relay burnt',
          actionTaken: 'Replaced relay',
          finalRemarks: 'Tested OK',
        );
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const ComplaintExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      expect(find.text('Relay burnt'), findsOneWidget);
      expect(find.text('Replaced relay'), findsOneWidget);
      expect(find.text('Tested OK'), findsOneWidget);
    });

    testWidgets('typing autosaves once after the debounce and shows status',
        (tester) async {
      final api = _FakeExecApi();
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const ComplaintExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();
      expect(api.complaintDraftSaves, isEmpty);

      await tester.enterText(
          find.byKey(const Key('exec_findings_field')), 'Relay burnt');
      await tester.pump(const Duration(milliseconds: 1000));
      expect(api.complaintDraftSaves, isEmpty);
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();

      expect(api.complaintDraftSaves, isNotEmpty);
      expect(api.complaintDraftSaves.single['initial_findings'], 'Relay burnt');
      expect(find.textContaining('All changes saved'), findsOneWidget);
      // Typing was not disturbed by the save.
      expect(find.text('Relay burnt'), findsOneWidget);
    });

    testWidgets('Save Progress saves now and shows the toast', (tester) async {
      final api = _FakeExecApi();
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const ComplaintExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      final save = find.byKey(const Key('save_exec_draft_button'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump();

      expect(api.complaintDraftSaves, hasLength(1));
      expect(find.text('Progress saved.'), findsOneWidget);
    });

    testWidgets(
        'a photo waiting on the phone says when it uploads and offers retake, not retry',
        (tester) async {
      final dir = Directory.systemTemp.createTempSync('pending_photo_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final photo = File('${dir.path}${Platform.pathSeparator}before.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      SharedPreferences.setMockInitialValues({
        'complaint_execution_pending_photos_7': jsonEncode([
          {'kind': 'BEFORE', 'localPath': photo.path, 'ownerUserId': 1},
        ]),
      });
      final api = _FakeExecApi();
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const ComplaintExecutionScreen(workOrderId: 7), api),
      );
      // The screen checks each saved photo on disk; real file I/O needs real time.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();

      expect(find.text('On this phone. Uploads when you tap Save Progress.'),
          findsOneWidget);
      expect(find.text('Not uploaded yet'), findsNothing);
      expect(find.byTooltip('Retake photo'), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsWidgets);
      expect(find.byIcon(Icons.replay_outlined), findsNothing);
      // Same per-kind cap as the server and web.
      expect(find.text('Before photos (1/10)'), findsOneWidget);
    });

    testWidgets('shows the breakdown information the web form shows',
        (tester) async {
      final api = _FakeExecApi()
        ..breakdownInfo = BreakdownInfo.fromWorkOrderJson({
          'status': 'IN_PROGRESS',
          'ticket_number': 'UMG-202610-0020',
          'description': 'platform light not working and MCB found in normal position',
          'original_complaint_details': {
            'failure_date': '2026-10-24',
            'failure_time': '18:30:00',
            'complainant_name': 'on-duty SM Shri paneerselvam',
            'general_asset_description': 'platform light',
            'station_name': 'Uthangal Mangalam',
          },
        });
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const ComplaintExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('breakdown_info_card')), findsOneWidget);
      for (final text in [
        'UMG-202610-0020',
        '24/10/2026',
        '18:30',
        'on-duty SM Shri paneerselvam',
        'platform light',
        'Uthangal Mangalam',
        'platform light not working and MCB found in normal position',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.byKey(const Key('exec_read_only_notice')), findsNothing);
    });

    testWidgets('a Job Work that is not In Progress opens read-only',
        (tester) async {
      final api = _FakeExecApi()
        ..breakdownInfo = const BreakdownInfo(status: 'TECH_COMPLETED')
        ..complaint = const ComplaintExecution(
          id: 9,
          initialFindings: 'Relay burnt',
          parameters: [
            {'parameter': 'red phase', 'value': '217', 'unit': 'voltage'},
          ],
          photos: [ExecutionPhoto(id: 3, kind: 'BEFORE')],
        );
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const ComplaintExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('This Job Work is Tech Completed'),
          findsOneWidget);
      expect(find.byKey(const Key('submit_exec_button')), findsNothing);
      expect(find.byKey(const Key('save_exec_draft_button')), findsNothing);
      expect(find.byKey(const Key('exec_technician_name_field')), findsNothing);
      expect(find.byKey(const Key('add_before_photo_button')), findsNothing);
      expect(find.byKey(const Key('add_param_row_button')), findsNothing);
      expect(find.byKey(const Key('delete_exec_photo_3')), findsNothing);
      final findings = tester.widget<TextField>(find.descendant(
          of: find.byKey(const Key('exec_findings_field')),
          matching: find.byType(TextField)));
      expect(findings.enabled, isFalse);
      // The saved work is still shown.
      expect(find.text('Relay burnt'), findsOneWidget);
      expect(find.text('217'), findsOneWidget);
    });

    testWidgets('the form fails closed when breakdown details cannot load',
        (tester) async {
      final api = _FakeExecApi()..breakdownInfo = null;
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const ComplaintExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('breakdown_info_card')), findsNothing);
      expect(find.byKey(const Key('submit_exec_button')), findsOneWidget);
    });

    testWidgets('Sign & Submit signs with the Technician Name typed',
        (tester) async {
      final api = _FakeExecApi()
        ..complaint = const ComplaintExecution(
          id: 9,
          initialFindings: 'Relay burnt',
          actionTaken: 'Replaced relay',
          finalRemarks: 'Tested OK',
          photos: [
            ExecutionPhoto(id: 1, kind: 'BEFORE'),
            ExecutionPhoto(id: 2, kind: 'AFTER'),
          ],
        );
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const ComplaintExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('exec_technician_name_field')), 'thamizh');
      final submit = find.byKey(const Key('submit_exec_button'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('confirm_submit_complaint_execution')));
      await tester.pumpAndSettle();

      expect(api.complaintSubmissions.single['technician_name'], 'thamizh');
    });

    testWidgets('Final Remarks come after the photos, as on the web',
        (tester) async {
      final api = _FakeExecApi();
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const ComplaintExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      final photosY = tester.getTopLeft(find.text('Before / After Photos')).dy;
      final remarksY =
          tester.getTopLeft(find.byKey(const Key('exec_remarks_field'))).dy;
      final paramsY =
          tester.getTopLeft(find.text('Technical Parameters (Optional)')).dy;
      expect(paramsY, lessThan(photosY));
      expect(remarksY, greaterThan(photosY));
      expect(find.text('No parameters applicable to this breakdown.'),
          findsOneWidget);
    });

    testWidgets('Sign & Submit without Before/After photos is blocked',
        (tester) async {
      final api = _FakeExecApi()
        ..complaint = const ComplaintExecution(
          id: 9,
          initialFindings: 'Relay burnt',
          actionTaken: 'Replaced relay',
          finalRemarks: 'Tested OK',
        );
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const ComplaintExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      final submit = find.byKey(const Key('submit_exec_button'));
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.textContaining('Before and an After photo'), findsOneWidget);
    });

    testWidgets('InspectionExecutionScreen renders one card per point',
        (tester) async {
      final api = _FakeExecApi()
        ..inspection = const PointwiseInspectionExecution(points: [
          InspectionPointExecutionEntry(
            pointJobWorkId: 11,
            pointNumber: 1,
            observation: 'Loose bolt',
          ),
          InspectionPointExecutionEntry(
            pointJobWorkId: 12,
            pointNumber: 2,
            observation: 'Cracked insulator',
          ),
        ]);
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const InspectionExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('insp_exec_point_11')), findsOneWidget);
      expect(find.byKey(const Key('insp_exec_point_12')), findsOneWidget);
      expect(find.text('Loose bolt'), findsOneWidget);
    });

    testWidgets(
        'InspectionExecutionScreen shows the inspector\'s photos read-only',
        (tester) async {
      final api = _FakeExecApi()
        ..inspection = const PointwiseInspectionExecution(
          generalEvidencePhotos: [
            ExecutionPhoto(id: 31, url: 'https://backend.example/media/g.jpg'),
          ],
          points: [
            InspectionPointExecutionEntry(
              pointJobWorkId: 11,
              pointNumber: 1,
              observation: 'Loose bolt',
              inspectionEvidencePhotos: [
                ExecutionPhoto(id: 32, url: 'https://backend.example/media/p.jpg'),
              ],
            ),
            InspectionPointExecutionEntry(
              pointJobWorkId: 12,
              pointNumber: 2,
              observation: 'Cracked insulator',
            ),
          ],
        );
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const InspectionExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('insp_exec_general_evidence')), findsOneWidget);
      expect(find.byKey(const Key('inspector_photo_31')), findsOneWidget);
      expect(find.byKey(const Key('insp_exec_inspector_photos_11')),
          findsOneWidget);
      expect(find.byKey(const Key('insp_exec_inspector_photos_12')),
          findsNothing);
      expect(find.byKey(const Key('inspector_photo_32')), findsOneWidget);
    });

    testWidgets('RectificationExecutionScreen renders an item per deficiency',
        (tester) async {
      final api = _FakeExecApi()
        ..rectification = const RectificationPayload(
          editable: true,
          items: [
            RectificationItem(id: 21, asset: 'TR-01', finding: 'Oil leak'),
            RectificationItem(id: 22, asset: 'TR-02', finding: 'Rust'),
          ],
        );
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const RectificationExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rect_item_card_21')), findsOneWidget);
      expect(find.byKey(const Key('rect_item_card_22')), findsOneWidget);
    });

    testWidgets(
        'RectificationExecutionScreen shows the checklist evidence read-only',
        (tester) async {
      final api = _FakeExecApi()
        ..rectification = const RectificationPayload(
          editable: true,
          items: [
            RectificationItem(
              id: 21,
              asset: 'TR-01',
              finding: 'Oil leak',
              sourcePhotos: [
                ExecutionPhoto(
                    id: 71,
                    kind: 'BEFORE',
                    url: 'https://backend.example/media/maintenance_line_evidence/f.jpg',
                    locked: true),
              ],
            ),
            RectificationItem(id: 22, asset: 'TR-02', finding: 'Rust'),
          ],
        );
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const RectificationExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rect_source_photos_21')), findsOneWidget);
      expect(find.byKey(const Key('inspector_photo_71')), findsOneWidget);
      expect(find.byKey(const Key('rect_source_photos_22')), findsNothing);
    });

    testWidgets('users without maintenance.edit see PermissionDeniedView',
        (tester) async {
      final api = _FakeExecApi();
      const perms = ['maintenance.view'];
      for (final screen in <Widget>[
        const ComplaintExecutionScreen(workOrderId: 7),
        const InspectionExecutionScreen(workOrderId: 7),
        const RectificationExecutionScreen(workOrderId: 7),
      ]) {
        _tallSurface(tester);
        await tester.pumpWidget(_harness(screen, api, permissions: perms));
        await tester.pumpAndSettle();
        expect(find.byType(PermissionDeniedView), findsOneWidget);
      }
    });

    testWidgets(
        'ComplaintExecutionScreen enforces ISO 55000 fields for CRITICAL assets',
        (tester) async {
      final api = _FakeExecApi()
        ..complaint = const ComplaintExecution(
          id: 10,
          initialFindings: 'Burnt terminal',
          actionTaken: 'Replaced terminal',
          finalRemarks: 'Restored service',
          assetCriticality: 'CRITICAL',
          requiresFailureDetails: true,
          failureCode: null,
          restoredTime: null,
          failureCodeOptions: [
            FailureCodeOption(
                id: 42, code: 'ELEC-42', description: 'Terminal failure'),
          ],
          photos: [
            ExecutionPhoto(id: 1, kind: 'BEFORE'),
            ExecutionPhoto(id: 2, kind: 'AFTER'),
          ],
        );
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const ComplaintExecutionScreen(workOrderId: 7), api),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('iso55000_mandatory_badge')), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);

      // Attempt submit without failure code or restored time
      final submitBtn = find.byKey(const Key('submit_exec_button'));
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Failure Code is mandatory for Critical Asset'),
        findsOneWidget,
      );
      expect(api.complaintSubmissions, isEmpty);

      // Now pick failure code
      final dropdown = find.byKey(const Key('failure_code_dropdown'));
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ELEC-42: Terminal failure').last,
          warnIfMissed: false);
      await tester.pumpAndSettle();

      // Tap Set to Now
      final setToNow = find.byKey(const Key('set_to_now_button'));
      await tester.ensureVisible(setToNow);
      await tester.tap(setToNow);
      await tester.pumpAndSettle();

      // Submit again
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      final confirmBtn =
          find.byKey(const Key('confirm_submit_complaint_execution'));
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(api.complaintSubmissions, hasLength(1));
      expect(api.complaintSubmissions.single['failure_code'], 42);
      expect(api.complaintSubmissions.single['restored_time'], isNotNull);
    });

    testWidgets(
        'RectificationExecutionScreen enforces ISO 55000 fields for HIGH criticality assets',
        (tester) async {
      final api = _FakeExecApi()
        ..rectification = const RectificationPayload(
          editable: true,
          workOrderId: 20,
          assetCriticality: 'HIGH',
          requiresFailureDetails: true,
          failureCode: null,
          restoredTime: null,
          failureCodeOptions: [
            FailureCodeOption(
                id: 77, code: 'DEF-77', description: 'Deficiency code'),
          ],
          finalRemarks: 'Fixed all points',
          items: [
            RectificationItem(
              id: 31,
              asset: 'CB-01',
              finding: 'Rust',
              actionTaken: 'Repainted',
              outcome: 'RECTIFIED',
              photos: [
                ExecutionPhoto(id: 1, kind: 'BEFORE'),
                ExecutionPhoto(id: 2, kind: 'AFTER'),
              ],
            ),
          ],
        );
      _tallSurface(tester);
      await tester.pumpWidget(
        _harness(const RectificationExecutionScreen(workOrderId: 20), api),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('iso55000_mandatory_badge')), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);

      // Attempt submit without failure code / restored time
      final submitBtn = find.byKey(const Key('submit_rect_button'));
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Failure Code is mandatory for Critical Asset'),
        findsOneWidget,
      );
      expect(api.rectificationSubmissions, isEmpty);

      // Pick failure code
      final dropdown = find.byKey(const Key('failure_code_dropdown'));
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('DEF-77: Deficiency code').last,
          warnIfMissed: false);
      await tester.pumpAndSettle();

      // Tap Set to Now
      final setToNow = find.byKey(const Key('set_to_now_button'));
      await tester.ensureVisible(setToNow);
      await tester.tap(setToNow);
      await tester.pumpAndSettle();

      // Submit again
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      final confirmBtn = find.byKey(const Key('confirm_submit_rectification'));
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(api.rectificationSubmissions, hasLength(1));
      expect(api.rectificationSubmissions.single['failure_code'], 77);
      expect(api.rectificationSubmissions.single['restored_time'], isNotNull);
    });
  });
}
