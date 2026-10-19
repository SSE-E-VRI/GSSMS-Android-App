import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/inspections/data/inspection_repository.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_detail_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockInspectionRepository extends Mock implements IInspectionRepository {}

class _FakeAuthenticatedController extends AuthController {
  _FakeAuthenticatedController(this._session);

  final UserSession _session;

  @override
  AuthState build() => Authenticated(_session);
}

const _session = UserSession(
  accessToken: 'test_token',
  username: 'depot_incharge',
  primaryRole: AuthRole.depotIncharge,
  roles: [AuthRole.depotIncharge],
  permissions: ['inspections.view', 'inspections.edit'],
  scope: OrgScope(level: OrgScopeLevel.depot),
);

void main() {
  testWidgets('Close button is disabled while a convert is in flight',
      (tester) async {
    final mockRepo = MockInspectionRepository();
    const open = Inspection(
      id: 8,
      title: 'EB Bunk Monthly Check',
      notes: 'Earth resistance and cleaning',
      status: InspectionStatus.open,
      stationName: 'Thalanallur',
    );
    when(() => mockRepo.fetchInspectionById(8)).thenAnswer((_) async => open);
    final gate = Completer<Map<String, dynamic>>();
    when(() => mockRepo.convertToWorkOrder(8)).thenAnswer((_) => gate.future);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inspectionRepositoryProvider.overrideWithValue(mockRepo),
          authControllerProvider.overrideWith(
            () => _FakeAuthenticatedController(_session),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const InspectionDetailScreen(inspection: open),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('convert_to_work_order_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_convert_button')));
    await tester.pump();
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('close_inspection_button')),
      200,
    );
    await tester.pump();
    final closeButton = tester
        .widget<FilledButton>(find.byKey(const Key('close_inspection_button')));
    expect(closeButton.onPressed, isNull);

    gate.complete({'work_order_id': 42});
    await tester.pumpAndSettle();
  });
}
