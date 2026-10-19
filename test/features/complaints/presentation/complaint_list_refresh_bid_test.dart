import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/complaints/data/complaint_repository.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_detail_screen.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_list_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockComplaintRepository extends Mock implements IComplaintRepository {}

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
  permissions: ['complaints.view', 'complaints.create'],
  scope: OrgScope(level: OrgScopeLevel.depot),
);

void main() {
  testWidgets('back from detail refetches the complaint list', (tester) async {
    final mockRepo = MockComplaintRepository();
    const complaint = Complaint(
      id: 1,
      title: 'Transformer Leakage',
      description: 'Oil leaking near base valve',
      status: ComplaintStatus.open,
      stationName: 'VRI',
    );
    when(() => mockRepo.fetchComplaints())
        .thenAnswer((_) async => [complaint]);
    when(() => mockRepo.fetchComplaintById(1))
        .thenAnswer((_) async => complaint);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          complaintRepositoryProvider.overrideWithValue(mockRepo),
          authControllerProvider.overrideWith(
            () => _FakeAuthenticatedController(_session),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ComplaintListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('complaint_card_1')));
    await tester.pumpAndSettle();
    expect(find.byType(ComplaintDetailScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    verify(() => mockRepo.fetchComplaints()).called(2);
  });
}
