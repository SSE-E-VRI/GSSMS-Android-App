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
  testWidgets(
      'point-less legacy offers no Convert action, close stays available (owner decision 2026-10-02)',
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

    // Owner decision 2026-10-02: legacy point-less inspections are NOT
    // converted (held/cancelled via Job Works) — no conversion path.
    expect(find.byKey(const Key('convert_to_work_order_button')),
        findsNothing);
    verifyNever(() => mockRepo.convertToWorkOrder(8));

    await tester.scrollUntilVisible(
      find.byKey(const Key('close_inspection_button')),
      200,
    );
    expect(find.byKey(const Key('close_inspection_button')), findsOneWidget);
  });
}
