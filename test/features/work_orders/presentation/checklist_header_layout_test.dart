import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_header.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/fake_auth.dart';

class _MockRepo extends Mock implements IWorkOrderRepository {}

const _longStation =
    'Chennai Central Suburban Terminus Signal Interlocking Cabin';

const _record = MaintenanceRecord(
  id: 23,
  workOrderId: 22,
  workOrderTicket: 'JW-2026-000123',
  templateName: 'Quarterly Signal Maintenance',
  stationName: _longStation,
  divisionName: 'Chennai Division',
  depotName: 'Egmore Depot',
  lines: [
    MaintenanceRecordLine(id: 1, itemName: 'Item', assetCategory: 'Category'),
  ],
);

void main() {
  for (final scale in [1.0, 1.3, 1.5]) {
    testWidgets('header does not overflow at text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ChecklistHeader(record: _record),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      for (final label in ['Location', 'Schedule', 'Job Work', 'Date']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text(_longStation), findsOneWidget);
    });
  }

  testWidgets('screen shows title and details expanded at 360dp, scale 1.5',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _MockRepo();
    when(() => repo.fetchMaintenanceRecord(23))
        .thenAnswer((_) async => _record);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderRepositoryProvider.overrideWithValue(repo),
          authControllerProvider.overrideWith(
            () => FakeAuthenticatedController(
              fakeSession(role: AuthRole.maintenanceStaff),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const ChecklistScreen(recordId: 23),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('$_longStation · Quarterly Signal Maintenance · 0%'),
      findsOneWidget,
    );
    expect(find.text('0 of 1'), findsOneWidget);
    for (final label in ['Location', 'Schedule', 'Job Work', 'Date']) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
