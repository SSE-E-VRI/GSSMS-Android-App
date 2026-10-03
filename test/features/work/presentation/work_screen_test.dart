import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/data/lookup_options_service.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/complaints/data/complaint_repository.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/deficiencies/data/deficiency_repository.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';
import 'package:gssms_mobile/features/deficiencies/presentation/screens/deficiency_list_screen.dart';
import 'package:gssms_mobile/features/inspections/data/inspection_repository.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:gssms_mobile/features/reports/data/infrastructure_options_service.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:gssms_mobile/features/work/presentation/screens/work_screen.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fake_auth.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}
class MockComplaintRepository extends Mock implements IComplaintRepository {}
class MockInspectionRepository extends Mock implements IInspectionRepository {}
class MockDeficiencyRepository extends Mock implements IDeficiencyRepository {}
class MockLookupOptionsService extends Mock implements LookupOptionsService {}
class MockInfrastructureOptionsService extends Mock implements InfrastructureOptionsService {}

void main() {
  setUpAll(() {
    registerFallbackValue(InfraFilterType.station);
  });

  group('WorkScreen Widget Tests', () {
    late MockWorkOrderRepository mockWoRepo;
    late MockComplaintRepository mockComplaintRepo;
    late MockInspectionRepository mockInspectionRepo;
    late MockDeficiencyRepository mockDeficiencyRepo;
    late MockLookupOptionsService mockLookupService;
    late MockInfrastructureOptionsService mockInfraService;

    final testDeficiencies = [
      Deficiency(
        id: 1,
        code: 'DEF-001',
        description: 'Oil level below minimum mark',
        deficiencyFinding: 'Oil leak observed at main transformer valve',
        status: DeficiencyStatus.open,
        severityLabel: 'HIGH',
        assetId: 101,
        assetUniqueId: 'AST-VRI-01',
        equipmentName: 'Main Transformer',
        depotName: 'VRI Depot',
        detectedAt: DateTime(2026, 9, 15, 10, 30),
      ),
    ];

    setUp(() {
      mockWoRepo = MockWorkOrderRepository();
      mockComplaintRepo = MockComplaintRepository();
      mockInspectionRepo = MockInspectionRepository();
      mockDeficiencyRepo = MockDeficiencyRepository();
      mockLookupService = MockLookupOptionsService();
      mockInfraService = MockInfrastructureOptionsService();

      when(() => mockWoRepo.fetchWorkOrders()).thenAnswer((_) async => const <WorkOrder>[]);
      when(() => mockComplaintRepo.fetchComplaints()).thenAnswer((_) async => const <Complaint>[]);
      when(() => mockInspectionRepo.fetchInspections()).thenAnswer((_) async => const <Inspection>[]);
      when(() => mockDeficiencyRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);
    });

    Widget createTestWidget(
      UserSession session, {
      double textScale = 1.0,
    }) {
      return ProviderScope(
        overrides: [
          localCacheServiceProvider.overrideWithValue(InMemoryLocalCacheService()),
          workOrderRepositoryProvider.overrideWithValue(mockWoRepo),
          complaintRepositoryProvider.overrideWithValue(mockComplaintRepo),
          inspectionRepositoryProvider.overrideWithValue(mockInspectionRepo),
          deficiencyRepositoryProvider.overrideWithValue(mockDeficiencyRepo),
          lookupOptionsServiceProvider.overrideWithValue(mockLookupService),
          infrastructureOptionsServiceProvider.overrideWithValue(mockInfraService),
          authControllerProvider.overrideWith(
            () => FakeAuthenticatedController(session),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: WorkScreen(session: session),
        ),
      );
    }

    testWidgets(
        'shows tabs Job Works / Breakdowns / Inspections / Deficiencies for Depot Incharge with all 4 permissions',
        (tester) async {
      final session = fakeSession(
        role: AuthRole.depotIncharge,
        permissions: const [
          'maintenance.view',
          'complaints.view',
          'inspections.view',
          'assets.view',
          'maintenance.create',
        ],
      );

      await tester.pumpWidget(createTestWidget(session));
      await tester.pumpAndSettle();

      expect(find.text('Work Hub'), findsOneWidget);
      expect(find.text('Job Works'), findsOneWidget);
      expect(find.text('Breakdowns'), findsOneWidget);
      expect(find.text('Inspections'), findsOneWidget);
      expect(find.text('Deficiencies'), findsOneWidget);
      expect(find.text('Complaints'), findsNothing);

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.isScrollable, isTrue);
      expect(tabBar.tabs.length, 4);
    });

    testWidgets('hides Deficiencies tab without assets.view permission',
        (tester) async {
      final session = fakeSession(
        role: AuthRole.depotIncharge,
        permissions: const [
          'maintenance.view',
          'complaints.view',
          'inspections.view',
        ],
      );

      await tester.pumpWidget(createTestWidget(session));
      await tester.pumpAndSettle();

      expect(find.text('Job Works'), findsOneWidget);
      expect(find.text('Breakdowns'), findsOneWidget);
      expect(find.text('Inspections'), findsOneWidget);
      expect(find.text('Deficiencies'), findsNothing);

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.isScrollable, isFalse);
      expect(tabBar.tabs.length, 3);
    });

    testWidgets('single-tab rule: shows Deficiencies screen directly without TabBar when only assets.view',
        (tester) async {
      final session = fakeSession(
        role: AuthRole.depotIncharge,
        permissions: const ['assets.view'],
      );

      await tester.pumpWidget(createTestWidget(session));
      await tester.pumpAndSettle();

      // No TabBar or Work Hub header
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Work Hub'), findsNothing);

      // Deficiencies screen is embedded directly
      expect(find.byType(DeficiencyListScreen), findsOneWidget);
      expect(find.text('DEF-001'), findsOneWidget);
    });

    testWidgets(
        'tapping Deficiencies tab renders DeficiencyListScreen in embedded mode without second AppBar',
        (tester) async {
      final session = fakeSession(
        role: AuthRole.depotIncharge,
        permissions: const [
          'maintenance.view',
          'complaints.view',
          'inspections.view',
          'assets.view',
          'maintenance.create',
        ],
      );

      await tester.pumpWidget(createTestWidget(session));
      await tester.pumpAndSettle();

      // Exactly 1 AppBar exists (Work Hub's AppBar)
      expect(find.byType(AppBar), findsOneWidget);

      // Switch to Deficiencies tab
      await tester.tap(find.text('Deficiencies'));
      await tester.pumpAndSettle();

      // Still only 1 AppBar (no second AppBar from DeficiencyListScreen)
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);

      // Deficiencies list rows appear
      expect(find.text('DEF-001'), findsOneWidget);

      // Select row -> selection bar appears
      await tester.tap(find.byKey(const Key('deficiency_check_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deficiency_create_bulk')), findsOneWidget);
      expect(find.textContaining('1 selected'), findsOneWidget);
    });

    testWidgets('no layout overflow at 360dp width and text scale 1.3',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final session = fakeSession(
        role: AuthRole.depotIncharge,
        permissions: const [
          'maintenance.view',
          'complaints.view',
          'inspections.view',
          'assets.view',
          'maintenance.create',
        ],
      );

      await tester.pumpWidget(createTestWidget(session, textScale: 1.3));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Job Works'), findsOneWidget);
      expect(find.text('Breakdowns'), findsOneWidget);
      expect(find.text('Inspections'), findsOneWidget);
      expect(find.text('Deficiencies'), findsOneWidget);
    });
  });
}
