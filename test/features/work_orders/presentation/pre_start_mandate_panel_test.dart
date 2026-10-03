import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/supervisor_mandate.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/pre_start_mandate_panel.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fake_auth.dart';

class MockRepo extends Mock implements IWorkOrderRepository {}

void main() {
  late MockRepo repo;

  const wo = WorkOrder(
    id: 7,
    status: WorkOrderStatus.assigned,
    type: WorkOrderType.preventive,
    title: 'PM',
    originalScheduleId: 3,
    maintenanceMasterId: 9,
  );

  setUp(() => repo = MockRepo());

  Widget wrap() => ProviderScope(
        overrides: [workOrderRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: PreStartMandatePanel(workOrder: wo),
            ),
          ),
        ),
      );

  void stubLoad() {
    when(() => repo.prepareChecklist(7)).thenAnswer(
      (_) async => const PrepareChecklistResult(preview: true, masterId: 9),
    );
    when(() => repo.getSupervisorMandates(7)).thenAnswer((_) async => const [
          SupervisorMandate(
            id: 1,
            assetCategoryId: 2,
            assetName: 'TR',
            action: 'EXCLUDE',
            reason: 'Out of service',
          ),
        ]);
    when(() => repo.getMasterChecklistGroups(9)).thenAnswer((_) async => const [
          ChecklistGroupPreview(
            assetCategoryId: 2,
            assetCategoryName: 'Transformer',
            assetName: 'TR',
            itemCount: 4,
          ),
          ChecklistGroupPreview(
            assetCategoryId: 5,
            assetCategoryName: 'Panel',
            assetName: 'PN',
            itemCount: 2,
          ),
        ]);
  }

  testWidgets('collapsed makes no repository calls', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.byKey(const Key('pre_start_panel')), findsOneWidget);
    expect(find.text('Review checklist groups'), findsOneWidget);
    verifyZeroInteractions(repo);
  });

  testWidgets('opening shows groups and badges', (tester) async {
    stubLoad();
    await tester.pumpWidget(wrap());
    await tester.tap(find.byKey(const Key('pre_start_open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pre_start_group_0')), findsOneWidget);
    expect(find.byKey(const Key('pre_start_group_1')), findsOneWidget);
    expect(find.text('Skipped at START'), findsOneWidget);
    expect(find.text('Will be checked'), findsOneWidget);
    expect(find.text('Reason: Out of service'), findsOneWidget);
    expect(find.text('Check this group again'), findsOneWidget);
    expect(find.text('(TR) 4 items'), findsOneWidget);
  });

  testWidgets('Skip posts EXCLUDE with group keys', (tester) async {
    stubLoad();
    when(() => repo.setSupervisorMandate(
          7,
          assetCategoryId: any(named: 'assetCategoryId'),
          assetName: any(named: 'assetName'),
          action: any(named: 'action'),
          reason: any(named: 'reason'),
        )).thenAnswer((_) async => const SupervisorMandate(
          id: 2,
          assetCategoryId: 5,
          assetName: 'PN',
          action: 'EXCLUDE',
          reason: 'n/a',
        ));
    await tester.pumpWidget(wrap());
    await tester.tap(find.byKey(const Key('pre_start_open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('pre_start_group_1')),
        matching: find.byType(TextField),
      ),
      'n/a',
    );
    await tester.tap(find.text('Skip this group'));
    await tester.pumpAndSettle();
    verify(() => repo.setSupervisorMandate(
          7,
          assetCategoryId: 5,
          assetName: 'PN',
          action: 'EXCLUDE',
          reason: 'n/a',
        )).called(1);
    expect(find.text('Skipped at START'), findsNWidgets(2));
  });

  testWidgets('not-applicable execution mode', (tester) async {
    when(() => repo.prepareChecklist(7)).thenAnswer(
      (_) async => const PrepareChecklistResult(executionMode: 'COMPLAINT'),
    );
    await tester.pumpWidget(wrap());
    await tester.tap(find.byKey(const Key('pre_start_open')));
    await tester.pumpAndSettle();
    expect(find.text('Not applicable to this Job Work.'), findsOneWidget);
    verifyNever(() => repo.getMasterChecklistGroups(any()));
  });

  test('isVisibleFor truth table', () {
    final ok = fakeSession();
    expect(PreStartMandatePanel.isVisibleFor(wo, ok), isTrue);
    expect(PreStartMandatePanel.isVisibleFor(wo, null), isFalse);
    expect(
      PreStartMandatePanel.isVisibleFor(
        wo,
        fakeSession(role: AuthRole.maintenanceStaff),
      ),
      isFalse,
    );
    expect(
      PreStartMandatePanel.isVisibleFor(
        wo,
        fakeSession(permissions: const ['maintenance.view']),
      ),
      isFalse,
    );
    expect(
      PreStartMandatePanel.isVisibleFor(
        wo.copyWith(status: WorkOrderStatus.inProgress),
        ok,
      ),
      isFalse,
    );
    expect(
      PreStartMandatePanel.isVisibleFor(wo.copyWith(linkedRecordId: 4), ok),
      isFalse,
    );
    expect(
      PreStartMandatePanel.isVisibleFor(
        const WorkOrder(
          id: 1,
          status: WorkOrderStatus.assigned,
          type: WorkOrderType.preventive,
          title: 'x',
        ),
        ok,
      ),
      isFalse,
    );
    expect(
      PreStartMandatePanel.isVisibleFor(
        const WorkOrder(
          id: 1,
          status: WorkOrderStatus.assigned,
          type: WorkOrderType.preventive,
          title: 'x',
          originalScheduleId: 3,
          executionMode: 'COMPLAINT',
        ),
        ok,
      ),
      isFalse,
    );
  });
}
