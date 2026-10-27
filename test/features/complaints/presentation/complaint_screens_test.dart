import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/data/lookup_options_service.dart';
import 'package:gssms_mobile/core/domain/lookup_option.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
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
import 'package:gssms_mobile/features/reports/data/infrastructure_options_service.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:mocktail/mocktail.dart';

class MockComplaintRepository extends Mock implements IComplaintRepository {}

class MockLookupOptionsService extends Mock implements LookupOptionsService {}

class MockInfrastructureOptionsService extends Mock
    implements InfrastructureOptionsService {}

class MockAssetApiService extends Mock implements AssetApiService {}

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
  permissions: ['complaints.view', 'complaints.create'],
  scope: OrgScope(level: OrgScopeLevel.depot),
);

void main() {
  setUpAll(() {
    registerFallbackValue(InfraFilterType.station);
  });

  group('Complaint Screens Widget Tests', () {
    late MockComplaintRepository mockRepo;

    const testComplaints = [
      Complaint(
        id: 1,
        title: 'Transformer Leakage',
        description: 'Oil leaking near base valve',
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

      expect(find.text('Breakdowns'), findsOneWidget);
      expect(find.text('Search number, title, place'), findsOneWidget);
      expect(find.byKey(const Key('complaint_filters_button')), findsOneWidget);
      expect(find.text('Transformer Leakage'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      // Status is always visible on the card (B7); there is no complaint
      // severity in the API, so no fabricated priority badge either.
      expect(find.text('Open'), findsWidgets);
      expect(find.text('High'), findsNothing);
      expect(find.text('Medium'), findsNothing);
      expect(find.byKey(const Key('fab_create_complaint')), findsOneWidget);
      expect(
        find.bySemanticsLabel('Breakdown #1, status: Open, VRI (Station), Transformer Leakage'),
        findsOneWidget,
      );

      // Open filter bottom sheet
      await tester.tap(find.byKey(const Key('complaint_filters_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('date_range_from')), findsOneWidget);
      expect(find.byKey(const Key('date_range_to')), findsOneWidget);
      expect(find.byKey(const Key('complaint_status_filter_dropdown')), findsOneWidget);
    });

    testWidgets('ComplaintListScreen displays converted breakdown with linked Job Work line', (tester) async {
      const convertedComplaint = Complaint(
        id: 42,
        title: 'Signal Light Failure',
        description: 'Bulb fused',
        status: ComplaintStatus.converted,
        stationName: 'VRI',
        complainantName: 'Station Master',
        isConverted: true,
        workOrderId: 101,
        workOrderTicketNumber: 'JW-2026-101',
        workOrderStatus: 'IN_PROGRESS',
      );

      when(() => mockRepo.fetchComplaints()).thenAnswer((_) async => [convertedComplaint]);

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

      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Station Master'), findsOneWidget);
      expect(find.text('Job Work JW-2026-101 · In Progress'), findsOneWidget);
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
      expect(find.text('Breakdown #1'), findsOneWidget);
      expect(find.text('Oil leaking near base valve'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    group('detail has no delete icon (recorded breakdowns are immutable)', () {
      UserSession sessionFor(AuthRole role) => UserSession(
            accessToken: 'test_token',
            username: 'user',
            primaryRole: role,
            roles: [role],
            permissions: const ['complaints.view', 'complaints.delete'],
            scope: const OrgScope(level: OrgScopeLevel.depot),
          );

      Future<void> pumpDetail(
        WidgetTester tester,
        AuthRole role, {
        ComplaintStatus status = ComplaintStatus.open,
      }) async {
        final complaint = Complaint(
          id: 1,
          title: 'Transformer Leakage',
          status: status,
          stationName: 'VRI',
        );
        when(() => mockRepo.fetchComplaintById(1))
            .thenAnswer((_) async => complaint);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              complaintRepositoryProvider.overrideWithValue(mockRepo),
              authControllerProvider.overrideWith(
                () => _FakeAuthenticatedController(sessionFor(role)),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: ComplaintDetailScreen(complaint: complaint),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('is hidden for DEPOT_INCHARGE even with complaints.delete',
          (tester) async {
        await pumpDetail(tester, AuthRole.depotIncharge);
        expect(find.byKey(const Key('delete_breakdown_button')), findsNothing);
      });

      testWidgets('is hidden for SUPER_ADMIN even with complaints.delete',
          (tester) async {
        await pumpDetail(tester, AuthRole.superAdmin);
        expect(find.byKey(const Key('delete_breakdown_button')), findsNothing);
      });

      testWidgets('stays hidden for a closed complaint', (tester) async {
        await pumpDetail(tester, AuthRole.superAdmin,
            status: ComplaintStatus.closed);
        expect(find.byKey(const Key('delete_breakdown_button')), findsNothing);
      });
    });

    testWidgets('ComplaintCreateScreen validates inputs and submits', (tester) async {
      final mockLookups = MockLookupOptionsService();
      final mockInfra = MockInfrastructureOptionsService();
      final mockAssets = MockAssetApiService();

      when(() => mockLookups.fetchOptions('complaint_department')).thenAnswer(
        (_) async => const [LookupOption(key: 'ELECTRICAL', label: 'Electrical')],
      );
      when(() => mockInfra.fetchOptions(any(), depotId: any(named: 'depotId')))
          .thenAnswer((_) async => const []);
      when(() => mockAssets.getAssets(stationId: any(named: 'stationId')))
          .thenAnswer((_) async => const AssetPage(assets: [], truncated: false));
      when(() => mockRepo.createComplaint(
            title: any(named: 'title'),
            description: any(named: 'description'),
            department: any(named: 'department'),
            depotId: any(named: 'depotId'),
            stationId: any(named: 'stationId'),
            infrastructureId: any(named: 'infrastructureId'),
            assetId: any(named: 'assetId'),
            generalAssetDescription: any(named: 'generalAssetDescription'),
            failureDate: any(named: 'failureDate'),
            failureTime: any(named: 'failureTime'),
            complainantName: any(named: 'complainantName'),
          )).thenAnswer((_) async => testComplaints[0]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            complaintRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthenticatedController(_sessionWithComplaintsAdd),
            ),
            lookupOptionsServiceProvider.overrideWithValue(mockLookups),
            infrastructureOptionsServiceProvider.overrideWithValue(mockInfra),
            assetApiServiceProvider.overrideWithValue(mockAssets),
          ],
          child: const MaterialApp(
            home: ComplaintCreateScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap submit with empty fields -> shows validation errors
      await tester.ensureVisible(find.byKey(const Key('submit_complaint_button')));
      await tester.tap(find.byKey(const Key('submit_complaint_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a breakdown title'), findsOneWidget);
      expect(find.text('Please enter detailed description'), findsOneWidget);

      // Fill in title/description and complainant name, but still no department -> the Form-level
      // errors clear while the department check (a plain submit-time guard,
      // not a FormField validator) now surfaces on its own.
      await tester.enterText(find.byKey(const Key('complaint_title_field')), 'Test Title');
      await tester.enterText(find.byKey(const Key('complaint_description_field')), 'Detailed failure description');
      await tester.enterText(find.byKey(const Key('complaint_complainant_field')), 'Test User');
      await tester.ensureVisible(find.byKey(const Key('submit_complaint_button')));
      await tester.tap(find.byKey(const Key('submit_complaint_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please select a department'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('complaint_department_dropdown')));
      await tester.tap(find.byKey(const Key('complaint_department_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Electrical').last);
      await tester.pumpAndSettle();

      // Pick failure date
      await tester.ensureVisible(find.byKey(const Key('complaint_failure_date_field')));
      await tester.tap(find.byKey(const Key('complaint_failure_date_field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Pick failure time
      await tester.ensureVisible(find.byKey(const Key('complaint_failure_time_field')));
      await tester.tap(find.byKey(const Key('complaint_failure_time_field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('submit_complaint_button')));
      await tester.tap(find.byKey(const Key('submit_complaint_button')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.createComplaint(
            title: 'Test Title',
            description: 'Detailed failure description',
            department: 'ELECTRICAL',
            depotId: null,
            stationId: null,
            infrastructureId: null,
            assetId: null,
            generalAssetDescription: null,
            failureDate: any(named: 'failureDate'),
            failureTime: any(named: 'failureTime'),
            complainantName: 'Test User',
          )).called(1);
    });

    testWidgets(
        'convert coerces string work_order_id and refetches full record with ticket',
        (tester) async {
      const open = Complaint(
        id: 7,
        title: 'Pump Noise',
        description: 'Rattling',
        status: ComplaintStatus.open,
        stationName: 'VRI',
      );
      const converted = Complaint(
        id: 7,
        title: 'Pump Noise',
        description: 'Rattling',
        status: ComplaintStatus.converted,
        stationName: 'VRI',
        isConverted: true,
        workOrderId: 42,
        workOrderTicketNumber: 'JW-2026-42',
        workOrderStatus: 'IN_PROGRESS',
      );
      var fetchCount = 0;
      when(() => mockRepo.fetchComplaintById(7)).thenAnswer((_) async {
        fetchCount++;
        return fetchCount == 1 ? open : converted;
      });
      when(() => mockRepo.convertToWorkOrder(7))
          .thenAnswer((_) async => {'work_order_id': '42'});
      const convertSession = UserSession(
        accessToken: 'test_token',
        username: 'depot_incharge',
        primaryRole: AuthRole.depotIncharge,
        roles: [AuthRole.depotIncharge],
        permissions: ['complaints.view', 'complaints.edit', 'maintenance.view'],
        scope: OrgScope(level: OrgScopeLevel.depot),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            complaintRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthenticatedController(convertSession),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ComplaintDetailScreen(complaint: open),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fetchCount, 1);

      await tester.tap(find.byKey(const Key('convert_to_work_order_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('A Job Work will be created'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm_convert_button')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.convertToWorkOrder(7)).called(1);
      expect(find.text('Converted. A Job Work has been created.'),
          findsOneWidget);
      expect(fetchCount, 2);
      await tester.scrollUntilVisible(
        find.textContaining('JW-2026-42'),
        200,
      );
      expect(find.textContaining('JW-2026-42'), findsWidgets);
    });
  });
}
