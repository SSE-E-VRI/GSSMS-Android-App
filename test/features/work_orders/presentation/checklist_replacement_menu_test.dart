import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_repository.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/fake_auth.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

class MockReplacementRepository extends Mock implements IReplacementRepository {}

MaintenanceRecord _record({
  String status = 'IN_PROGRESS',
  bool withJobWork = true,
}) {
  return MaintenanceRecord.fromJson({
    'id': 55,
    'status': status,
    if (withJobWork) 'work_order': 101,
    if (withJobWork)
      'work_order_context': {
        'work_order_id': 101,
        'asset_id': 501,
        'asset_unique_id': 'STN-001',
        'asset_name': 'Panel',
        'status': status,
      },
    'schedule_details': const {'station': 9, 'infrastructure': 4},
    'lines': const <dynamic>[],
  });
}

void main() {
  late MockWorkOrderRepository woRepo;
  late MockReplacementRepository replRepo;

  setUp(() {
    woRepo = MockWorkOrderRepository();
    replRepo = MockReplacementRepository();
  });

  Future<void> pump(
    WidgetTester tester, {
    required AuthRole role,
    required List<String> permissions,
    MaintenanceRecord? record,
  }) async {
    when(() => woRepo.fetchMaintenanceRecord(55))
        .thenAnswer((_) async => record ?? _record());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderRepositoryProvider.overrideWithValue(woRepo),
          replacementRepositoryProvider.overrideWithValue(replRepo),
          authControllerProvider.overrideWith(
            () => FakeAuthenticatedController(
                fakeSession(role: role, permissions: permissions)),
          ),
        ],
        child: const MaterialApp(home: ChecklistScreen(recordId: 55)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checklist_overflow_menu')));
    await tester.pumpAndSettle();
  }

  const staffPerms = ['maintenance.view', 'maintenance.edit', 'assets.replace'];

  testWidgets('maintenance staff sees both replace entries', (tester) async {
    await pump(tester, role: AuthRole.maintenanceStaff, permissions: staffPerms);
    expect(find.text('Enter Replaced Asset'), findsOneWidget);
    expect(find.text('Enter Replaced Component'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
  });

  testWidgets('role without assets.replace sees neither', (tester) async {
    await pump(tester,
        role: AuthRole.divAdmin,
        permissions: const ['maintenance.view', 'maintenance.edit']);
    expect(find.text('Enter Replaced Asset'), findsNothing);
    expect(find.text('Enter Replaced Component'), findsNothing);
    expect(find.text('Preview'), findsOneWidget);
  });

  testWidgets('super admin sees component only', (tester) async {
    await pump(tester, role: AuthRole.superAdmin, permissions: const ['*']);
    expect(find.text('Enter Replaced Asset'), findsNothing);
    expect(find.text('Enter Replaced Component'), findsOneWidget);
  });

  testWidgets('hidden once the record is TECH_COMPLETED', (tester) async {
    await pump(tester,
        role: AuthRole.maintenanceStaff,
        permissions: staffPerms,
        record: _record(status: 'TECH_COMPLETED'));
    expect(find.text('Enter Replaced Asset'), findsNothing);
    expect(find.text('Enter Replaced Component'), findsNothing);
  });

  testWidgets('hidden when the record has no Job Work', (tester) async {
    await pump(tester,
        role: AuthRole.maintenanceStaff,
        permissions: staffPerms,
        record: _record(withJobWork: false));
    expect(find.text('Enter Replaced Asset'), findsNothing);
    expect(find.text('Enter Replaced Component'), findsNothing);
  });

  testWidgets('Enter Replaced Asset opens the Replace Asset sheet',
      (tester) async {
    await pump(tester, role: AuthRole.maintenanceStaff, permissions: staffPerms);
    await tester.tap(find.text('Enter Replaced Asset'));
    await tester.pumpAndSettle();
    expect(find.text('Replace Asset: STN-001'), findsOneWidget);
  });
}
