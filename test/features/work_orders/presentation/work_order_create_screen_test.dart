import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/data/org_scope_options_service.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/reports/data/infrastructure_options_service.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_master.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_create_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}
class MockOrgScopeOptionsService extends Mock implements OrgScopeOptionsService {}
class MockInfraOptionsService extends Mock implements InfrastructureOptionsService {}
class MockAssetApiService extends Mock implements AssetApiService {}

class _FakeAuth extends AuthController {
  _FakeAuth(this._s);
  final UserSession _s;
  @override
  AuthState build() => Authenticated(_s);
}

const _session = UserSession(
  accessToken: 't',
  username: 'depot_incharge',
  firstName: 'Vri',
  lastName: '',
  primaryRole: AuthRole.depotIncharge,
  roles: [AuthRole.depotIncharge],
  permissions: ['maintenance.view', 'maintenance.create'],
  scope: OrgScope(level: OrgScopeLevel.depot, depot: OrgUnitInfo(id: 23, name: 'Vriddhachalam Depot')),
  depotId: 23,
  depotName: 'Vriddhachalam Depot',
);

void main() {
  setUpAll(() {
    registerFallbackValue(InfraFilterType.station);
  });

  testWidgets('WorkOrderCreateScreen validates title and submits with checklist', (tester) async {
    final mockRepo = MockWorkOrderRepository();
    final mockOrg = MockOrgScopeOptionsService();
    final mockInfra = MockInfraOptionsService();
    final mockAssets = MockAssetApiService();

    const testMaster = MaintenanceMaster(
      id: 5,
      name: 'Basic Checklist',
      scheduleType: MaintenanceScheduleType.monthly,
      templateKind: MaintenanceTemplateKind.assetTemplate,
    );

    when(() => mockInfra.fetchOptions(any(), depotId: any(named: 'depotId')))
        .thenAnswer((_) async => const []);
    when(() => mockRepo.fetchMaintenanceMasters())
        .thenAnswer((_) async => const [testMaster]);
    when(() => mockRepo.createWorkOrder(
          title: any(named: 'title'),
          description: any(named: 'description'),
          type: any(named: 'type'),
          priority: any(named: 'priority'),
          depotId: any(named: 'depotId'),
          stationId: any(named: 'stationId'),
          infrastructureId: any(named: 'infrastructureId'),
          assetId: any(named: 'assetId'),
          scheduledDate: any(named: 'scheduledDate'),
          maintenanceMasterId: any(named: 'maintenanceMasterId'),
        )).thenAnswer((_) async => const WorkOrder(
          id: 202,
          status: WorkOrderStatus.newOrder,
          type: WorkOrderType.preventive,
          title: 'Station monthly maintenance',
        ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderRepositoryProvider.overrideWithValue(mockRepo),
          authControllerProvider.overrideWith(() => _FakeAuth(_session)),
          orgScopeOptionsServiceProvider.overrideWithValue(mockOrg),
          infrastructureOptionsServiceProvider.overrideWithValue(mockInfra),
          assetApiServiceProvider.overrideWithValue(mockAssets),
        ],
        child: const MaterialApp(home: WorkOrderCreateScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New Job Work'), findsWidgets);
    expect(find.byKey(const Key('wo_title_field')), findsOneWidget);
    expect(find.byKey(const Key('wo_type_dropdown')), findsOneWidget);
    expect(find.byKey(const Key('submit_wo_button')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('submit_wo_button')));
    await tester.tap(find.byKey(const Key('submit_wo_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a title'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('wo_title_field')), 'Station monthly maintenance');
    // Need to select a checklist before submitting (required for Preventive)
    await tester.ensureVisible(find.byKey(const Key('wo_template_dropdown')));
    await tester.tap(find.byKey(const Key('wo_template_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basic Checklist (Monthly)'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('submit_wo_button')));
    await tester.tap(find.byKey(const Key('submit_wo_button')));
    await tester.pumpAndSettle();

    verify(() => mockRepo.createWorkOrder(
          title: 'Station monthly maintenance',
          description: any(named: 'description'),
          type: 'PREVENTIVE',
          priority: 'MEDIUM',
          depotId: 23,
          stationId: null,
          infrastructureId: null,
          assetId: null,
          scheduledDate: null,
          maintenanceMasterId: 5,
        )).called(1);
  });

  testWidgets('AMC checklist renders under its own segment, not Asset',
      (tester) async {
    const assetMaster = MaintenanceMaster(
      id: 11,
      name: 'Panel Monthly',
      scheduleType: MaintenanceScheduleType.monthly,
      templateKind: MaintenanceTemplateKind.assetTemplate,
    );
    const amcMaster = MaintenanceMaster(
      id: 12,
      name: 'DG Set AMC',
      scheduleType: MaintenanceScheduleType.quarterly,
      templateKind: MaintenanceTemplateKind.amc,
    );

    final mockRepo = MockWorkOrderRepository();
    final mockOrg = MockOrgScopeOptionsService();
    final mockInfra = MockInfraOptionsService();
    final mockAssets = MockAssetApiService();

    when(() => mockInfra.fetchOptions(any(), depotId: any(named: 'depotId')))
        .thenAnswer((_) async => const []);
    when(() => mockRepo.fetchMaintenanceMasters())
        .thenAnswer((_) async => const [assetMaster, amcMaster]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderRepositoryProvider.overrideWithValue(mockRepo),
          authControllerProvider.overrideWith(() => _FakeAuth(_session)),
          orgScopeOptionsServiceProvider.overrideWithValue(mockOrg),
          infrastructureOptionsServiceProvider.overrideWithValue(mockInfra),
          assetApiServiceProvider.overrideWithValue(mockAssets),
        ],
        child: const MaterialApp(home: WorkOrderCreateScreen()),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openTemplateMenu() async {
      await tester.ensureVisible(find.byKey(const Key('wo_template_dropdown')));
      await tester.tap(find.byKey(const Key('wo_template_dropdown')));
      await tester.pumpAndSettle();
    }

    // Default Asset segment: the AMC checklist must not hide here.
    await openTemplateMenu();
    expect(find.text('Panel Monthly (Monthly)'), findsOneWidget);
    expect(find.text('DG Set AMC (Quarterly)'), findsNothing);

    // Dismiss the dropdown menu first by tapping barrier / outside
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Scroll AMC into view inside its horizontal scroll view
    await tester.scrollUntilVisible(
      find.text('AMC'),
      50,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('AMC'));
    await tester.pumpAndSettle();

    // AMC segment: the AMC checklist renders here, the asset one does not.
    await openTemplateMenu();
    expect(find.text('DG Set AMC (Quarterly)'), findsOneWidget);
    expect(find.text('Panel Monthly (Monthly)'), findsNothing);
  });


  testWidgets('WorkOrderCreateScreen restricts types, shows hints, and validates checklist for Preventive', (tester) async {
    final mockRepo = MockWorkOrderRepository();
    final mockOrg = MockOrgScopeOptionsService();
    final mockInfra = MockInfraOptionsService();
    final mockAssets = MockAssetApiService();

    const testMaster = MaintenanceMaster(
      id: 10,
      name: 'Ad-hoc PM Checklist',
      scheduleType: MaintenanceScheduleType.monthly,
      templateKind: MaintenanceTemplateKind.assetTemplate,
    );

    when(() => mockInfra.fetchOptions(any(), depotId: any(named: 'depotId')))
        .thenAnswer((_) async => const []);
    when(() => mockRepo.fetchMaintenanceMasters())
        .thenAnswer((_) async => const [testMaster]);
    when(() => mockRepo.createWorkOrder(
          title: any(named: 'title'),
          description: any(named: 'description'),
          type: any(named: 'type'),
          priority: any(named: 'priority'),
          depotId: any(named: 'depotId'),
          stationId: any(named: 'stationId'),
          infrastructureId: any(named: 'infrastructureId'),
          assetId: any(named: 'assetId'),
          scheduledDate: any(named: 'scheduledDate'),
          maintenanceMasterId: any(named: 'maintenanceMasterId'),
        )).thenAnswer((_) async => const WorkOrder(
          id: 303,
          status: WorkOrderStatus.newOrder,
          type: WorkOrderType.preventive,
          title: 'Ad-hoc PM',
        ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderRepositoryProvider.overrideWithValue(mockRepo),
          authControllerProvider.overrideWith(() => _FakeAuth(_session)),
          orgScopeOptionsServiceProvider.overrideWithValue(mockOrg),
          infrastructureOptionsServiceProvider.overrideWithValue(mockInfra),
          assetApiServiceProvider.overrideWithValue(mockAssets),
        ],
        child: const MaterialApp(home: WorkOrderCreateScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 1. General breakdown hint is visible
    expect(find.text('Report breakdowns in the Breakdowns module.'), findsOneWidget);

    // 2. In PREVENTIVE mode: Checklist header is required with asterisk and web helper text
    expect(find.text('Checklist *'), findsOneWidget);
    expect(
        find.text(
            'Maintenance checklist to attach — determines what the technician is asked to fill in when closing the job work. Scheduled PM is created from Schedules → Convert.'),
        findsOneWidget);
    expect(find.text('Filter by schedule type'), findsOneWidget);

    // 3. Open type dropdown and verify only Preventive is offered
    await tester.tap(find.byKey(const Key('wo_type_dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Preventive Maintenance'), findsOneWidget);
    expect(find.text('Corrective Maintenance'), findsNothing);
    expect(find.text('Breakdown'), findsNothing);
    expect(find.text('Calibration'), findsNothing);
    expect(find.text('Installation'), findsNothing);

    // 4. Attempt submit without checklist -> rejected with snackbar
    await tester.enterText(find.byKey(const Key('wo_title_field')), 'Ad-hoc PM');
    await tester.ensureVisible(find.byKey(const Key('submit_wo_button')));
    await tester.tap(find.byKey(const Key('submit_wo_button')));
    await tester.pumpAndSettle();
    expect(find.text('A Preventive Job Work needs a checklist.'), findsOneWidget);
    // Verify createWorkOrder was never called
    verifyNever(() => mockRepo.createWorkOrder(
          title: any(named: 'title'),
          description: any(named: 'description'),
          type: any(named: 'type'),
          priority: any(named: 'priority'),
          depotId: any(named: 'depotId'),
          stationId: any(named: 'stationId'),
          infrastructureId: any(named: 'infrastructureId'),
          assetId: any(named: 'assetId'),
          scheduledDate: any(named: 'scheduledDate'),
          maintenanceMasterId: any(named: 'maintenanceMasterId'),
        ));

    // 5. Select a template and submit -> succeeds
    await tester.ensureVisible(find.byKey(const Key('wo_template_dropdown')));
    await tester.tap(find.byKey(const Key('wo_template_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ad-hoc PM Checklist (Monthly)').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('submit_wo_button')));
    await tester.tap(find.byKey(const Key('submit_wo_button')));
    await tester.pumpAndSettle();

    verify(() => mockRepo.createWorkOrder(
          title: 'Ad-hoc PM',
          description: any(named: 'description'),
          type: 'PREVENTIVE',
          priority: 'MEDIUM',
          depotId: 23,
          stationId: null,
          infrastructureId: null,
          assetId: null,
          scheduledDate: null,
          maintenanceMasterId: 10,
        )).called(1);
  });

  testWidgets('WorkOrderCreateScreen action buttons fit without overflow at 360dp width and 1.3 text scale', (tester) async {
    final mockRepo = MockWorkOrderRepository();
    final mockOrg = MockOrgScopeOptionsService();
    final mockInfra = MockInfraOptionsService();
    final mockAssets = MockAssetApiService();

    when(() => mockInfra.fetchOptions(any(), depotId: any(named: 'depotId')))
        .thenAnswer((_) async => const []);
    when(() => mockRepo.fetchMaintenanceMasters())
        .thenAnswer((_) async => const []);

    final originalOnError = FlutterError.onError;
    FlutterErrorDetails? caughtDetails;
    FlutterError.onError = (details) {
      caughtDetails = details;
    };
    addTearDown(() {
      FlutterError.onError = originalOnError;
    });

    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderRepositoryProvider.overrideWithValue(mockRepo),
          authControllerProvider.overrideWith(() => _FakeAuth(_session)),
          orgScopeOptionsServiceProvider.overrideWithValue(mockOrg),
          infrastructureOptionsServiceProvider.overrideWithValue(mockInfra),
          assetApiServiceProvider.overrideWithValue(mockAssets),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: const WorkOrderCreateScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify AppBar title is 'New Job Work'
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('New Job Work')), findsOneWidget);

    // Verify Action buttons are visible and did not overflow
    await tester.ensureVisible(find.byKey(const Key('submit_wo_button')));
    expect(find.byKey(const Key('cancel_wo_button')), findsOneWidget);
    expect(find.byKey(const Key('submit_wo_button')), findsOneWidget);
    expect(caughtDetails, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('S2: coded 409 directs preventive creates to schedule conversion',
      (tester) async {
    final mockRepo = MockWorkOrderRepository();
    final mockOrg = MockOrgScopeOptionsService();
    final mockInfra = MockInfraOptionsService();
    final mockAssets = MockAssetApiService();

    when(() => mockInfra.fetchOptions(any(), depotId: any(named: 'depotId')))
        .thenAnswer((_) async => const []);
    const conflictMaster = MaintenanceMaster(id: 5, name: 'Basic Checklist', scheduleType: MaintenanceScheduleType.monthly, templateKind: MaintenanceTemplateKind.assetTemplate);
    when(() => mockRepo.fetchMaintenanceMasters()).thenAnswer((_) async => const [conflictMaster]);
    DioException conflict409() {
      final options = RequestOptions(path: '/api/maintenance/work-orders/');
      return DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options,
          statusCode: 409,
          data: {
            'error':
                'Preventive maintenance for an assigned template must be created by converting its schedule.',
            'code': 'PM_USE_SCHEDULE_CONVERSION',
            'blocking_work_order': null,
            'pending_request': null,
          },
        ),
      );
    }

    when(() => mockRepo.createWorkOrder(
          title: any(named: 'title'),
          description: any(named: 'description'),
          type: any(named: 'type'),
          priority: any(named: 'priority'),
          depotId: any(named: 'depotId'),
          stationId: any(named: 'stationId'),
          infrastructureId: any(named: 'infrastructureId'),
          assetId: any(named: 'assetId'),
          scheduledDate: any(named: 'scheduledDate'),
          maintenanceMasterId: any(named: 'maintenanceMasterId'),
        )).thenThrow(conflict409());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderRepositoryProvider.overrideWithValue(mockRepo),
          authControllerProvider.overrideWith(() => _FakeAuth(_session)),
          orgScopeOptionsServiceProvider.overrideWithValue(mockOrg),
          infrastructureOptionsServiceProvider.overrideWithValue(mockInfra),
          assetApiServiceProvider.overrideWithValue(mockAssets),
        ],
        child: const MaterialApp(home: WorkOrderCreateScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('wo_title_field')), 'Station monthly maintenance');
    await tester.ensureVisible(find.byKey(const Key('wo_template_dropdown')));
    await tester.tap(find.byKey(const Key('wo_template_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basic Checklist (Monthly)').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('submit_wo_button')));
    await tester.tap(find.byKey(const Key('submit_wo_button')));
    await tester.pumpAndSettle();

    // No blind resubmit wording: the snackbar names the conversion path.
    expect(find.textContaining('Convert the due schedule'), findsOneWidget);
  });
}
