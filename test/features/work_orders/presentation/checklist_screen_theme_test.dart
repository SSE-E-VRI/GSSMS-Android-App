import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

void main() {
  // Regression test for a layout crash that only reproduced under the app's
  // real theme, not the bare MaterialApp used by the other checklist tests:
  // AppTheme.lightTheme gives every ElevatedButton a full-width
  // `minimumSize: Size.fromHeight(48)` for use as a standalone CTA. The
  // checklist's bottom action bar puts several ElevatedButtons in a Row
  // inside a horizontally scrolling SingleChildScrollView, which hands its
  // children unbounded width; combined with that infinite-width minimum,
  // Flutter's layout engine threw "BoxConstraints forces an infinite width"
  // and aborted the frame, leaving the whole screen blank with no app-level
  // exception logged.
  testWidgets(
      'bottom action bar lays out under the real app theme without an infinite-width crash',
      (tester) async {
    final mockRepo = MockWorkOrderRepository();
    const record = MaintenanceRecord(
      id: 23,
      workOrderId: 22,
      lines: [
        MaintenanceRecordLine(id: 1, itemName: 'Item', assetCategory: 'Category'),
      ],
    );
    when(() => mockRepo.fetchMaintenanceRecord(23)).thenAnswer((_) async => record);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [workOrderRepositoryProvider.overrideWithValue(mockRepo)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ChecklistScreen(recordId: 23),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Save Progress'), findsOneWidget);
    expect(find.text('Sign & Submit'), findsOneWidget);
  });
}
