import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/complaints/data/complaint_repository.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/complaint_status_style.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_detail_screen.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

class _Complaints extends Mock implements IComplaintRepository {}
class _WorkOrders extends Mock implements IWorkOrderRepository {}
class _Auth extends AuthController {
  @override
  AuthState build() => const Authenticated(UserSession(
    accessToken: 'test', username: 'supervisor', primaryRole: AuthRole.depotIncharge,
    roles: [AuthRole.depotIncharge], permissions: ['complaints.view', 'maintenance.view'],
    scope: OrgScope(level: OrgScopeLevel.depot),
  ));
}

Complaint _complaint(String status, {bool effective = true}) => Complaint(
  id: 7, title: 'Pump failure', status: ComplaintStatus.converted,
  isConverted: true, workOrderId: 42, workOrderTicketNumber: 'JW-42',
  workOrderStatus: status, effectiveStatus: effective ? status : null,
);

void main() {
  for (final entry in {'VERIFIED': 'Verified', 'CLOSED': 'Closed'}.entries) {
    for (final effective in [true, false]) {
      testWidgets('primary breakdown badge shows ${entry.key}, effective=$effective', (tester) async {
        final complaint = _complaint(entry.key, effective: effective);
        await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme,
          home: Scaffold(body: Column(children: [
            ComplaintStatusChip(complaint: complaint),
            ComplaintEffectiveChip(complaint: complaint),
          ]))));
        expect(find.text(entry.value), findsOneWidget);
        expect(find.text('Converted'), findsNothing);
        // The persisted record remains converted for audit and edit guards.
        expect(complaint.status, ComplaintStatus.converted);
      });
    }
  }

  testWidgets('returning from linked Job Work refreshes breakdown status', (tester) async {
    final complaints = _Complaints();
    final workOrders = _WorkOrders();
    var reads = 0;
    when(() => complaints.fetchComplaintById(7)).thenAnswer((_) async =>
      _complaint(++reads == 1 ? 'IN_PROGRESS' : 'CLOSED'));
    // The destination can fail to load; returning must still refresh the parent.
    when(() => workOrders.fetchWorkOrderById(42)).thenAnswer((_) async => throw Exception('Offline'));
    await tester.pumpWidget(ProviderScope(overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      complaintRepositoryProvider.overrideWithValue(complaints),
      workOrderRepositoryProvider.overrideWithValue(workOrders),
    ], child: MaterialApp(theme: AppTheme.lightTheme,
      home: ComplaintDetailScreen(complaint: _complaint('IN_PROGRESS')))));
    await tester.pumpAndSettle();
    expect(reads, 1);
    final link = find.byKey(const Key('view_linked_job_work_button'));
    await tester.scrollUntilVisible(link, 250);
    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(reads, 2);
    await tester.scrollUntilVisible(find.text('Closed'), -250);
    expect(find.text('Closed'), findsOneWidget);
  });
}
