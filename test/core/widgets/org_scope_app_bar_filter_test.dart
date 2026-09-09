import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/widgets/org_scope_app_bar_filter.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';

void main() {
  group('OrgScopeAppBarFilter Widget Tests', () {
    testWidgets('collapses to nothing when user is depot-scoped and enableStation is false', (tester) async {
      const depotScope = OrgScope(
        level: OrgScopeLevel.depot,
        depot: OrgUnitInfo(id: 10, code: 'VRI', name: 'Vriddhachalam Depot'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                OrgScopeAppBarFilter(
                  scope: depotScope,
                  selection: OrgScopeSelection.empty,
                  enableStation: false,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('org_scope_filter_icon')), findsNothing);
      expect(find.byKey(const Key('org_scope_active_chip')), findsNothing);
    });

    testWidgets('renders plain filter icon when selection is empty', (tester) async {
      const globalScope = OrgScope(level: OrgScopeLevel.global);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                OrgScopeAppBarFilter(
                  scope: globalScope,
                  selection: OrgScopeSelection.empty,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('org_scope_filter_icon')), findsOneWidget);
      expect(find.byKey(const Key('org_scope_active_chip')), findsNothing);
    });

    testWidgets('renders active chip when depot is selected in selection', (tester) async {
      const globalScope = OrgScope(level: OrgScopeLevel.global);
      const selectionWithDepot = OrgScopeSelection(
        zoneId: 1,
        divisionId: 2,
        depotId: 3,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                OrgScopeAppBarFilter(
                  scope: globalScope,
                  selection: selectionWithDepot,
                  depotLabel: 'Vriddhachalam',
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('org_scope_filter_icon')), findsNothing);
      expect(find.byKey(const Key('org_scope_active_chip')), findsOneWidget);
      expect(find.text('Depot: Vriddhachalam ▾'), findsOneWidget);
    });

    testWidgets('tapping filter icon opens bottom sheet with Done and Clear buttons', (tester) async {
      const globalScope = OrgScope(level: OrgScopeLevel.global);
      OrgScopeSelection? changedSelection;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                OrgScopeAppBarFilter(
                  scope: globalScope,
                  selection: const OrgScopeSelection(depotId: 5),
                  onChanged: (s) {
                    changedSelection = s;
                  },
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('org_scope_active_chip')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('org_scope_bottom_sheet')), findsOneWidget);
      expect(find.byKey(const Key('org_scope_done_button')), findsOneWidget);
      expect(find.byKey(const Key('org_scope_clear_button')), findsOneWidget);

      // Tapping Clear notifies empty selection and closes bottom sheet
      await tester.tap(find.byKey(const Key('org_scope_clear_button')));
      await tester.pumpAndSettle();

      expect(changedSelection, equals(OrgScopeSelection.empty));
      expect(find.byKey(const Key('org_scope_bottom_sheet')), findsNothing);
    });

    testWidgets('shows filter icon for depot scope with station available (parity with bar)', (tester) async {
      const depotScope = OrgScope(
        level: OrgScopeLevel.depot,
        depot: OrgUnitInfo(id: 10, code: 'VRI', name: 'Vriddhachalam Depot'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                OrgScopeAppBarFilter(
                  scope: depotScope,
                  selection: OrgScopeSelection.empty,
                  enableStation: true,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      // The bar would offer Station here, so the chip must not collapse.
      expect(find.byKey(const Key('org_scope_filter_icon')), findsOneWidget);
    });

    testWidgets('collapses when no depot is resolved and only station could apply', (tester) async {
      const selfScope = OrgScope(level: OrgScopeLevel.self);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                OrgScopeAppBarFilter(
                  scope: selfScope,
                  selection: OrgScopeSelection.empty,
                  enableStation: true,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('org_scope_filter_icon')), findsNothing);
      expect(find.byKey(const Key('org_scope_active_chip')), findsNothing);
    });

    testWidgets('chip label uses own depot name instead of #id', (tester) async {
      const depotScope = OrgScope(
        level: OrgScopeLevel.depot,
        depot: OrgUnitInfo(id: 10, code: 'VRI', name: 'Vriddhachalam Depot'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                OrgScopeAppBarFilter(
                  scope: depotScope,
                  selection: const OrgScopeSelection(depotId: 10),
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Depot: Vriddhachalam Depot ▾'), findsOneWidget);
    });
  });

  group('OrgScopeFilterBar.hasFilterableOptions parity', () {
    test('matches the bar build predicates across scope levels', () {
      const empty = OrgScopeSelection.empty;
      expect(
        OrgScopeFilterBar.hasFilterableOptions(
          scope: const OrgScope(level: OrgScopeLevel.global),
          selection: empty,
        ),
        isTrue,
      );
      expect(
        OrgScopeFilterBar.hasFilterableOptions(
          scope: const OrgScope(level: OrgScopeLevel.depot),
          selection: empty,
          enableStation: false,
        ),
        isFalse,
      );
      expect(
        OrgScopeFilterBar.hasFilterableOptions(
          scope: const OrgScope(
            level: OrgScopeLevel.depot,
            depot: OrgUnitInfo(id: 10, name: 'Vriddhachalam Depot'),
          ),
          selection: empty,
          enableStation: true,
        ),
        isTrue,
      );
      expect(
        OrgScopeFilterBar.hasFilterableOptions(
          scope: const OrgScope(level: OrgScopeLevel.self),
          selection: empty,
          enableStation: true,
        ),
        isFalse,
      );
      // Reports-style: zone/division disabled still offers Depot globally.
      expect(
        OrgScopeFilterBar.hasFilterableOptions(
          scope: const OrgScope(level: OrgScopeLevel.global),
          selection: empty,
          enableZoneDivision: false,
        ),
        isTrue,
      );
    });
  });
}
