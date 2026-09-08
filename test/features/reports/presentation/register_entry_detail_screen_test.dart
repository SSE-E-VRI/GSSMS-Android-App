import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/reports/domain/models/maintenance_register_entry.dart';
import 'package:gssms_mobile/features/reports/presentation/screens/register_entry_detail_screen.dart';
import '../../../helpers/fake_auth.dart';

void main() {
  const entry = MaintenanceRegisterEntry(
    id: 1,
    masterName: 'MTUR-202608-0016',
    depotName: 'Vriddhachalam Depot',
    technician: 'gmani',
    supervisor: 'vri',
    items: [
      RegisterLineItem(
        assetName: 'EB Bunk',
        inspection: 'Check and clean the EB meter bunk',
        status: 'DIRTY',
        statusLabel: 'Dirty',
        action: 'Cleaned',
      ),
      RegisterLineItem(
        assetName: 'EB Bunk',
        inspection: 'Check the discolouration of wires',
        status: 'NORMAL',
        statusLabel: 'Found normal',
        action: 'Tightened',
      ),
      RegisterLineItem(
        assetName: 'Earth Pit',
        inspection: 'Check whether 2 earth pits are available',
        status: 'OK',
        statusLabel: 'Available',
        action: 'No action required',
      ),
    ],
  );

  Widget wrap(
    MaintenanceRegisterEntry e, {
    List<String> permissions = const ['reports.view', 'reports.export'],
  }) {
    return ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthenticatedController(fakeSession(
            permissions: permissions,
          )),
        ),
      ],
      child: MaterialApp(home: RegisterEntryDetailScreen(entry: e)),
    );
  }

  testWidgets('groups checklist rows by Asset/Equipment with the requested columns',
      (tester) async {
    await tester.pumpWidget(wrap(entry));
    await tester.pumpAndSettle();

    // One card per distinct asset, not one row per checklist item.
    expect(find.byKey(const Key('asset_group_EB Bunk')), findsOneWidget);
    expect(find.byKey(const Key('asset_group_Earth Pit')), findsOneWidget);
    expect(find.text('EB Bunk'), findsOneWidget);
    expect(find.text('Earth Pit'), findsOneWidget);

    // Table header matches the requested column set exactly.
    expect(find.text('Checkpoint/Parameter'), findsWidgets);
    expect(find.text('Status'), findsWidgets);
    expect(find.text('Action Taken'), findsWidgets);

    // Row content lands in the right columns.
    expect(find.text('Check and clean the EB meter bunk'), findsOneWidget);
    expect(find.text('Dirty'), findsOneWidget);
    expect(find.text('Cleaned'), findsOneWidget);
  });

  testWidgets('offers a PDF download action when reports.export is granted',
      (tester) async {
    await tester.pumpWidget(wrap(entry));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action_download_register_pdf')), findsOneWidget);
  });

  // RBAC-01 regression: reports.view must not substitute for reports.export.
  testWidgets('hides the PDF download action for reports.view without reports.export',
      (tester) async {
    await tester.pumpWidget(wrap(entry, permissions: const ['reports.view']));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('action_download_register_pdf')), findsNothing);
  });

  testWidgets('shows an empty state when the entry has no line items', (tester) async {
    const empty = MaintenanceRegisterEntry(id: 2, masterName: 'Empty Register');
    await tester.pumpWidget(wrap(empty));
    await tester.pumpAndSettle();

    expect(find.text('No recorded line items found for this entry.'), findsOneWidget);
  });
}
