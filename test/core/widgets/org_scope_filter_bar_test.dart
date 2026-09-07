import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/data/org_scope_options_service.dart';
import 'package:gssms_mobile/core/domain/org_option.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:mocktail/mocktail.dart';

class MockOrgScopeOptionsService extends Mock implements OrgScopeOptionsService {}

void main() {
  late MockOrgScopeOptionsService mockService;

  setUp(() {
    mockService = MockOrgScopeOptionsService();
    when(() => mockService.fetchZones()).thenAnswer((_) async => const []);
    when(() => mockService.fetchDivisions(zoneId: any(named: 'zoneId')))
        .thenAnswer((_) async => const []);
    when(() => mockService.fetchDepots(
          zoneId: any(named: 'zoneId'),
          divisionId: any(named: 'divisionId'),
        )).thenAnswer((_) async => const []);
    when(() => mockService.fetchStations(depotId: any(named: 'depotId')))
        .thenAnswer((_) async => const []);
  });

  Future<void> pump(WidgetTester tester, OrgScope scope, {OrgScopeSelection? selection}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [orgScopeOptionsServiceProvider.overrideWithValue(mockService)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: OrgScopeFilterBar(
              scope: scope,
              selection: selection ?? OrgScopeSelection.empty,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('OrgScopeFilterBar visibility per session.scope.level', () {
    testWidgets('GLOBAL scope shows Zone, Division and Depot', (tester) async {
      await pump(tester, const OrgScope(level: OrgScopeLevel.global));

      expect(find.byKey(const Key('org_scope_zone')), findsOneWidget);
      expect(find.byKey(const Key('org_scope_division')), findsOneWidget);
      expect(find.byKey(const Key('org_scope_depot')), findsOneWidget);
      expect(find.byKey(const Key('org_scope_station')), findsNothing);
    });

    testWidgets('ZONE scope shows Division and Depot but not Zone', (tester) async {
      await pump(
        tester,
        const OrgScope(level: OrgScopeLevel.zone, zone: OrgUnitInfo(id: 1, name: 'Southern Railway')),
      );

      expect(find.byKey(const Key('org_scope_zone')), findsNothing);
      expect(find.byKey(const Key('org_scope_division')), findsOneWidget);
      expect(find.byKey(const Key('org_scope_depot')), findsOneWidget);
    });

    testWidgets('DIVISION scope shows Depot only', (tester) async {
      await pump(
        tester,
        const OrgScope(
          level: OrgScopeLevel.division,
          zone: OrgUnitInfo(id: 1, name: 'Southern Railway'),
          division: OrgUnitInfo(id: 2, name: 'Tiruchchirappalli'),
        ),
      );

      expect(find.byKey(const Key('org_scope_zone')), findsNothing);
      expect(find.byKey(const Key('org_scope_division')), findsNothing);
      expect(find.byKey(const Key('org_scope_depot')), findsOneWidget);
    });

    testWidgets('DEPOT scope shows nothing (Station too, since no depot is selectable)', (tester) async {
      await pump(
        tester,
        const OrgScope(
          level: OrgScopeLevel.depot,
          depot: OrgUnitInfo(id: 9, name: 'Vriddhachalam Depot'),
        ),
      );

      expect(find.byKey(const Key('org_scope_zone')), findsNothing);
      expect(find.byKey(const Key('org_scope_division')), findsNothing);
      expect(find.byKey(const Key('org_scope_depot')), findsNothing);
      // The user's own depot is already fixed, so Station appears directly.
      expect(find.byKey(const Key('org_scope_station')), findsOneWidget);
    });

    testWidgets('enableStation: false suppresses Station even at DEPOT scope', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [orgScopeOptionsServiceProvider.overrideWithValue(mockService)],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: OrgScopeFilterBar(
                scope: const OrgScope(
                  level: OrgScopeLevel.depot,
                  depot: OrgUnitInfo(id: 9, name: 'Vriddhachalam Depot'),
                ),
                selection: OrgScopeSelection.empty,
                enableStation: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('org_scope_station')), findsNothing);
    });

    testWidgets('enableZoneDivision: false always shows Depot only, regardless of scope',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [orgScopeOptionsServiceProvider.overrideWithValue(mockService)],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: OrgScopeFilterBar(
                scope: const OrgScope(level: OrgScopeLevel.global),
                selection: OrgScopeSelection.empty,
                enableZoneDivision: false,
                enableStation: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('org_scope_zone')), findsNothing);
      expect(find.byKey(const Key('org_scope_division')), findsNothing);
      expect(find.byKey(const Key('org_scope_depot')), findsOneWidget);
    });

    // Regression: an enableZoneDivision:false caller (Reports) used to force
    // the Depot dropdown on even for a viewer already fixed to one depot,
    // where it could only ever offer that same single depot — pointless UI.
    testWidgets(
        'enableZoneDivision: false hides Depot for a viewer already fixed to one depot',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [orgScopeOptionsServiceProvider.overrideWithValue(mockService)],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: OrgScopeFilterBar(
                scope: const OrgScope(
                  level: OrgScopeLevel.depot,
                  depot: OrgUnitInfo(id: 9, name: 'Vriddhachalam Depot'),
                ),
                selection: OrgScopeSelection.empty,
                enableZoneDivision: false,
                enableStation: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('org_scope_depot')), findsNothing);
    });
  });

  testWidgets('picking a zone from the dropdown reports it and loads its divisions',
      (tester) async {
    when(() => mockService.fetchZones()).thenAnswer(
      (_) async => const [OrgOption(id: 1, name: 'Southern Railway')],
    );
    when(() => mockService.fetchDivisions(zoneId: 1)).thenAnswer(
      (_) async => const [OrgOption(id: 2, name: 'Tiruchchirappalli')],
    );

    OrgScopeSelection? changed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [orgScopeOptionsServiceProvider.overrideWithValue(mockService)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: OrgScopeFilterBar(
              scope: const OrgScope(level: OrgScopeLevel.global),
              selection: OrgScopeSelection.empty,
              onChanged: (s) => changed = s,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('org_scope_zone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Southern Railway').last);
    await tester.pumpAndSettle();

    expect(changed?.zoneId, 1);
    verify(() => mockService.fetchDivisions(zoneId: 1)).called(1);
  });
}
