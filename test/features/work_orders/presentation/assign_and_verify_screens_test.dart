import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/technician.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/verification_workspace_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockWorkOrderRepository mockRepo;

  const newOrder = WorkOrder(
    id: 101,
    status: WorkOrderStatus.newOrder,
    type: WorkOrderType.preventive,
    title: 'Monthly Transformer Inspection',
  );

  const techCompleted = WorkOrder(
    id: 101,
    status: WorkOrderStatus.techCompleted,
    type: WorkOrderType.preventive,
    title: 'Monthly Transformer Inspection',
  );

  setUp(() {
    mockRepo = MockWorkOrderRepository();
    when(() => mockRepo.fetchAudit(101)).thenAnswer(
      (_) async => const WorkOrderAudit(workOrderId: 101),
    );
    when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => [newOrder]);
  });

  Widget wrap(Widget home) {
    return ProviderScope(
      overrides: [workOrderRepositoryProvider.overrideWithValue(mockRepo)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: home,
      ),
    );
  }

  group('Assign technician dialog', () {
    testWidgets('opens a technician dropdown for ASSIGNED', (tester) async {
      when(() => mockRepo.fetchWorkOrderById(101)).thenAnswer((_) async => newOrder);
      when(() => mockRepo.fetchAllowedActions(101)).thenAnswer(
        (_) async => const WorkOrderActionSet(
          workOrderId: 101,
          currentStatus: 'NEW',
          allowed: [
            WorkOrderAction(
              targetStatus: 'ASSIGNED',
              label: 'Assigned',
              enabled: true,
            ),
          ],
        ),
      );
      when(() => mockRepo.fetchAssignableTechnicians()).thenAnswer(
        (_) async => const [
          Technician(id: 4, name: 'tech_ramesh'),
          Technician(id: 5, name: 'tech_anita'),
        ],
      );

      await tester.pumpWidget(wrap(const WorkOrderDetailScreen(workOrderId: 101)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('action_assigned')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assign_technician_dropdown')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the users.view error instead of an empty dropdown', (tester) async {
      when(() => mockRepo.fetchWorkOrderById(101)).thenAnswer((_) async => newOrder);
      when(() => mockRepo.fetchAllowedActions(101)).thenAnswer(
        (_) async => const WorkOrderActionSet(
          workOrderId: 101,
          currentStatus: 'NEW',
          allowed: [
            WorkOrderAction(
              targetStatus: 'ASSIGNED',
              label: 'Assigned',
              enabled: true,
            ),
          ],
        ),
      );
      when(() => mockRepo.fetchAssignableTechnicians()).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/users/'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/users/'),
            statusCode: 403,
            data: const {'detail': 'You do not have permission to view users.'},
          ),
        ),
      );

      await tester.pumpWidget(wrap(const WorkOrderDetailScreen(workOrderId: 101)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('action_assigned')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assign_technician_error')), findsOneWidget);
      expect(find.textContaining('permission to view users'), findsOneWidget);
      expect(find.byKey(const Key('assign_technician_dropdown')), findsNothing);
    });
  });

  group('VerificationWorkspaceScreen', () {
    void stubDetail() {
      when(() => mockRepo.fetchWorkOrderById(101))
          .thenAnswer((_) async => techCompleted);
      when(() => mockRepo.fetchAllowedActions(101)).thenAnswer(
        (_) async => const WorkOrderActionSet(workOrderId: 101),
      );
    }

    testWidgets('disables Verify when canVerify is false and shows banners', (tester) async {
      stubDetail();
      when(() => mockRepo.fetchVerificationWorkspace(101)).thenAnswer(
        (_) async => const VerificationWorkspace(
          canVerify: false,
          disabledReasons: ['Checklist incomplete'],
          deficiencies: ['Oil leak'],
          deficiencyCount: 1,
          record: MaintenanceRecord(
            id: 55,
            workOrderId: 101,
            lines: [
              MaintenanceRecordLine(
                id: 1,
                itemName: 'TR-01',
                inspectionPoint: 'Oil level',
                recordedValue: 'Low',
                status: 'FAIL',
                observationAction: 'Top up required',
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('verify_blocked_banner')), findsOneWidget);
      expect(find.text('Checklist incomplete'), findsOneWidget);
      expect(find.byKey(const Key('deficiency_banner')), findsOneWidget);
      expect(find.text('Oil leak'), findsOneWidget);
      expect(find.text('Oil level'), findsOneWidget);

      final verifyButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('verify_confirm_button')),
      );
      expect(verifyButton.onPressed, isNull);
    });

    testWidgets('Return to Technician still uses generic REWORK_REQUIRED', (tester) async {
      stubDetail();
      when(() => mockRepo.fetchVerificationWorkspace(101)).thenAnswer(
        (_) async => const VerificationWorkspace(canVerify: true),
      );
      when(
        () => mockRepo.transitionStatus(
          101,
          status: 'REWORK_REQUIRED',
          remarks: any(named: 'remarks'),
        ),
      ).thenAnswer((_) async => techCompleted.copyWith(status: WorkOrderStatus.reworkRequired));

      await tester.pumpWidget(
        wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(VerificationWorkspaceScreen));
      await ProviderScope.containerOf(context)
          .read(workOrderDetailControllerProvider(101).notifier)
          .loadDetail();
      await tester.pump();

      await tester.tap(find.byKey(const Key('return_to_technician_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('transition_remarks_field')),
        'Rework the oil top-up',
      );
      await tester.tap(find.byKey(const Key('transition_confirm_button')));
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.transitionStatus(
          101,
          status: 'REWORK_REQUIRED',
          remarks: 'Rework the oil top-up',
        ),
      ).called(1);
      verifyNever(() => mockRepo.verifyWorkOrder(any(), remarks: any(named: 'remarks')));
    });
  });
}
