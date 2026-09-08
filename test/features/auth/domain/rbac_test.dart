import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';

void main() {
  const maintenanceViewSession = UserSession(
    accessToken: 't',
    username: 'u',
    primaryRole: AuthRole.depotIncharge,
    permissions: ['maintenance.view'],
  );

  const reportsViewOnlySession = UserSession(
    accessToken: 't',
    username: 'u',
    primaryRole: AuthRole.depotUser,
    permissions: ['reports.view'],
  );

  const reportsExportSession = UserSession(
    accessToken: 't',
    username: 'u',
    primaryRole: AuthRole.depotIncharge,
    permissions: ['reports.view', 'reports.export'],
  );

  test('sessionAllows is fail-closed for a null session', () {
    expect(sessionAllows(null, 'maintenance.view'), isFalse);
  });

  test('sessionAllows requires an exact JWT permission', () {
    expect(sessionAllows(maintenanceViewSession, 'maintenance.view'), isTrue);
    expect(sessionAllows(maintenanceViewSession, 'dashboard.view'), isFalse);
  });

  group('canExportPdf', () {
    test('denies a missing session', () {
      expect(canExportPdf(null), isFalse);
    });

    test('requires reports.export specifically, not a substitute', () {
      expect(canExportPdf(reportsExportSession), isTrue);
    });

    // RBAC-01/RBAC-02 regression: reports.view and maintenance.view must
    // never substitute for reports.export. The backend enforces export as
    // strictly additive (WorkOrderReportViewSet._get_filters,
    // MaintenanceRecordViewSet.export_history both 403 on reports.export
    // alone), so DEPOT_USER/CONTROL_CELL/EB_BILL_CLERK/GUEST/VIEWER
    // (reports.view but no reports.export) and MAINTENANCE_STAFF/QR_GUEST
    // (maintenance.view but no reports permission at all) must be denied.
    test('reports.view alone does not grant export (RBAC-01)', () {
      expect(canExportPdf(reportsViewOnlySession), isFalse);
    });

    test('maintenance.view alone does not grant export (RBAC-02)', () {
      expect(canExportPdf(maintenanceViewSession), isFalse);
    });
  });
}
