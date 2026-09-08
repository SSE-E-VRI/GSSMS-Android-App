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
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_create_screen.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_detail_screen.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_list_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockInspectionRepository extends Mock implements IInspectionRepository {}

class _FakeAuthenticatedController extends AuthController {
  _FakeAuthenticatedController(this._session);

  final UserSession _session;

  @override
  AuthState build() => Authenticated(_session);
}

const _sessionWithInspectionsAdd = UserSession(
  accessToken: 'test_token',
  username: 'depot_incharge',
  firstName: 'Vri',
  lastName: '',
  primaryRole: AuthRole.depotIncharge,
  roles: [AuthRole.depotIncharge],
  permissions: [
    'inspections.view',
    'inspections.create',
    'inspections.edit',
    'maintenance.view'
  ],
  scope: OrgScope(level: OrgScopeLevel.depot),
);

// Mirrors web's usePermissions().isDepotRole gate on the Convert action:
// a non-depot role holding the same inspections.edit permission still can't
// convert, because ConversionService itself 403s everyone except
// DEPOT_INCHARGE/DEPOT_USER.
const _sessionNonDepotRole = UserSession(
  accessToken: 'test_token',
  username: 'div_admin',
  firstName: 'Div',
  lastName: '',
  primaryRole: AuthRole.divAdmin,
  roles: [AuthRole.divAdmin],
  permissions: ['inspections.view', 'inspections.create', 'inspections.edit'],
  scope: OrgScope(level: OrgScopeLevel.division),
);

void main() {
  setUpAll(() {
    registerFallbackValue('fallback');
    registerFallbackValue(0);
    registerFallbackValue(<String>['fallback']);
  });

  group('Inspection Screens Widget Tests', () {
    late MockInspectionRepository mockRepo;

    const testInspections = [
      Inspection(
        id: 1,
        inspectionNumber: 'INSP-001',
        title: 'EB Bunk Monthly Check',
        description: 'Earth resistance and cleaning',
        priority: InspectionPriority.high,
        status: InspectionStatus.pending,
        stationName: 'Thalanallur',
      ),
    ];

    setUp(() {
      mockRepo = MockInspectionRepository();
    });

    testWidgets('InspectionListScreen renders inspections and log button',
        (tester) async {
      when(() => mockRepo.fetchInspections())
          .thenAnswer((_) async => testInspections);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inspectionRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthenticatedController(_sessionWithInspectionsAdd),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const InspectionListScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Field Inspections'), findsOneWidget);
      expect(find.byKey(const Key('date_range_from')), findsOneWidget);
      expect(find.text('EB Bunk Monthly Check'), findsOneWidget);
      expect(find.text('INSP-001'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.byKey(const Key('fab_create_inspection')), findsOneWidget);
    });

    testWidgets(
        'tapping a logged inspection opens its detail screen with Convert action',
        (tester) async {
      when(() => mockRepo.fetchInspections())
          .thenAnswer((_) async => testInspections);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inspectionRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthenticatedController(_sessionWithInspectionsAdd),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const InspectionListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inspection_card_1')));
      await tester.pumpAndSettle();

      expect(find.byType(InspectionDetailScreen), findsOneWidget);
      expect(find.text('INSP-001'), findsOneWidget);
      expect(find.text('Earth resistance and cleaning'), findsOneWidget);
      // DEPOT_INCHARGE holding inspections.edit on an unconverted inspection
      // is exactly who ConversionService allows to convert.
      expect(find.byKey(const Key('convert_to_work_order_button')),
          findsOneWidget);
    });

    testWidgets(
        'Convert action is hidden for a non-depot role holding inspections.edit',
        (tester) async {
      when(() => mockRepo.fetchInspections())
          .thenAnswer((_) async => testInspections);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inspectionRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthenticatedController(_sessionNonDepotRole),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const InspectionListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inspection_card_1')));
      await tester.pumpAndSettle();

      expect(find.byType(InspectionDetailScreen), findsOneWidget);
      expect(
          find.byKey(const Key('convert_to_work_order_button')), findsNothing);
    });

    testWidgets(
        'Convert to Job Work calls the repository and shows the linked Work Order link',
        (tester) async {
      when(() => mockRepo.fetchInspections())
          .thenAnswer((_) async => testInspections);
      when(() => mockRepo.convertToWorkOrder(1)).thenAnswer(
        (_) async => {'message': 'Converted successfully', 'work_order_id': 42},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inspectionRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthenticatedController(_sessionWithInspectionsAdd),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const InspectionListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inspection_card_1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('convert_to_work_order_button')));
      await tester.pumpAndSettle();
      // Confirmation dialog.
      await tester.tap(find.text('Convert'));
      await tester.pumpAndSettle();

      verify(() => mockRepo.convertToWorkOrder(1)).called(1);
      expect(find.text('Converted successfully. Job Work created.'),
          findsOneWidget);
      // Off the initial viewport below the Location card — scroll to it like
      // a real user would rather than asserting on unpainted content.
      await tester.scrollUntilVisible(
        find.byKey(const Key('view_linked_work_order')),
        200,
      );
      expect(find.byKey(const Key('view_linked_work_order')), findsOneWidget);
    });

    testWidgets(
        'InspectionDetailScreen shows a link to the Work Order for an already-converted inspection',
        (tester) async {
      const converted = Inspection(
        id: 1,
        inspectionNumber: 'INSP-001',
        title: 'EB Bunk Monthly Check',
        status: InspectionStatus.converted,
        priority: InspectionPriority.high,
        isConverted: true,
        workOrderId: 42,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inspectionRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthenticatedController(_sessionWithInspectionsAdd),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const InspectionDetailScreen(inspection: converted),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('view_linked_work_order')),
        200,
      );
      expect(find.byKey(const Key('view_linked_work_order')), findsOneWidget);
      // Already converted: the Convert action must not be offered again.
      expect(
          find.byKey(const Key('convert_to_work_order_button')), findsNothing);
    });

    testWidgets('InspectionCreateScreen validates inputs and submits (web-parity form)',
        (tester) async {
      when(() => mockRepo.createInspection(
            title: any(named: 'title'),
            description: any(named: 'description'),
            priority: any(named: 'priority'),
            assetId: any(named: 'assetId'),
            depotId: any(named: 'depotId'),
            stationId: any(named: 'stationId'),
            infrastructureId: any(named: 'infrastructureId'),
            scheduledDate: any(named: 'scheduledDate'),
            inspectionPoints: any(named: 'inspectionPoints'),
          )).thenAnswer((_) async => testInspections[0]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inspectionRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthenticatedController(_sessionWithInspectionsAdd),
            ),
          ],
          child: const MaterialApp(home: InspectionCreateScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Initial validation: empty title + empty points
      await tester.ensureVisible(find.byKey(const Key('submit_inspection_button')));
      await tester.tap(find.byKey(const Key('submit_inspection_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a title'), findsOneWidget);
      expect(find.text('Please add at least one inspection point'), findsOneWidget);
      // Legacy hidden field still present for backward-compat finders (offstage)
      expect(find.byKey(const Key('inspection_description_field'), skipOffstage: false), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('inspection_title_field')), 'Test Title');
      // Points field may have been scrolled off — bring it back
      await tester.ensureVisible(find.byKey(const Key('inspection_point_field_0')));
      await tester.enterText(
          find.byKey(const Key('inspection_point_field_0')),
          'Detailed findings');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('submit_inspection_button')));
      await tester.tap(find.byKey(const Key('submit_inspection_button')));
      await tester.pumpAndSettle();

      final captured = verify(() => mockRepo.createInspection(
            title: captureAny(named: 'title'),
            description: captureAny(named: 'description'),
            priority: captureAny(named: 'priority'),
            assetId: captureAny(named: 'assetId'),
            depotId: captureAny(named: 'depotId'),
            stationId: captureAny(named: 'stationId'),
            infrastructureId: captureAny(named: 'infrastructureId'),
            scheduledDate: captureAny(named: 'scheduledDate'),
            inspectionPoints: captureAny(named: 'inspectionPoints'),
          )).captured;
      // captured is [title, description, priority, assetId, depotId, stationId, infraId, scheduledDate, inspectionPoints]
      expect(captured[0], 'Test Title');
      expect(captured[1], 'Detailed findings');
      expect(captured[2], 'MEDIUM');
      expect(captured[8], contains('Detailed findings'));
    });

    testWidgets('InspectionCreateScreen mirrors web Add Inspection Note layout',
        (tester) async {
      when(() => mockRepo.createInspection(
            title: any(named: 'title'),
            description: any(named: 'description'),
            priority: any(named: 'priority'),
            assetId: any(named: 'assetId'),
            depotId: any(named: 'depotId'),
            stationId: any(named: 'stationId'),
            infrastructureId: any(named: 'infrastructureId'),
            scheduledDate: any(named: 'scheduledDate'),
            inspectionPoints: any(named: 'inspectionPoints'),
          )).thenAnswer((_) async => testInspections[0]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inspectionRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => _FakeAuthenticatedController(_sessionWithInspectionsAdd),
            ),
          ],
          child: const MaterialApp(home: InspectionCreateScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Web header + depot/title/date/location/points/cancel/save all present
      // Labels are RichText (wrapping fix) — match via plain-text predicate.
      Finder richLabel(String s) => find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains(s));
      expect(find.text('Add Inspection Note'), findsWidgets);
      expect(find.byKey(const Key('inspection_depot_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('inspection_title_field')), findsOneWidget);
      expect(richLabel('Title / Subject'), findsOneWidget);
      expect(find.byKey(const Key('inspection_date_field')), findsOneWidget);
      expect(richLabel('Date of Inspection'), findsOneWidget);
      expect(find.text('Location Details (Optional)'), findsOneWidget);
      expect(find.byKey(const Key('inspection_infra_type_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('inspection_location_dropdown')), findsOneWidget);
      expect(richLabel('Inspection Points'), findsOneWidget);
      expect(find.byKey(const Key('inspection_point_field_0')), findsOneWidget);
      expect(find.byKey(const Key('add_inspection_point_button')), findsOneWidget);
      expect(find.byKey(const Key('cancel_inspection_button')), findsOneWidget);
      expect(find.byKey(const Key('submit_inspection_button')), findsOneWidget);
      expect(find.text('Save Inspection'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Add Point creates a new row
      await tester.ensureVisible(find.byKey(const Key('add_inspection_point_button')));
      await tester.tap(find.byKey(const Key('add_inspection_point_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inspection_point_field_1')), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);

      // Fill both points
      await tester.ensureVisible(find.byKey(const Key('inspection_point_field_0')));
      await tester.enterText(find.byKey(const Key('inspection_point_field_0')), 'Point A');
      await tester.ensureVisible(find.byKey(const Key('inspection_point_field_1')));
      await tester.enterText(find.byKey(const Key('inspection_point_field_1')), 'Point B');
      await tester.pumpAndSettle();

      // Remove second point
      await tester.ensureVisible(find.byKey(const Key('remove_inspection_point_1')));
      await tester.tap(find.byKey(const Key('remove_inspection_point_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inspection_point_field_1')), findsNothing);

      // Title still required if empty
      await tester.enterText(find.byKey(const Key('inspection_title_field')), 'Web Title');
      await tester.ensureVisible(find.byKey(const Key('submit_inspection_button')));
      await tester.tap(find.byKey(const Key('submit_inspection_button')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.createInspection(
            title: 'Web Title',
            description: 'Point A',
            priority: any(named: 'priority'),
            assetId: any(named: 'assetId'),
            depotId: any(named: 'depotId'),
            stationId: any(named: 'stationId'),
            infrastructureId: any(named: 'infrastructureId'),
            scheduledDate: any(named: 'scheduledDate'),
            inspectionPoints: any(named: 'inspectionPoints'),
          )).called(1);
    });
  });
}
