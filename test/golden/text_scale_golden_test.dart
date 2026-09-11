import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/data/asset_repository.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/assets/presentation/controllers/asset_controllers.dart';
import 'package:gssms_mobile/features/assets/presentation/screens/asset_list_screen.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/complaints/data/complaint_repository.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_list_screen.dart';
import 'package:gssms_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:gssms_mobile/features/inspections/data/inspection_repository.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_list_screen.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_list_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fake_auth.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}
class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}
class MockComplaintRepository extends Mock implements IComplaintRepository {}
class MockInspectionRepository extends Mock implements IInspectionRepository {}
class MockAssetRepository extends Mock implements IAssetRepository {}

/// Text-scale layout-tolerance harness (P1-8).
///
/// Tests all seven main screens across textScaler 1.0, 1.3, and 1.5
/// to ensure no RenderFlex layout overflows occur even at maximum accessibility scales.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const scales = [1.0, 1.3, 1.5];

  const testOrders = [
    WorkOrder(
      id: 101,
      status: WorkOrderStatus.assigned,
      type: WorkOrderType.preventive,
      title: 'Monthly Transformer Inspection',
      assetName: 'TR-01',
      stationName: 'VRI',
      assignedToName: 'tech_ramesh',
    ),
  ];

  const testRecord = MaintenanceRecord(
    id: 23,
    workOrderId: 101,
    lines: [
      MaintenanceRecordLine(
        id: 1,
        itemName: 'Check Transformer Oil Level',
        assetCategory: 'Category',
      ),
    ],
  );

  const testAudit = WorkOrderAudit(
    workOrderId: 101,
    ticketNumber: 'VRI-202608-0001',
    events: [
      WorkOrderAuditEvent(
        eventId: 'e1',
        eventType: 'STATUS_CHANGE',
        fromState: 'NEW',
        toState: 'ASSIGNED',
        actor: 'incharge_kumar',
        actorRole: 'DEPOT_INCHARGE',
      ),
    ],
  );

  const testActionSet = WorkOrderActionSet(
    workOrderId: 101,
    currentStatus: 'ASSIGNED',
    allowed: [
      WorkOrderAction(
        targetStatus: 'IN_PROGRESS',
        label: 'Start',
        enabled: true,
      ),
    ],
  );

  const testComplaints = [
    Complaint(
      id: 1,
      complaintNumber: 'CMP-001',
      title: 'Transformer Leakage',
      description: 'Oil leaking near base valve',
      severity: ComplaintSeverity.high,
      status: ComplaintStatus.open,
      stationName: 'VRI',
    ),
  ];

  const testInspections = [
    Inspection(
      id: 1,
      inspectionNumber: 'INSP-001',
      title: 'EB Bunk Monthly Check',
      notes: 'Earth resistance and cleaning',
      priority: InspectionPriority.high,
      status: InspectionStatus.open,
      stationName: 'Thalanallur',
    ),
  ];

  const testAssets = [
    Asset(
      id: 42,
      uniqueId: 'VRI-STN-CLS-MAIN-001',
      assetTypeName: 'Main Panel',
      assetCategoryName: 'CLS Panels',
      criticality: AssetCriticality.critical,
      stationName: 'VRI',
      make: 'SUNTRON',
    ),
  ];

  group('HomeScreen layout scaling', () {
    for (final scale in scales) {
      testWidgets('home_screen textScaler $scale', (tester) async {
        await _setSurface(tester, const Size(400, 800));
        await _pumpHome(tester, scale);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ChecklistScreen layout scaling', () {
    for (final scale in scales) {
      testWidgets('checklist_screen textScaler $scale', (tester) async {
        await _setSurface(tester, const Size(400, 800));
        final mockRepo = MockWorkOrderRepository();
        when(() => mockRepo.fetchMaintenanceRecord(23))
            .thenAnswer((_) async => testRecord);

        await _pumpChecklist(tester, scale, mockRepo: mockRepo);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('WorkOrderListScreen layout scaling', () {
    for (final scale in scales) {
      testWidgets('work_order_list_screen textScaler $scale', (tester) async {
        await _setSurface(tester, const Size(400, 800));
        final mockRepo = MockWorkOrderRepository();
        when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => testOrders);

        await _pumpWithScaler(
          tester,
          scale: scale,
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(permissions: const ['*'])),
            ),
          ],
          child: const WorkOrderListScreen(),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('WorkOrderDetailScreen layout scaling', () {
    for (final scale in scales) {
      testWidgets('work_order_detail_screen textScaler $scale', (tester) async {
        await _setSurface(tester, const Size(400, 800));
        final mockRepo = MockWorkOrderRepository();
        when(() => mockRepo.fetchWorkOrderById(101)).thenAnswer((_) async => testOrders.first);
        when(() => mockRepo.fetchAllowedActions(101)).thenAnswer((_) async => testActionSet);
        when(() => mockRepo.fetchAudit(101)).thenAnswer((_) async => testAudit);

        await _pumpWithScaler(
          tester,
          scale: scale,
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(permissions: const ['*'])),
            ),
          ],
          child: const WorkOrderDetailScreen(workOrderId: 101),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ComplaintListScreen layout scaling', () {
    for (final scale in scales) {
      testWidgets('complaint_list_screen textScaler $scale', (tester) async {
        await _setSurface(tester, const Size(400, 800));
        final mockRepo = MockComplaintRepository();
        when(() => mockRepo.fetchComplaints()).thenAnswer((_) async => testComplaints);

        await _pumpWithScaler(
          tester,
          scale: scale,
          overrides: [
            complaintRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(permissions: const ['*'])),
            ),
          ],
          child: const ComplaintListScreen(),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('InspectionListScreen layout scaling', () {
    for (final scale in scales) {
      testWidgets('inspection_list_screen textScaler $scale', (tester) async {
        await _setSurface(tester, const Size(400, 800));
        final mockRepo = MockInspectionRepository();
        when(() => mockRepo.fetchInspections()).thenAnswer((_) async => testInspections);

        await _pumpWithScaler(
          tester,
          scale: scale,
          overrides: [
            inspectionRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(permissions: const ['*'])),
            ),
          ],
          child: const InspectionListScreen(),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('AssetListScreen layout scaling', () {
    for (final scale in scales) {
      testWidgets('asset_list_screen textScaler $scale', (tester) async {
        await _setSurface(tester, const Size(400, 800));
        final mockRepo = MockAssetRepository();
        when(() => mockRepo.fetchAssets(
          zoneId: any(named: 'zoneId'),
          divisionId: any(named: 'divisionId'),
          depotId: any(named: 'depotId'),
          stationId: any(named: 'stationId'),
        )).thenAnswer(
          (_) async => const AssetPage(assets: testAssets, truncated: false),
        );

        await _pumpWithScaler(
          tester,
          scale: scale,
          overrides: [
            assetRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(permissions: const ['*'])),
            ),
          ],
          child: const AssetListScreen(),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpWithScaler(
  WidgetTester tester, {
  required Widget child,
  required double scale,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheServiceProvider.overrideWithValue(InMemoryLocalCacheService()),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, c) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: c!,
          );
        },
        home: child,
      ),
    ),
  );
}

Future<void> _pumpHome(WidgetTester tester, double scale) async {
  const session = UserSession(
    accessToken: 'super_token',
    username: 'super_admin_user',
    firstName: 'System',
    lastName: 'Administrator',
    primaryRole: AuthRole.superAdmin,
    roles: [AuthRole.superAdmin],
    permissions: ['*'],
    scope: OrgScope(level: OrgScopeLevel.global),
  );

  final mockWorkOrderRepo = MockWorkOrderRepository();
  final mockAssetRepo = MockAssetRepository();
  when(() => mockWorkOrderRepo.fetchWorkOrders())
      .thenAnswer((_) async => const <WorkOrder>[]);
  when(() => mockAssetRepo.fetchAssets(
    zoneId: any(named: 'zoneId'),
    divisionId: any(named: 'divisionId'),
    depotId: any(named: 'depotId'),
    stationId: any(named: 'stationId'),
  )).thenAnswer(
    (_) async => const AssetPage(assets: [], truncated: false),
  );

  await _pumpWithScaler(
    tester,
    scale: scale,
    overrides: [
      authRepositoryProvider.overrideWithValue(MockAuthRepository()),
      workOrderRepositoryProvider.overrideWithValue(mockWorkOrderRepo),
      assetRepositoryProvider.overrideWithValue(mockAssetRepo),
      authControllerProvider.overrideWith(
        () => FakeAuthenticatedController(session),
      ),
    ],
    child: const HomeScreen(session: session),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpChecklist(
  WidgetTester tester,
  double scale, {
  required MockWorkOrderRepository mockRepo,
}) async {
  await _pumpWithScaler(
    tester,
    scale: scale,
    overrides: [
      workOrderRepositoryProvider.overrideWithValue(mockRepo),
      authControllerProvider.overrideWith(
        () => FakeAuthenticatedController(
          fakeSession(role: AuthRole.maintenanceStaff, permissions: const ['*']),
        ),
      ),
    ],
    child: const ChecklistScreen(recordId: 23),
  );
}
