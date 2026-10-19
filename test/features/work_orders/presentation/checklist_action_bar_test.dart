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
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_action_bar.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fake_auth.dart';

class _MockRepo extends Mock implements IWorkOrderRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChecklistLoaded.firstIncompleteRequiredLine', () {
    test('returns first incomplete required line in display order', () {
      const record = MaintenanceRecord(
        id: 1,
        lines: [
          MaintenanceRecordLine(
            id: 10,
            itemName: 'Item A',
            assetCategory: 'Cat A',
            isRequired: true,
            recordedValue: 'OK',
            checkedOut: true,
          ),
          MaintenanceRecordLine(
            id: 20,
            itemName: 'Item A',
            assetCategory: 'Cat A',
            isRequired: true,
            checkedOut: true,
          ),
          MaintenanceRecordLine(
            id: 30,
            itemName: 'Item B',
            assetCategory: 'Cat B',
            isRequired: true,
            checkedOut: true,
          ),
        ],
      );

      const state = ChecklistLoaded(record: record);
      expect(state.firstIncompleteRequiredLine?.id, 20);
      expect(state.remainingRequired, 2);
    });

    test('ignores non-required lines when explicit isRequired lines exist', () {
      const record = MaintenanceRecord(
        id: 1,
        lines: [
          MaintenanceRecordLine(
            id: 10,
            itemName: 'Item A',
            assetCategory: 'Cat A',
            isRequired: false,
            checkedOut: true,
          ),
          MaintenanceRecordLine(
            id: 20,
            itemName: 'Item A',
            assetCategory: 'Cat A',
            isRequired: true,
            checkedOut: true,
          ),
        ],
      );

      const state = ChecklistLoaded(record: record);
      expect(state.firstIncompleteRequiredLine?.id, 20);
      expect(state.remainingRequired, 1);
    });

    test('all active lines count when none has explicit isRequired', () {
      const record = MaintenanceRecord(
        id: 1,
        lines: [
          MaintenanceRecordLine(
            id: 10,
            itemName: 'Item A',
            assetCategory: 'Cat A',
            recordedValue: 'OK',
            checkedOut: true,
          ),
          MaintenanceRecordLine(
            id: 20,
            itemName: 'Item B',
            assetCategory: 'Cat B',
            checkedOut: true,
          ),
        ],
      );

      const state = ChecklistLoaded(record: record);
      expect(state.firstIncompleteRequiredLine?.id, 20);
      expect(state.remainingRequired, 1);
    });

    test('skips not-checked-out and excluded lines', () {
      const record = MaintenanceRecord(
        id: 1,
        lines: [
          MaintenanceRecordLine(
            id: 10,
            itemName: 'Item A',
            assetCategory: 'Cat A',
            excluded: true,
          ),
          MaintenanceRecordLine(
            id: 20,
            itemName: 'Item B',
            assetCategory: 'Cat B',
            checkedOut: false,
          ),
          MaintenanceRecordLine(
            id: 30,
            itemName: 'Item C',
            assetCategory: 'Cat C',
            checkedOut: true,
          ),
        ],
      );

      const state = ChecklistLoaded(record: record);
      expect(state.firstIncompleteRequiredLine?.id, 30);
      expect(state.remainingRequired, 1);
    });

    test('returns null when all required lines are completed', () {
      const record = MaintenanceRecord(
        id: 1,
        lines: [
          MaintenanceRecordLine(
            id: 10,
            itemName: 'Item A',
            assetCategory: 'Cat A',
            recordedValue: 'OK',
            checkedOut: true,
          ),
        ],
      );

      const state = ChecklistLoaded(record: record);
      expect(state.firstIncompleteRequiredLine, isNull);
      expect(state.remainingRequired, 0);
      expect(state.canSubmit, isTrue);
    });
  });

  group('ChecklistActionBar widget unit tests', () {
    testWidgets('shows Sign & Submit and remaining hint when incomplete',
        (tester) async {
      var submitted = false;
      var jumped = false;

      const record = MaintenanceRecord(
        id: 1,
        lines: [
          MaintenanceRecordLine(id: 10, itemName: 'A', checkedOut: true),
          MaintenanceRecordLine(id: 20, itemName: 'B', checkedOut: true),
          MaintenanceRecordLine(id: 30, itemName: 'C', checkedOut: true),
        ],
      );
      const state = ChecklistLoaded(record: record);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              bottomNavigationBar: ChecklistActionBar(
                state: state,
                onSignAndSubmit: () => submitted = true,
                onIncompleteTap: () => jumped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('complete_checklist_button')), findsOneWidget);
      expect(find.text('Sign & Submit'), findsOneWidget);
      expect(find.byKey(const Key('checklist_remaining_hint')), findsOneWidget);
      expect(find.text('3 required items left'), findsOneWidget);

      await tester.tap(find.byKey(const Key('complete_checklist_button')));
      expect(jumped, isTrue);
      expect(submitted, isFalse);
    });

    testWidgets('singular helper text when 1 item left', (tester) async {
      const record = MaintenanceRecord(
        id: 1,
        lines: [
          MaintenanceRecordLine(id: 10, itemName: 'A', checkedOut: true),
        ],
      );
      const state = ChecklistLoaded(record: record);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              bottomNavigationBar: ChecklistActionBar(
                state: state,
                onSignAndSubmit: () {},
                onIncompleteTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('1 required item left'), findsOneWidget);
    });

    testWidgets('hides remaining hint and calls onSignAndSubmit at 0',
        (tester) async {
      var submitted = false;
      var jumped = false;

      const record = MaintenanceRecord(
        id: 1,
        lines: [
          MaintenanceRecordLine(id: 10, itemName: 'A', recordedValue: 'OK', checkedOut: true),
        ],
      );
      const state = ChecklistLoaded(record: record);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              bottomNavigationBar: ChecklistActionBar(
                state: state,
                onSignAndSubmit: () => submitted = true,
                onIncompleteTap: () => jumped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Sign & Submit'), findsOneWidget);
      expect(find.byKey(const Key('checklist_remaining_hint')), findsNothing);

      await tester.tap(find.byKey(const Key('complete_checklist_button')));
      expect(submitted, isTrue);
      expect(jumped, isFalse);
    });

    testWidgets('disables button and shows spinner while submitting',
        (tester) async {
      const record = MaintenanceRecord(id: 1, lines: []);
      const state = ChecklistLoaded(record: record, isSubmitting: true);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              bottomNavigationBar: ChecklistActionBar(
                state: state,
                onSignAndSubmit: () {},
                onIncompleteTap: () {},
              ),
            ),
          ),
        ),
      );

      final btn = tester.widget<FilledButton>(find.byKey(const Key('complete_checklist_button')));
      expect(btn.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('ChecklistScreen completion button interaction', () {
    late _MockRepo mockRepo;

    setUp(() {
      mockRepo = _MockRepo();
    });

    Future<void> pumpScreen(WidgetTester tester, MaintenanceRecord record) async {
      tester.view.physicalSize = const Size(1080, 2412);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      when(() => mockRepo.fetchMaintenanceRecord(record.id))
          .thenAnswer((_) async => record);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheServiceProvider.overrideWithValue(InMemoryLocalCacheService()),
            workOrderRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(
                fakeSession(role: AuthRole.maintenanceStaff),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: ChecklistScreen(recordId: record.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        'label is "Sign & Submit" with "3 required items left"; tap jumps, highlights first incomplete line and shows snackbar without opening completion sheet',
        (tester) async {
      const record = MaintenanceRecord(
        id: 77,
        lines: [
          MaintenanceRecordLine(
            id: 101,
            itemName: 'Pump A',
            assetCategory: 'Mechanical',
            isRequired: true,
            recordedValue: 'OK',
            checkedOut: true,
          ),
          MaintenanceRecordLine(
            id: 102,
            itemName: 'Pump B',
            assetCategory: 'Mechanical',
            isRequired: true,
            checkedOut: true,
          ),
          MaintenanceRecordLine(
            id: 103,
            itemName: 'Valve C',
            assetCategory: 'Mechanical',
            isRequired: true,
            checkedOut: true,
          ),
          MaintenanceRecordLine(
            id: 104,
            itemName: 'Sensor D',
            assetCategory: 'Electrical',
            isRequired: true,
            checkedOut: true,
          ),
        ],
      );

      await pumpScreen(tester, record);

      // Verify button label and helper text
      expect(find.byKey(const Key('complete_checklist_button')), findsOneWidget);
      expect(find.text('Sign & Submit'), findsOneWidget);
      expect(find.text('3 required items left'), findsOneWidget);

      // Tap Sign & Submit while incomplete
      await tester.tap(find.byKey(const Key('complete_checklist_button')));
      await tester.pump();

      // Does NOT open completion sheet
      expect(find.byKey(const Key('completion_confirm_button')), findsNothing);

      // Scrolls and highlights the first incomplete line (102)
      expect(find.byKey(const Key('checklist_line_102_highlighted')), findsOneWidget);
      expect(find.byKey(const Key('checklist_line_highlighted')), findsOneWidget);
      expect(find.byKey(const Key('checklist_line_103_highlighted')), findsNothing);

      // Shows the snackbar
      expect(find.text('Complete the highlighted item first (3 left).'), findsOneWidget);

      // Wait 3s: highlight clears
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const Key('checklist_line_102_highlighted')), findsNothing);
      expect(find.byKey(const Key('checklist_line_102')), findsOneWidget);
    });

    testWidgets(
        'clears subsystem filter that hides first incomplete line when tapped',
        (tester) async {
      const record = MaintenanceRecord(
        id: 88,
        lines: [
          MaintenanceRecordLine(
            id: 201,
            itemName: 'Transformer',
            assetCategory: 'Electrical',
            checkedOut: true,
          ),
          MaintenanceRecordLine(
            id: 202,
            itemName: 'Pump',
            assetCategory: 'Mechanical',
            recordedValue: 'OK',
            checkedOut: true,
          ),
        ],
      );

      await pumpScreen(tester, record);

      // Select 'Mechanical' subsystem filter so 'Electrical' (line 201) is hidden
      final dropdownFinder = find.byKey(const Key('checklist_subsystem_filter_dropdown'));
      expect(dropdownFinder, findsOneWidget);
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mechanical (1)').last);
      await tester.pumpAndSettle();

      // Line 201 is now hidden
      expect(find.byKey(const Key('checklist_line_201')), findsNothing);

      // Tap Sign & Submit
      await tester.tap(find.byKey(const Key('complete_checklist_button')));
      await tester.pumpAndSettle();

      // Subsystem filter was cleared, line 201 is visible and highlighted
      expect(find.byKey(const Key('checklist_line_201_highlighted')), findsOneWidget);
      expect(find.text('Complete the highlighted item first (1 left).'), findsOneWidget);
    });

    testWidgets('at 0 required items left, tapping opens completion sheet',
        (tester) async {
      const record = MaintenanceRecord(
        id: 99,
        lines: [
          MaintenanceRecordLine(
            id: 301,
            itemName: 'Transformer',
            assetCategory: 'Electrical',
            recordedValue: 'OK',
            checkedOut: true,
          ),
        ],
      );

      await pumpScreen(tester, record);

      expect(find.text('Sign & Submit'), findsOneWidget);
      expect(find.byKey(const Key('checklist_remaining_hint')), findsNothing);

      // Tapping opens the completion dialog / sheet
      await tester.tap(find.byKey(const Key('complete_checklist_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('completion_confirm_button')), findsOneWidget);
    });
  });
}
