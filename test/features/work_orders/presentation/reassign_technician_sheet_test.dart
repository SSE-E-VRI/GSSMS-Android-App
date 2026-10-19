import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/technician.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/reassign_technician_sheet.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fake_auth.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

void main() {
  late MockWorkOrderRepository repo;
  bool? result;

  const wo = WorkOrder(
    id: 7,
    status: WorkOrderStatus.assigned,
    type: WorkOrderType.preventive,
    title: 'PM',
    depotId: 3,
    assignedToId: 1,
    assignedToName: 'Alice',
  );

  setUp(() {
    repo = MockWorkOrderRepository();
    result = null;
    when(() => repo.fetchAssignableTechnicians(depotId: 3)).thenAnswer(
      (_) async => const [
        Technician(id: 1, name: 'Alice'),
        Technician(id: 2, name: 'Bob'),
      ],
    );
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [workOrderRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async => result =
                    await showReassignTechnicianSheet(context, ref, wo),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> pickBob(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('reassign_technician_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob').last);
    await tester.pumpAndSettle();
  }

  testWidgets('excludes current assignee from the dropdown', (tester) async {
    await open(tester);
    expect(find.text('Reassign technician'), findsOneWidget);
    expect(find.byKey(const Key('reassign_current_assignee')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reassign_technician_dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    // Only the read-only current-assignee label shows Alice.
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('short reason is rejected and nothing is sent', (tester) async {
    await open(tester);
    await pickBob(tester);
    await tester.enterText(
        find.byKey(const Key('reassign_reason_field')), 'too short');
    await tester.tap(find.byKey(const Key('reassign_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('A reason of at least 10 characters is required.'),
        findsOneWidget);
    verifyNever(() => repo.reassignWorkOrder(any(),
        technicianId: any(named: 'technicianId'),
        reason: any(named: 'reason')));
  });

  testWidgets('passes technician and trimmed reason, then pops true',
      (tester) async {
    when(() => repo.reassignWorkOrder(7,
            technicianId: 2, reason: 'Original tech on leave'))
        .thenAnswer((_) async => wo);
    await open(tester);
    await pickBob(tester);
    await tester.enterText(find.byKey(const Key('reassign_reason_field')),
        '  Original tech on leave  ');
    await tester.tap(find.byKey(const Key('reassign_confirm')));
    await tester.pumpAndSettle();
    verify(() => repo.reassignWorkOrder(7,
        technicianId: 2, reason: 'Original tech on leave')).called(1);
    expect(result, isTrue);
    expect(find.text('Reassign technician'), findsNothing);
  });

  testWidgets('shows server 400 message inline and stays open',
      (tester) async {
    when(() => repo.reassignWorkOrder(any(),
            technicianId: any(named: 'technicianId'),
            reason: any(named: 'reason')))
        .thenThrow(DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 400,
        data: {'error': 'Same technician as current'},
      ),
      type: DioExceptionType.badResponse,
    ));
    await open(tester);
    await pickBob(tester);
    await tester.enterText(find.byKey(const Key('reassign_reason_field')),
        'Reason long enough');
    await tester.tap(find.byKey(const Key('reassign_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reassign_error')), findsOneWidget);
    expect(find.textContaining('Same technician as current'), findsOneWidget);
    expect(find.text('Reassign technician'), findsOneWidget);
    expect(result, isNull);
  });

  test('canShow gates on role, status and assignee', () {
    final allowed = fakeSession();
    expect(ReassignTechnicianSheet.canShow(wo, allowed), isTrue);
    expect(ReassignTechnicianSheet.canShow(wo, null), isFalse);
    expect(
        ReassignTechnicianSheet.canShow(
            wo, fakeSession(role: AuthRole.maintenanceStaff)),
        isFalse);
    expect(
        ReassignTechnicianSheet.canShow(
            wo.copyWith(status: WorkOrderStatus.inProgress), allowed),
        isFalse);
  });
}
