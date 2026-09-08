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
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_create_screen.dart';
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

const _sessionWithComplaintsAdd = UserSession(
  accessToken: 'test_token',
  username: 'depot_incharge',
  firstName: 'Vri',
  lastName: '',
  primaryRole: AuthRole.depotIncharge,
  roles: [AuthRole.depotIncharge],
  permissions: ['complaints.create'],
  scope: OrgScope(level: OrgScopeLevel.depot),
);

void main() {
  group('Complaint Screens Widget Tests', () {
    late MockComplaintRepository mockRepo;

    const testComplaints = [
      Complaint(
        id: 1,
        complaintNumber: 'CMP-001',
        title: 'Transformer Leakage',
        description: 'Oil leaking near base valve',
        severity: ComplaintSeverity.high,
        status: ComplaintStatus.open,
        stationName: 'VRI',
      ),
    ];

    setUp(() {
      mockRepo = MockComplaintRepository();
    });

    testWidgets('ComplaintListScreen renders complaints and log button', (tester) async {
      when(() => mockRepo.fetchComplaints()).thenAnswer((_) async => testComplaints);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            complaintRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthenticatedController(_sessionWithComplaintsAdd),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ComplaintListScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Complaints & Issues'), findsOneWidget);
      expect(find.byKey(const Key('date_range_from')), findsOneWidget);
      expect(find.text('Transformer Leakage'), findsOneWidget);
      expect(find.text('CMP-001'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.byKey(const Key('fab_create_complaint')), findsOneWidget);
    });

    testWidgets('tapping a logged complaint opens its detail screen', (tester) async {
      when(() => mockRepo.fetchComplaints()).thenAnswer((_) async => testComplaints);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            complaintRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthenticatedController(_sessionWithComplaintsAdd),
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
      expect(find.text('CMP-001'), findsOneWidget);
      expect(find.text('Oil leaking near base valve'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('ComplaintCreateScreen validates inputs and submits', (tester) async {
      when(() => mockRepo.createComplaint(
            title: any(named: 'title'),
            description: any(named: 'description'),
            severity: any(named: 'severity'),
            assetId: any(named: 'assetId'),
          )).thenAnswer((_) async => testComplaints[0]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            complaintRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: ComplaintCreateScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap submit with empty fields -> shows validation errors
      await tester.tap(find.byKey(const Key('submit_complaint_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a complaint title'), findsOneWidget);
      expect(find.text('Please enter detailed description'), findsOneWidget);

      // Enter valid fields
      await tester.enterText(find.byKey(const Key('complaint_title_field')), 'Test Title');
      await tester.enterText(find.byKey(const Key('complaint_description_field')), 'Detailed failure description');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_complaint_button')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.createComplaint(
            title: 'Test Title',
            description: 'Detailed failure description',
            severity: 'MEDIUM',
            assetId: null,
          )).called(1);
    });
  });
}
