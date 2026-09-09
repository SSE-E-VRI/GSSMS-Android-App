import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_line_card.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fake_auth.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'at least 4 checklist cards are rendered and visible on a 1080x2412 viewport',
      (tester) async {
    // 1080x2412 device configuration (e.g. OPPO CPH2381, Android 14)
    tester.view.physicalSize = const Size(1080, 2412);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockRepo = MockWorkOrderRepository();

    final testRecord = MaintenanceRecord(
      id: 77,
      workOrderId: 101,
      stationName: 'Thalanallur',
      templateName: 'Station Monthly',
      lines: List.generate(
        10,
        (i) => MaintenanceRecordLine(
          id: i + 1,
          itemName: 'Equipment Unit ${i + 1}',
          inspectionPoint: 'Checkpoint ${i + 1}',
          assetCategory: 'Substation',
          itemKind: MaintenanceItemKind.recordParameter,
          valueType: MaintenanceValueType.text,
        ),
      ),
    );

    when(() => mockRepo.fetchMaintenanceRecord(77))
        .thenAnswer((_) async => testRecord);

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
          home: const ChecklistScreen(recordId: 77),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final cardsFinder = find.byType(ChecklistLineCard);
    final renderedCount = cardsFinder.evaluate().length;

    // Assert that at least 4 checklist cards are rendered
    expect(renderedCount, greaterThanOrEqualTo(4));

    // Assert that the first 4 cards are within the visible viewport bounds
    final viewportHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    for (var i = 1; i <= 4; i++) {
      final cardFinder = find.byKey(ValueKey(i));
      expect(cardFinder, findsOneWidget);
      final cardTop = tester.getTopLeft(cardFinder).dy;
      expect(cardTop, lessThan(viewportHeight),
          reason: 'Card $i should be visible on screen');
    }
  });
}
