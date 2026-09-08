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

  test('wildcard permission grants every code', () {
      const wildcard = UserSession(
        accessToken: 't',
        username: 'u',
        primaryRole: AuthRole.superAdmin,
        roles: [AuthRole.superAdmin],
        permissions: ['*'],
      );
      expect(sessionAllows(wildcard, 'maintenance.edit'), isTrue);
      expect(sessionAllows(wildcard, 'reports.export'), isTrue);
      expect(canExportPdf(wildcard), isTrue);
    });

    test('sessionAllowsAny is fail-closed and matches any listed code', () {
      expect(sessionAllowsAny(null, ['maintenance.view']), isFalse);
      expect(
        sessionAllowsAny(maintenanceViewSession, ['dashboard.view', 'maintenance.view']),
        isTrue,
      );
      expect(
        sessionAllowsAny(maintenanceViewSession, ['dashboard.view', 'reports.export']),
        isFalse,
      );
    });

    group('canCreateWorkOrder', () {
      test('requires maintenance.create and a depot create role', () {
        const incharge = UserSession(
          accessToken: 't',
          username: 'u',
          primaryRole: AuthRole.depotIncharge,
          roles: [AuthRole.depotIncharge],
          permissions: ['maintenance.create'],
        );
        expect(canCreateWorkOrder(incharge), isTrue);
      });

      test('denies admin roles that hold maintenance.create', () {
        const admin = UserSession(
          accessToken: 't',
          username: 'u',
          primaryRole: AuthRole.divAdmin,
          roles: [AuthRole.divAdmin],
          permissions: ['maintenance.create', '*'],
        );
        expect(canCreateWorkOrder(admin), isFalse);
      });

      test('denies depot incharge without maintenance.create', () {
        const incharge = UserSession(
          accessToken: 't',
          username: 'u',
          primaryRole: AuthRole.depotIncharge,
          roles: [AuthRole.depotIncharge],
          permissions: ['maintenance.view'],
        );
        expect(canCreateWorkOrder(incharge), isFalse);
      });
    });

    group('canConvertInspection', () {
      test('allows depot incharge with inspections.edit', () {
        const incharge = UserSession(
          accessToken: 't',
          username: 'u',
          primaryRole: AuthRole.depotIncharge,
          roles: [AuthRole.depotIncharge],
          permissions: ['inspections.edit'],
        );
        expect(canConvertInspection(incharge), isTrue);
      });

      test('denies zone/division admins that hold inspections.edit', () {
        const zr = UserSession(
          accessToken: 't',
          username: 'u',
          primaryRole: AuthRole.zrAdmin,
          roles: [AuthRole.zrAdmin],
          permissions: ['inspections.edit', '*'],
        );
        expect(canConvertInspection(zr), isFalse);
      });
    });

    group('canWriteChecklist', () {
      test('allows maintenance staff with maintenance.edit', () {
        const staff = UserSession(
          accessToken: 't',
          username: 'u',
          primaryRole: AuthRole.maintenanceStaff,
          roles: [AuthRole.maintenanceStaff],
          permissions: ['maintenance.edit'],
        );
        expect(canWriteChecklist(staff), isTrue);
      });

      test('denies depot incharge despite maintenance.edit', () {
        const incharge = UserSession(
          accessToken: 't',
          username: 'u',
          primaryRole: AuthRole.depotIncharge,
          roles: [AuthRole.depotIncharge],
          permissions: ['maintenance.edit'],
        );
        expect(canWriteChecklist(incharge), isFalse);
      });
    });
}
