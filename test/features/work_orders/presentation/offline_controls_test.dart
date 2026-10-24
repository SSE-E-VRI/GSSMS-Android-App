import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_action_bar.dart';
import '../../../helpers/fake_auth.dart';

void main() {
  testWidgets('restricted mode keeps local save and disables server completion',
      (tester) async {
    final session = fakeSession(role: AuthRole.maintenanceStaff, userId: 1)
        .copyWith(
            isOffline: true,
            offlineUntil: DateTime.now().add(const Duration(hours: 1)));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          authControllerProvider
              .overrideWith(() => FakeAuthenticatedController(session)),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: ChecklistActionBar(
          state: const ChecklistLoaded(record: MaintenanceRecord(id: 1)),
          onSignAndSubmit: () {},
          onIncompleteTap: () {},
          onSaveProgress: () {},
        )))));
    await tester.pumpAndSettle();
    final local = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Save progress'));
    final complete = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Connect to submit'));
    expect(local.onPressed, isNotNull);
    expect(complete.onPressed, isNull);
  });
}
