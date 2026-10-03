import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/presentation/screens/asset_detail_screen.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/deficiencies/data/deficiency_repository.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';
import 'package:gssms_mobile/features/deficiencies/presentation/screens/deficiency_list_screen.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/batch_convert_result.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../test/helpers/fake_auth.dart';

class MockDeficiencyRepository extends Mock implements IDeficiencyRepository {}
class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

void main() {
  group('DeficiencyListScreen Widget Tests', () {
    late MockDeficiencyRepository mockRepo;
    late MockWorkOrderRepository mockWoRepo;

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
      Deficiency(
        id: 2,
        code: 'DEF-002',
        description: 'Loose bolt on gantry',
        deficiencyFinding: 'Loose mounting bolt on overhead mast',
        status: DeficiencyStatus.resolved,
        severityLabel: 'MEDIUM',
        assetId: 102,
        assetUniqueId: 'AST-VRI-02',
        equipmentName: 'Gantry Mast',
        depotName: 'VRI Depot',
        detectedAt: DateTime(2026, 9, 14, 14, 0),
        activeRemedialWorkOrderId: 202,
        activeRemedialWorkOrderStatus: 'TECH_COMPLETED',
      ),
      Deficiency(
        id: 3,
        code: 'DEF-003',
        description: 'Platform lamp fixture cracked',
        deficiencyFinding: 'Cracked platform light bracket',
        status: DeficiencyStatus.inProgress,
        severityLabel: 'LOW',
        assetId: null, // No asset ID -> opens bottom sheet
        equipmentName: 'Platform 1 Light',
        depotName: 'VRI Depot',
        detectedAt: DateTime(2026, 9, 12, 8, 0),
        workOrderId: 303,
        workOrderTicket: 'JW-2026-303',
      ),
    ];

    setUp(() {
      mockRepo = MockDeficiencyRepository();
      mockWoRepo = MockWorkOrderRepository();
    });

    Widget createTestWidget({
      required IDeficiencyRepository repository,
      IWorkOrderRepository? workOrderRepository,
      AuthRole role = AuthRole.depotIncharge,
      List<String> permissions = const ['assets.view', 'maintenance.create'],
      bool isEmbedded = false,
    }) {
      final session = fakeSession(
        role: role,
        permissions: permissions,
      );

      return ProviderScope(
        overrides: [
          deficiencyRepositoryProvider.overrideWithValue(repository),
          workOrderRepositoryProvider.overrideWithValue(workOrderRepository ?? mockWoRepo),
          authControllerProvider.overrideWith(
            () => FakeAuthenticatedController(session),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: DeficiencyListScreen(isEmbedded: isEmbedded),
        ),
      );
    }

    testWidgets('renders list with bucket chips, defaults to Needs Action',
        (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);

      await tester.pumpWidget(createTestWidget(repository: mockRepo));
      await tester.pumpAndSettle();

      expect(find.text('Deficiencies'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Verify bucket filter chips
      expect(find.byKey(const Key('filter_chip_all')), findsOneWidget);
      expect(find.byKey(const Key('filter_chip_needs_action')), findsOneWidget);
      expect(find.byKey(const Key('filter_chip_in_progress')), findsOneWidget);
      expect(find.byKey(const Key('filter_chip_awaiting_closure')), findsOneWidget);

      // Default is Needs Action: only DEF-001 is shown (DEF-002 is awaiting closure, DEF-003 is in progress)
      expect(find.text('DEF-001'), findsOneWidget);
      expect(find.text('DEF-002'), findsNothing);
      expect(find.text('DEF-003'), findsNothing);

      // Verify counts on chips (non-collapsing): Total 3, Needs action 1, In progress 1, Awaiting closure 1
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Needs action (1)'), findsOneWidget);
      expect(find.text('In progress (1)'), findsOneWidget);
      expect(find.text('Awaiting closure (1)'), findsOneWidget);
    });

    testWidgets('bucket chips filter the list and show appropriate cards',
        (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);

      await tester.pumpWidget(createTestWidget(repository: mockRepo));
      await tester.pumpAndSettle();

      // Tap All chip
      await tester.tap(find.byKey(const Key('filter_chip_all')));
      await tester.pumpAndSettle();

      expect(find.text('DEF-001'), findsOneWidget);
      expect(find.text('DEF-002'), findsOneWidget);
      expect(find.text('DEF-003'), findsOneWidget);

      // Tap In progress chip -> DEF-003
      await tester.tap(find.byKey(const Key('filter_chip_in_progress')));
      await tester.pumpAndSettle();

      expect(find.text('DEF-001'), findsNothing);
      expect(find.text('DEF-002'), findsNothing);
      expect(find.text('DEF-003'), findsOneWidget);

      // Tap Awaiting closure chip -> DEF-002
      await tester.ensureVisible(find.byKey(const Key('filter_chip_awaiting_closure')));
      await tester.tap(find.byKey(const Key('filter_chip_awaiting_closure')));
      await tester.pumpAndSettle();

      expect(find.text('DEF-001'), findsNothing);
      expect(find.text('DEF-002'), findsOneWidget);
      expect(find.text('DEF-003'), findsNothing);
    });

    testWidgets('Depot Incharge sees Create Job Work buttons and checkboxes on Needs Action',
        (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);

      await tester.pumpWidget(createTestWidget(
        repository: mockRepo,
        role: AuthRole.depotIncharge,
        permissions: ['assets.view', 'maintenance.create'],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deficiency_check_1')), findsOneWidget);
      expect(find.byKey(const Key('deficiency_create_1')), findsOneWidget);
    });

    testWidgets('Maintenance Staff does not see checkboxes or Create buttons',
        (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);

      await tester.pumpWidget(createTestWidget(
        repository: mockRepo,
        role: AuthRole.maintenanceStaff,
        permissions: ['assets.view'],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deficiency_check_1')), findsNothing);
      expect(find.byKey(const Key('deficiency_create_1')), findsNothing);
    });

    testWidgets('single create calls API and shows success snackbar',
        (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);

      when(() => mockWoRepo.createRectification([1], onePerDeficiency: false))
          .thenAnswer((_) async => const BatchConvertResult(
                workOrderIds: [1001],
                results: [BatchConvertResultItem(ticketNumber: 'JW-REC-001')],
              ));

      await tester.pumpWidget(createTestWidget(
        repository: mockRepo,
        workOrderRepository: mockWoRepo,
      ));
      await tester.pumpAndSettle();

      // Tap Create Job Work
      await tester.tap(find.byKey(const Key('deficiency_create_1')));
      await tester.pumpAndSettle();

      // Dialog appears with exact confirmation text
      expect(find.text('Create a Job Work for this deficiency?'), findsOneWidget);

      // Confirm dialog
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      verify(() => mockWoRepo.createRectification([1], onePerDeficiency: false)).called(1);
      expect(find.text('Job Work JW-REC-001 created.'), findsOneWidget);
    });

    testWidgets('bulk selection shows bottom bar and creates grouped Job Works',
        (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);

      when(() => mockWoRepo.createRectification([1], onePerDeficiency: false))
          .thenAnswer((_) async => const BatchConvertResult(
                workOrderIds: [1001],
                results: [BatchConvertResultItem(ticketNumber: 'JW-BULK-001')],
              ));

      await tester.pumpWidget(createTestWidget(
        repository: mockRepo,
        workOrderRepository: mockWoRepo,
      ));
      await tester.pumpAndSettle();

      // Bottom bar not visible initially
      expect(find.byKey(const Key('deficiency_create_bulk')), findsNothing);

      // Check item
      await tester.tap(find.byKey(const Key('deficiency_check_1')));
      await tester.pumpAndSettle();

      // Bottom bar appears
      expect(find.byKey(const Key('deficiency_create_bulk')), findsOneWidget);
      expect(find.byKey(const Key('rectification_grouping_switch')), findsOneWidget);

      // Tap bulk create button
      await tester.tap(find.byKey(const Key('deficiency_create_bulk')));
      await tester.pumpAndSettle();

      expect(find.text('Create rectification Job Work(s) for 1 deficiencies, grouped by location?'), findsOneWidget);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      verify(() => mockWoRepo.createRectification([1], onePerDeficiency: false)).called(1);
      expect(find.text('Job Work JW-BULK-001 created.'), findsOneWidget);
    });

    testWidgets('search field filters list by text query', (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);

      await tester.pumpWidget(createTestWidget(repository: mockRepo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'transformer');
      await tester.pumpAndSettle();

      expect(find.text('DEF-001'), findsOneWidget);
      expect(find.text('DEF-002'), findsNothing);
      expect(find.text('DEF-003'), findsNothing);
    });

    testWidgets('shows empty state when no deficiencies exist',
        (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => []);

      await tester.pumpWidget(createTestWidget(repository: mockRepo));
      await tester.pumpAndSettle();

      expect(find.text('No deficiencies recorded yet'), findsOneWidget);
    });

    testWidgets('shows PermissionDeniedView when user lacks assets.view',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        repository: mockRepo,
        permissions: ['complaints.view'],
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionDeniedView), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('tapping card with assetId deep-links to AssetDetailScreen',
        (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);

      await tester.pumpWidget(createTestWidget(repository: mockRepo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('DEF-001'));
      await tester.pumpAndSettle();

      expect(find.byType(AssetDetailScreen), findsOneWidget);
      final assetDetail = tester.widget<AssetDetailScreen>(
        find.byType(AssetDetailScreen),
      );
      expect(assetDetail.assetId, 101);
      expect(assetDetail.initialTabIndex, 4);
    });

    testWidgets('selection clears when switching bucket chips',
        (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);

      await tester.pumpWidget(createTestWidget(repository: mockRepo));
      await tester.pumpAndSettle();

      // Check item in Needs action
      await tester.tap(find.byKey(const Key('deficiency_check_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deficiency_create_bulk')), findsOneWidget);

      // Switch to All
      await tester.tap(find.byKey(const Key('filter_chip_all')));
      await tester.pumpAndSettle();

      // Bottom bar is gone because selection was cleared
      expect(find.byKey(const Key('deficiency_create_bulk')), findsNothing);
    });

    testWidgets('409 conflict error shows message and reloads list',
        (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);

      final dioError = DioException(
        requestOptions: RequestOptions(path: '/api/v1/maintenance/work-orders/create_rectification/'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/maintenance/work-orders/create_rectification/'),
          statusCode: 409,
          data: {'detail': 'A Job Work already exists for this deficiency.', 'existing_ticket': 'JW-EXISTING-99'},
        ),
        type: DioExceptionType.badResponse,
      );

      when(() => mockWoRepo.createRectification([1], onePerDeficiency: false))
          .thenThrow(dioError);

      await tester.pumpWidget(createTestWidget(
        repository: mockRepo,
        workOrderRepository: mockWoRepo,
      ));
      await tester.pumpAndSettle();

      // Tap Create Job Work
      await tester.tap(find.byKey(const Key('deficiency_create_1')));
      await tester.pumpAndSettle();

      // Confirm
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.textContaining('JW-EXISTING-99'), findsOneWidget);
      // Verify reload was triggered
      verify(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).called(2);
    });

    testWidgets('embedded DeficiencyListScreen renders without AppBar or BackButton',
        (tester) async {
      when(() => mockRepo.fetchPendingDeficiencies(
            zoneId: any(named: 'zoneId'),
            divisionId: any(named: 'divisionId'),
            depotId: any(named: 'depotId'),
          )).thenAnswer((_) async => testDeficiencies);

      await tester.pumpWidget(createTestWidget(
        repository: mockRepo,
        isEmbedded: true,
      ));
      await tester.pumpAndSettle();

      // No standalone AppBar
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(BackButton), findsNothing);

      // Search, bucket chips, and list content are present
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byKey(const Key('filter_chip_needs_action')), findsOneWidget);
      expect(find.text('DEF-001'), findsOneWidget);
    });

    testWidgets('embedded DeficiencyListScreen without assets.view renders PermissionDeniedView without AppBar',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        repository: mockRepo,
        permissions: ['maintenance.view'],
        isEmbedded: true,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionDeniedView), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
    });

  });
}
