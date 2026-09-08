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

  testWidgets('WorkOrderCreateScreen validates title and submits', (tester) async {
    final mockRepo = MockWorkOrderRepository();
    final mockOrg = MockOrgScopeOptionsService();
    final mockInfra = MockInfraOptionsService();
    final mockAssets = MockAssetApiService();

    when(() => mockInfra.fetchOptions(any(), depotId: any(named: 'depotId')))
        .thenAnswer((_) async => const []);
    when(() => mockRepo.createWorkOrder(
          title: any(named: 'title'),
          description: any(named: 'description'),
          type: any(named: 'type'),
          priority: any(named: 'priority'),
          depotId: any(named: 'depotId'),
          stationId: any(named: 'stationId'),
          infrastructureId: any(named: 'infrastructureId'),
          assetId: any(named: 'assetId'),
          dueDate: any(named: 'dueDate'),
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
          dueDate: null,
        )).called(1);
  });
}
