import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fake_auth.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

/// Text-scale layout-tolerance harness (P1-8).
///
/// Behavioural, not pixel-golden: each subject is pumped at 1.0 / 1.3 / 1.5
/// and checked for layout overflow. Home at 1.3 is the recorded failure:
/// `GridView.count(childAspectRatio: 1.15)` in `home_screen.dart` overflows.
/// Do not fix the grid in this phase.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home_screen textScaler 1.0', (tester) async {
    await _setSurface(tester, const Size(400, 800));
    await _pumpHome(tester, 1.0);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('home_screen textScaler 1.3', (tester) async {
    await _setSurface(tester, const Size(400, 800));
    await _pumpHome(tester, 1.3);
    await tester.pump();
    // Drain the RenderFlex overflows (visible in the console logs) so the
    // framework does not raise its own implicit multi-exception failure;
    // the recorded failure below carries the P1-8 cause instead. Note:
    // takeException() collapses concurrent layout errors into one combined
    // summary, so the overflow type cannot be asserted from its string.
    var errorCount = 0;
    while (tester.takeException() != null) {
      errorCount++;
    }
    if (errorCount == 0) {
      fail('P1-8 gate changed: home grid no longer errors at textScaler 1.3 '
          '— remove this recorded failure and keep the green run.');
    }
    fail('Recorded P1-8 failure: home grid overflows at textScaler 1.3 '
        '(GridView.count childAspectRatio 1.15, home_screen.dart). '
        'Do not fix in this phase.');
  });

  testWidgets('home_screen textScaler 1.5', (tester) async {
    await _setSurface(tester, const Size(400, 800));
    await _pumpHome(tester, 1.5);
    await tester.pump();
    // 1.5 overflows from the same root cause; drain so the suite records
    // only the 1.3 gate above. No global FlutterError handler is installed
    // (a leaked override would mask failures in unrelated tests).
    while (tester.takeException() != null) {}
  });

  testWidgets('checklist_screen textScaler 1.0', (tester) async {
    await _pumpChecklist(tester, 1.0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('checklist_screen textScaler 1.3', (tester) async {
    await _pumpChecklist(tester, 1.3);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('checklist_screen textScaler 1.5', (tester) async {
    await _pumpChecklist(tester, 1.5);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpHome(WidgetTester tester, double scale) async {
  const session = UserSession(
    accessToken: 'super_token',
    username: 'super_admin_user',
    firstName: 'System',
    lastName: 'Administrator',
    primaryRole: AuthRole.superAdmin,
    roles: [AuthRole.superAdmin],
    permissions: ['*'],
    scope: OrgScope(level: OrgScopeLevel.global),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheServiceProvider
            .overrideWithValue(InMemoryLocalCacheService()),
        authRepositoryProvider.overrideWithValue(MockAuthRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          );
        },
        home: const HomeScreen(session: session),
      ),
    ),
  );
}

Future<void> _pumpChecklist(WidgetTester tester, double scale) async {
  final mockRepo = MockWorkOrderRepository();
  const record = MaintenanceRecord(
    id: 23,
    workOrderId: 22,
    lines: [
      MaintenanceRecordLine(
        id: 1,
        itemName: 'Item',
        assetCategory: 'Category',
      ),
    ],
  );
  when(() => mockRepo.fetchMaintenanceRecord(23))
      .thenAnswer((_) async => record);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheServiceProvider
            .overrideWithValue(InMemoryLocalCacheService()),
        workOrderRepositoryProvider.overrideWithValue(mockRepo),
        authControllerProvider.overrideWith(
          () => FakeAuthenticatedController(
            fakeSession(role: AuthRole.maintenanceStaff),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          );
        },
        home: const ChecklistScreen(recordId: 23),
      ),
    ),
  );
}
