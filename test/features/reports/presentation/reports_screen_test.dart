import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/reports/data/infrastructure_options_service.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:gssms_mobile/features/reports/presentation/screens/reports_screen.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import '../../../helpers/fake_auth.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

class MockInfrastructureOptionsService extends Mock
    implements InfrastructureOptionsService {}

void main() {
  late MockWorkOrderRepository mockRepo;
  late MockInfrastructureOptionsService mockOptions;

  setUpAll(() {
    registerFallbackValue(InfraFilterType.all);
  });

  setUp(() {
    mockRepo = MockWorkOrderRepository();
    mockOptions = MockInfrastructureOptionsService();
  });

  group('ReportsScreen Widget Tests', () {
    testWidgets('renders Reports & Audit date filter and register list cards under AppTheme', (tester) async {
      const orders = [
        WorkOrder(
          id: 101,
          status: WorkOrderStatus.verified,
          type: WorkOrderType.preventive,
          ticketNumber: 'VRI-202609-0042',
          title: 'Station Monthly Maintenance',
          stationName: 'Sendurai',
          depotName: 'Vriddhachalam Depot',
          assignedToName: 'Krishna',
        ),
      ];

      when(() => mockRepo.fetchWorkOrders(
            status: any(named: 'status'),
            completionFrom: any(named: 'completionFrom'),
            completionTo: any(named: 'completionTo'),
          )).thenAnswer((_) async => orders);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            infrastructureOptionsServiceProvider.overrideWithValue(mockOptions),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(
                permissions: const ['reports.view'],
              )),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ReportsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Reports'), findsOneWidget);
      expect(find.byKey(const Key('reports_infra_type')), findsOneWidget);
      expect(find.byKey(const Key('reports_infra_item')), findsOneWidget);
      expect(find.byKey(const Key('date_range_from')), findsOneWidget);
      expect(find.text('Station Monthly Maintenance'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.byKey(const Key('register_card_101')), findsOneWidget);
    });
  });
}
