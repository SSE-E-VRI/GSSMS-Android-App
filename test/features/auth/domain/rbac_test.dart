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

  group('WP5 helpers', () {
    UserSession sess(AuthRole role, List<String> perms) => UserSession(
          accessToken: 't',
          username: 'u',
          primaryRole: role,
          roles: [role],
          permissions: perms,
        );
    const edit = ['maintenance.edit'];

    test('canReassignWorkOrder', () {
      expect(canReassignWorkOrder(null), isFalse);
      expect(canReassignWorkOrder(sess(AuthRole.depotUser, edit)), isTrue);
      // SSOT §5.1: admin tier is awareness-only on mobile.
      expect(canReassignWorkOrder(sess(AuthRole.divAdmin, edit)), isFalse);
      expect(canReassignWorkOrder(sess(AuthRole.superAdmin, const ['*'])), isFalse);
      expect(canReassignWorkOrder(sess(AuthRole.depotUser, const [])), isFalse);
      expect(canReassignWorkOrder(sess(AuthRole.maintenanceStaff, edit)), isFalse);
    });

    test('canOperateJobWorksOnMobile: admin/HQ tier is read-only (SSOT 5.1)', () {
      expect(canOperateJobWorksOnMobile(null), isFalse);
      expect(canOperateJobWorksOnMobile(sess(AuthRole.depotIncharge, edit)), isTrue);
      expect(canOperateJobWorksOnMobile(sess(AuthRole.depotUser, edit)), isTrue);
      expect(canOperateJobWorksOnMobile(sess(AuthRole.maintenanceStaff, edit)), isTrue);
      expect(canOperateJobWorksOnMobile(sess(AuthRole.divAdmin, edit)), isFalse);
      expect(canOperateJobWorksOnMobile(sess(AuthRole.zrAdmin, edit)), isFalse);
      expect(canOperateJobWorksOnMobile(sess(AuthRole.superAdmin, const ['*'])), isFalse);
      expect(canOperateJobWorksOnMobile(sess(AuthRole.divHqUser, edit)), isFalse);
      expect(canOperateJobWorksOnMobile(sess(AuthRole.depotIncharge, const [])), isFalse);
      // Role union: an admin who is also a depot incharge keeps field controls.
      const multi = UserSession(
        accessToken: 't',
        username: 'u',
        primaryRole: AuthRole.divAdmin,
        roles: [AuthRole.divAdmin, AuthRole.depotIncharge],
        permissions: edit,
      );
      expect(canOperateJobWorksOnMobile(multi), isTrue);
    });

    test('canManagePreStartMandates', () {
      expect(canManagePreStartMandates(sess(AuthRole.depotIncharge, edit)), isTrue);
      expect(canManagePreStartMandates(sess(AuthRole.zrAdmin, edit)), isFalse);
      expect(canManagePreStartMandates(sess(AuthRole.divAdmin, edit)), isFalse);
      expect(canManagePreStartMandates(sess(AuthRole.depotUser, edit)), isFalse);
      expect(canManagePreStartMandates(null), isFalse);
    });

    test('canUncheckoutGroup', () {
      expect(
          canUncheckoutGroup(
              sess(AuthRole.depotIncharge, const ['maintenance.group_uncheckout'])),
          isTrue);
      expect(canUncheckoutGroup(sess(AuthRole.depotIncharge, edit)), isFalse);
      expect(canUncheckoutGroup(null), isFalse);
    });

    test('canTriageDeficiencySeverity', () {
      expect(canTriageDeficiencySeverity(sess(AuthRole.depotUser, edit)), isTrue);
      expect(canTriageDeficiencySeverity(sess(AuthRole.divAdmin, edit)), isFalse);
      expect(canTriageDeficiencySeverity(null), isFalse);
    });

    test('canFlagRemarkDeficiency', () {
      expect(canFlagRemarkDeficiency(sess(AuthRole.divAdmin, edit)), isTrue);
      expect(canFlagRemarkDeficiency(sess(AuthRole.depotUser, edit)), isTrue);
      expect(canFlagRemarkDeficiency(sess(AuthRole.maintenanceStaff, edit)), isFalse);
      expect(canFlagRemarkDeficiency(sess(AuthRole.depotUser, const [])), isFalse);
    });

    test('canRequestPmApproval', () {
      expect(canRequestPmApproval(sess(AuthRole.depotIncharge, edit)), isTrue);
      expect(canRequestPmApproval(sess(AuthRole.superAdmin, edit)), isFalse);
      expect(canRequestPmApproval(null), isFalse);
    });

    test('canReplaceAssets / canReplaceWholeAsset', () {
      const perms = ['maintenance.view', 'maintenance.edit', 'assets.replace'];
      final staff = sess(AuthRole.maintenanceStaff, perms);
      expect(canReplaceAssets(staff), isTrue);
      expect(canReplaceWholeAsset(staff), isTrue);

      // SUPER_ADMIN holds '*' but is not MAINTENANCE_STAFF: component only.
      final admin = sess(AuthRole.superAdmin, const ['*']);
      expect(canReplaceAssets(admin), isTrue);
      expect(canReplaceWholeAsset(admin), isFalse);

      final depot = sess(AuthRole.depotIncharge, edit);
      expect(canReplaceAssets(depot), isFalse);
      expect(canReplaceWholeAsset(depot), isFalse);

      expect(canReplaceAssets(null), isFalse);
      expect(canReplaceWholeAsset(null), isFalse);
    });

    group('canViewDeficiencyModule', () {
      const assets = ['assets.view'];

      test('MAINTENANCE_STAFF with assets.view is false (hidden from technicians)', () {
        expect(canViewDeficiencyModule(sess(AuthRole.maintenanceStaff, assets)), isFalse);
      });

      test('DEPOT_INCHARGE and DEPOT_USER with assets.view are true', () {
        expect(canViewDeficiencyModule(sess(AuthRole.depotIncharge, assets)), isTrue);
        expect(canViewDeficiencyModule(sess(AuthRole.depotUser, assets)), isTrue);
      });

      test('DIV_ADMIN / ZR_ADMIN / SUPER_ADMIN / DIV_HQ_USER are false', () {
        expect(canViewDeficiencyModule(sess(AuthRole.divAdmin, assets)), isFalse);
        expect(canViewDeficiencyModule(sess(AuthRole.zrAdmin, assets)), isFalse);
        expect(canViewDeficiencyModule(sess(AuthRole.superAdmin, assets)), isFalse);
        expect(canViewDeficiencyModule(sess(AuthRole.superAdmin, const ['*'])), isFalse);
        expect(canViewDeficiencyModule(sess(AuthRole.divHqUser, assets)), isFalse);
      });

      test('depot role without assets.view is false', () {
        expect(
          canViewDeficiencyModule(sess(AuthRole.depotIncharge, const ['maintenance.view'])),
          isFalse,
        );
        expect(canViewDeficiencyModule(sess(AuthRole.depotUser, const [])), isFalse);
      });

      test('DIV_ADMIN + DEPOT_INCHARGE multi-role with assets.view is true (role union)', () {
        const multi = UserSession(
          accessToken: 't',
          username: 'u',
          primaryRole: AuthRole.divAdmin,
          roles: [AuthRole.divAdmin, AuthRole.depotIncharge],
          permissions: assets,
        );
        expect(canViewDeficiencyModule(multi), isTrue);
      });

      test('null session is false (fail closed)', () {
        expect(canViewDeficiencyModule(null), isFalse);
      });
    });
  });
}
