import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  @override
  Future<ComplaintExecution> saveComplaintDraft(
    int workOrderId,
    Map<String, dynamic> fields,
  ) async {
    complaintDraftSaves.add(fields);
    return complaint;
  }

  @override
  Future<ComplaintExecution> getComplaintExecution(int workOrderId) async =>
      complaint;

  @override
  Future<PointwiseInspectionExecution> initializeInspectionExecution(
          int workOrderId) async =>
      inspection;

  @override
  Future<RectificationPayload> getRectification(int workOrderId) async =>
      rectification;
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

      expect(api.complaintDraftSaves, hasLength(1));
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
  });
}
