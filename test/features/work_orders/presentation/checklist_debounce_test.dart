import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/sync/mutation_outcome.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/fake_auth.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

void main() {
  group('ChecklistScreen line submission', () {
    late MockWorkOrderRepository mockRepo;

    /// A measurement line (free reading) and an inspection point with the
    /// nested status -> action options the backend actually sends.
    const record = MaintenanceRecord(
      id: 55,
      workOrderId: 101,
      lines: [
        MaintenanceRecordLine(
          id: 301,
          itemName: 'Switch Room',
          inspectionPoint: 'Earth resistance value',
          valueType: MaintenanceValueType.decimal,
          itemKind: MaintenanceItemKind.recordParameter,
          assetCategory: 'Substation',
          unit: 'Ohms',
        ),
        MaintenanceRecordLine(
          id: 302,
          itemName: 'EB Bunk',
          inspectionPoint: 'Check and clean the EB meter bunk',
          valueType: MaintenanceValueType.status,
          assetCategory: 'Substation',
          statusOptions: [
            MaintenanceStatusOption(
              id: 2071,
              label: 'Dirty',
              actionOptions: [
                MaintenanceActionOption(id: 4204, label: 'Cleaned'),
                MaintenanceActionOption(id: 4205, label: 'Pending', isDeficiency: true),
              ],
            ),
            MaintenanceStatusOption(id: 2072, label: 'Clean'),
          ],
        ),
      ],
    );

    setUp(() {
      mockRepo = MockWorkOrderRepository();
      when(() => mockRepo.fetchMaintenanceRecord(55)).thenAnswer((_) async => record);
      when(() => mockRepo.submitChecklistLine(any(), any()))
          .thenAnswer((_) async => MutationOutcome.synced);
    });

    Future<void> pumpChecklist(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(
                fakeSession(role: AuthRole.maintenanceStaff),
              ),
            ),
          ],
          child: const MaterialApp(home: ChecklistScreen(recordId: 55)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('typing a reading submits once after the pause, not per keystroke',
        (tester) async {
      await pumpChecklist(tester);

      final valueField = find.byKey(const Key('line_value_301'));
      expect(valueField, findsOneWidget);

      await tester.enterText(valueField, '2');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(valueField, '2.5');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(valueField, '2.53');

      // Still inside the debounce window: nothing should have been sent yet.
      verifyNever(() => mockRepo.submitChecklistLine(any(), any()));

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockRepo.submitChecklistLine(55, captureAny()),
      ).captured;
      expect(captured.length, 1, reason: 'one save for the whole typed value');
      expect((captured.single as Map<String, dynamic>)['value'], '2.53');
    });

    testWidgets('choosing a status saves immediately and reveals its actions',
        (tester) async {
      await pumpChecklist(tester);

      // Only the status dropdown is present until a status is chosen.
      expect(find.byKey(const Key('line_302_status_option')), findsOneWidget);
      expect(find.byKey(const Key('line_302_action_option')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('line_302_status_option')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('line_302_status_option')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dirty').last);
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockRepo.submitChecklistLine(55, captureAny()),
      ).captured;
      expect(captured.length, 1);
      expect((captured.single as Map<String, dynamic>)['status_option'], 2071);

      // The actions belonging to "Dirty" are now offered.
      expect(find.byKey(const Key('line_302_action_option')), findsOneWidget);
    });

    testWidgets('a measurement line renders its unit', (tester) async {
      await pumpChecklist(tester);
      expect(find.text('Ohms'), findsOneWidget);
    });
  });
}
