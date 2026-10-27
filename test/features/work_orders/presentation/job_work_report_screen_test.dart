// ignore_for_file: prefer_const_literals_to_create_immutables

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/data/job_work_report_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/job_work_report_screen.dart';
import 'package:mocktail/mocktail.dart';

import 'package:printing/printing.dart';

import '../../../helpers/fake_auth.dart';

class _MockRepo extends Mock implements JobWorkReportRepository {}

WorkOrder _wo({
  WorkOrderStatus status = WorkOrderStatus.techCompleted,
  int? assignedToId = 9,
}) =>
    WorkOrder(
      id: 101,
      status: status,
      type: WorkOrderType.preventive,
      title: 'Monthly PM',
      assignedToId: assignedToId,
      assignedToName: 'tech_ramesh',
    );

UserSession _tech({int? userId = 9}) => fakeSession(
      role: AuthRole.maintenanceStaff,
      permissions: const ['maintenance.view', 'maintenance.edit'],
      userId: userId,
    );

Future<void> _pump(
  WidgetTester tester,
  _MockRepo repo, {
  UserSession? session,
  WorkOrder? wo,
  JobWorkReportPreviewBuilder? previewBuilder,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jobWorkReportRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(
            () => FakeAuthenticatedController(session ?? _tech())),
        jobWorkReportPreviewBuilderProvider.overrideWithValue(
          previewBuilder ??
              (context, {required loaded, required getPdfBytes, required fileName}) {
                return KeyedSubtree(
                  key: const Key('job_work_report_pdf_preview'),
                  child: JobWorkReportBody(loaded: loaded),
                );
              },
        ),
      ],
      child: MaterialApp(
        home: JobWorkReportScreen(workOrder: wo ?? _wo()),
      ),
    ),
  );
}

LoadedJobWorkReport _loaded(JobWorkReport r) =>
    LoadedJobWorkReport(report: r, photos: const <String, Uint8List?>{});

ChecklistJobWorkReport _checklist({bool withLine = true}) {
  final record = <String, dynamic>{
    'technician_name': 'Ramesh',
    'remarks': 'All good',
    'lines': withLine
        ? [
            {
              'asset_unique_id': 'AST-1',
              'item_name': 'Pump',
              'inspection_point': 'Leak check',
              'status': 'NOT_OK',
              'status_label_snapshot': 'Not OK',
              'action_label_snapshot': 'Replace',
              'status_option': 1,
              'action_option': 2,
              'status_options': [
                {
                  'id': 1,
                  'label': 'Not OK',
                  'is_deficiency': true,
                  'action_options': [
                    {'id': 2, 'label': 'Replace'}
                  ],
                }
              ],
            }
          ]
        : [],
  };
  return ChecklistJobWorkReport.fromRecordJson(record, _wo());
}

void main() {
  late _MockRepo repo;
  setUpAll(() => registerFallbackValue(_wo()));
  setUp(() => repo = _MockRepo());

  testWidgets('checklist: loading then loaded, actions enabled after load',
      (tester) async {
    when(() => repo.load(any()))
        .thenAnswer((_) async => _loaded(_checklist()));
    await _pump(tester, repo);

    // Before load completes: disabled.
    FilledButton print() =>
        tester.widget<FilledButton>(find.byKey(const Key('job_work_report_print')));
    OutlinedButton share() => tester
        .widget<OutlinedButton>(find.byKey(const Key('job_work_report_share')));
    expect(print().onPressed, isNull);
    expect(share().onPressed, isNull);
    expect(find.textContaining('Loading report'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Preventive Maintenance Report'), findsOneWidget);
    expect(find.text('Deficiency Summary'), findsOneWidget);
    expect(find.text('Pending verification'), findsOneWidget);
    expect(print().onPressed, isNotNull);
    expect(share().onPressed, isNotNull);
  });

  testWidgets('breakdown report renders its title', (tester) async {
    final r = ComplaintJobWorkReport.fromJson(
      {'submission_history': const []},
      {'ticket_number': 'JW-1', 'title': 'Fix fan', 'asset_name': 'Fan'},
    );
    when(() => repo.load(any())).thenAnswer((_) async => _loaded(r));
    await _pump(tester, repo);
    await tester.pumpAndSettle();
    expect(find.text('Breakdown Job Work Report'), findsOneWidget);
    expect(find.text('1. Job Work Details'), findsOneWidget);
  });

  testWidgets('inspection report renders its title', (tester) async {
    final r = InspectionJobWorkReport.fromJson(
      {'ticket_number': 'JW-2'},
      fallbackTicket: 'JW-2',
    );
    when(() => repo.load(any())).thenAnswer((_) async => _loaded(r));
    await _pump(tester, repo);
    await tester.pumpAndSettle();
    expect(find.text('Inspection Job Work Report'), findsOneWidget);
  });

  testWidgets('rectification report renders its title and summary',
      (tester) async {
    final r = RectificationJobWorkReport.fromJson({
      'ticket_number': 'JW-3',
      'items': [
        {'asset': 'Lamp', 'outcome': 'RECTIFIED'}
      ],
    });
    when(() => repo.load(any())).thenAnswer((_) async => _loaded(r));
    await _pump(tester, repo);
    await tester.pumpAndSettle();
    expect(find.text('Deficiency Rectification Report'), findsOneWidget);
    expect(find.text('1 item · 1 rectified · 0 not rectified'),
        findsOneWidget);
  });

  testWidgets('error shows Retry which reloads', (tester) async {
    var calls = 0;
    when(() => repo.load(any())).thenAnswer((_) async {
      calls++;
      if (calls == 1) throw Exception('boom');
      return _loaded(_checklist());
    });
    await _pump(tester, repo);
    await tester.pumpAndSettle();
    expect(find.text('Could not load this report'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('job_work_report_print')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Preventive Maintenance Report'), findsOneWidget);
  });

  testWidgets('empty checklist shows no-details state and disables actions',
      (tester) async {
    when(() => repo.load(any()))
        .thenAnswer((_) async => _loaded(_checklist(withLine: false)));
    await _pump(tester, repo);
    await tester.pumpAndSettle();
    expect(find.text('No details available for this report.'),
        findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('job_work_report_print')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('non-technician session sees PermissionDeniedView',
      (tester) async {
    await _pump(tester, repo,
        session: fakeSession(role: AuthRole.depotIncharge, userId: 9));
    await tester.pumpAndSettle();
    expect(find.byType(PermissionDeniedView), findsOneWidget);
    verifyNever(() => repo.load(any()));
  });

  group('canShow', () {
    test('wrong role is false', () {
      expect(
        JobWorkReportScreen.canShow(
            _wo(), fakeSession(role: AuthRole.depotIncharge, userId: 9)),
        isFalse,
      );
    });
    test('in-progress is false', () {
      expect(
        JobWorkReportScreen.canShow(
            _wo(status: WorkOrderStatus.inProgress), _tech()),
        isFalse,
      );
    });
    test('assigned to someone else is false', () {
      expect(JobWorkReportScreen.canShow(_wo(assignedToId: 4), _tech()),
          isFalse);
    });
    test('null userId is false', () {
      expect(JobWorkReportScreen.canShow(_wo(), _tech(userId: null)), isFalse);
    });
    test('null session is false', () {
      expect(JobWorkReportScreen.canShow(_wo(), null), isFalse);
    });
    test('cancelled and assigned to me is true', () {
      expect(
        JobWorkReportScreen.canShow(
            _wo(status: WorkOrderStatus.cancelled), _tech()),
        isTrue,
      );
    });
  });

  group('preview builder', () {
    testWidgets('default builder provides PdfPreview widget', (tester) async {
      late Widget built;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                final builder = ref.watch(jobWorkReportPreviewBuilderProvider);
                built = builder(
                  context,
                  loaded: _loaded(_checklist()),
                  getPdfBytes: () async => Uint8List(0),
                  fileName: 'JobWork-Test.pdf',
                );
                return built;
              },
            ),
          ),
        ),
      );
      expect(built, isA<PdfPreview>());
      expect(find.byType(PdfPreview), findsOneWidget);
    });

    testWidgets('passes loaded data, filename and non-empty pdf bytes',
        (tester) async {
      LoadedJobWorkReport? capturedLoaded;
      String? capturedFileName;
      Uint8List? capturedBytes;

      when(() => repo.load(any()))
          .thenAnswer((_) async => _loaded(_checklist()));

      await _pump(
        tester,
        repo,
        previewBuilder:
            (context, {required loaded, required getPdfBytes, required fileName}) {
          capturedLoaded = loaded;
          capturedFileName = fileName;
          return Builder(
            builder: (ctx) {
              return TextButton(
                key: const Key('fetch_bytes_btn'),
                onPressed: () async {
                  capturedBytes = await getPdfBytes();
                },
                child: const Text('Fetch PDF'),
              );
            },
          );
        },
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fetch_bytes_btn')), findsOneWidget);
      expect(capturedLoaded, isNotNull);
      expect(capturedFileName, 'JobWork-WO__101-Verification.pdf');

      await tester.tap(find.byKey(const Key('fetch_bytes_btn')));
      await tester.pumpAndSettle();

      expect(capturedBytes, isNotNull);
      expect(capturedBytes!.isNotEmpty, isTrue);
    });
  });
}

