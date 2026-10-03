import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fail-closed permission check. A missing session never grants access.
bool sessionAllows(UserSession? session, String permissionCode) {
  return session?.hasPermission(permissionCode) ?? false;
}

bool sessionAllowsAny(UserSession? session, List<String> permissionCodes) {
  for (final code in permissionCodes) {
    if (sessionAllows(session, code)) return true;
  }
  return false;
}

UserSession? sessionFromAuth(AuthState state) {
  return state is Authenticated ? state.session : null;
}

UserSession? sessionOf(WidgetRef ref) {
  return sessionFromAuth(ref.watch(authControllerProvider));
}

/// PDF/report export gate. The backend enforces `reports.export` as strictly
/// additive to `reports.view`/`maintenance.view` (see
/// `WorkOrderReportViewSet._get_filters` and `MaintenanceRecordViewSet.
/// export_history`, both of which 403 on `reports.export` alone regardless of
/// what read access the caller already has) — so neither of those weaker
/// permissions may ever substitute for it here. Mobile PDFs are generated
/// client-side from already-fetched data, so this is the only checkpoint;
/// there is no server round-trip left to catch a client-side leak.
bool canExportPdf(UserSession? session) {
  return sessionAllows(session, 'reports.export');
}

/// Roles the backend's `WorkOrderPermission.CREATE_ROLES` accepts for the
/// generic work-order create action (`POST /work-orders/`) — see
/// `maintenance/views.py`. Unlike every other work-order permission this one
/// has no `is_super_admin` bypass: `maintenance.create` alone (which
/// SUPER_ADMIN, ZR_ADMIN, DIV_ADMIN and DIV_HQ_USER all hold per the registry)
/// is not enough, so the mobile create flow must not offer it to a role
/// outside this set — it would be a guaranteed 403 on submit.
const _workOrderCreateRoles = {AuthRole.depotIncharge, AuthRole.depotUser};

/// Whether this session may reach the "New Job Work" create flow: the
/// `maintenance.create` permission AND membership of one of the roles the
/// server actually accepts for it (see [_workOrderCreateRoles]).
bool canCreateWorkOrder(UserSession? session) {
  if (session == null) return false;
  if (!sessionAllows(session, 'maintenance.create')) return false;
  return session.roles.any(_workOrderCreateRoles.contains);
}

/// Roles ConversionService accepts for inspection → job-work. `inspections.edit`
/// is held by SUPER_ADMIN/ZR_ADMIN/DIV_ADMIN as well, but those roles are
/// hard-rejected server-side — matching [canCreateWorkOrder].
const _inspectionConvertRoles = {AuthRole.depotIncharge, AuthRole.depotUser};

bool canConvertInspection(UserSession? session) {
  if (session == null) return false;
  if (!sessionAllows(session, 'inspections.edit')) return false;
  return session.roles.any(_inspectionConvertRoles.contains);
}

/// Same `ConversionService._validate_scope` gate as [canConvertInspection] —
/// Complaint and Inspection conversion share one service method, hard-
/// rejecting every role except DEPOT_INCHARGE/DEPOT_USER regardless of who
/// else holds `complaints.edit`.
const _complaintConvertRoles = {AuthRole.depotIncharge, AuthRole.depotUser};

bool canConvertComplaint(UserSession? session) {
  if (session == null) return false;
  if (!sessionAllows(session, 'complaints.edit')) return false;
  return session.roles.any(_complaintConvertRoles.contains);
}

/// Batch complaint/inspection → work-order conversion
/// (`create_from_complaints`/`create_from_inspections`) maps to
/// `maintenance.create` server-side (`WorkOrderViewSet.permission_by_action`)
/// — same permission and same DEPOT_INCHARGE/DEPOT_USER role gate as the
/// plain "New Job Work" create action, so this is deliberately just
/// [canCreateWorkOrder] under another name for callers in the Pending
/// Actions screen, not a separate check.
bool canBatchConvertToWorkOrder(UserSession? session) => canCreateWorkOrder(session);

/// Deficiency → rectification Job Work creation (`create_rectification`)
/// maps to `maintenance.create` server-side with the same in-body
/// DEPOT_INCHARGE/DEPOT_USER converter-role gate as the complaint/inspection
/// batch conversions above — deliberately the same check under a distinct
/// name so the Deficiencies tab reads on its own terms.
bool canCreateRectification(UserSession? session) => canCreateWorkOrder(session);

/// Roles `MaintenanceScheduleViewSet.create_batch_work_orders` accepts —
/// gated server-side on `maintenance.edit` (not `.create`, unlike the other
/// two batch-convert actions above) plus the same in-body DEPOT_INCHARGE/
/// DEPOT_USER role check.
const _scheduleBatchConvertRoles = {AuthRole.depotIncharge, AuthRole.depotUser};

bool canBatchConvertSchedules(UserSession? session) {
  if (session == null) return false;
  if (!sessionAllows(session, 'maintenance.edit')) return false;
  return session.roles.any(_scheduleBatchConvertRoles.contains);
}

/// Record-write policy on `MaintenanceRecordViewSet`: SUPER_ADMIN / DIV_ADMIN /
/// ZR_ADMIN, or assigned MAINTENANCE_STAFF. DEPOT_INCHARGE / DEPOT_USER and
/// HQ users hold `maintenance.edit` but are read-only for checklist records.
const _checklistWriterRoles = {
  AuthRole.superAdmin,
  AuthRole.divAdmin,
  AuthRole.zrAdmin,
  AuthRole.maintenanceStaff,
};

bool canWriteChecklist(UserSession? session) {
  if (session == null) return false;
  if (!sessionAllows(session, 'maintenance.edit')) return false;
  return session.roles.any(_checklistWriterRoles.contains);
}

bool _editWithRoles(UserSession? session, Set<AuthRole> roles) {
  if (session == null) return false;
  if (!sessionAllows(session, 'maintenance.edit')) return false;
  return session.roles.any(roles.contains);
}

/// Reassign technician (`POST .../work-orders/{id}/reassign/`, `views.py:3705`,
/// `workorder_lifecycle_service.py:1061`): `maintenance.edit` plus legacy role
/// ADMIN (SUPER/ZR/DIV admin), DEPOT_INCHARGE or DEPOT_USER.
bool canReassignWorkOrder(UserSession? session) => _editWithRoles(session, {
      AuthRole.superAdmin,
      AuthRole.zrAdmin,
      AuthRole.divAdmin,
      AuthRole.depotIncharge,
      AuthRole.depotUser,
    });

/// Pre-START checklist preparation and supervisor mandates
/// (`prepare-checklist/` `views.py:3049`, `supervisor-mandate/` `views.py:3065`):
/// `maintenance.edit` plus SUPER_ADMIN, ZR_ADMIN, DIV_ADMIN or DEPOT_INCHARGE.
bool canManagePreStartMandates(UserSession? session) =>
    _editWithRoles(session, {
      AuthRole.superAdmin,
      AuthRole.zrAdmin,
      AuthRole.divAdmin,
      AuthRole.depotIncharge,
    });

/// Un-checking a checked-out asset group (`group-inclusion/`, `views.py:2151`)
/// needs `maintenance.group_uncheckout` (DEPOT_INCHARGE; SUPER_ADMIN holds all).
bool canUncheckoutGroup(UserSession? session) =>
    sessionAllows(session, 'maintenance.group_uncheckout');

/// Changing a deficiency's severity (`PATCH /deficiencies/{id}/`,
/// `assets/services/deficiencies.py:20,139`): `maintenance.edit` plus
/// DEPOT_INCHARGE or DEPOT_USER.
bool canTriageDeficiencySeverity(UserSession? session) =>
    _editWithRoles(session, {AuthRole.depotIncharge, AuthRole.depotUser});

/// Flag / un-flag a technician remark as a deficiency
/// (`flag-remark-deficiency/`, `views.py:1797`): `maintenance.edit` plus
/// DEPOT_INCHARGE, DEPOT_USER, DIV_ADMIN or ZR_ADMIN (SUPER_ADMIN included).
bool canFlagRemarkDeficiency(UserSession? session) => _editWithRoles(session, {
      AuthRole.superAdmin,
      AuthRole.zrAdmin,
      AuthRole.divAdmin,
      AuthRole.depotIncharge,
      AuthRole.depotUser,
    });

/// PM skip / checklist-change requests (`schedules/{id}/skip-request/`,
/// `template-change-request/`): `maintenance.edit` plus DEPOT_INCHARGE or
/// DEPOT_USER (superuser is refused server-side).
bool canRequestPmApproval(UserSession? session) =>
    _editWithRoles(session, {AuthRole.depotIncharge, AuthRole.depotUser});

/// Web MaintenanceRecordForm `auth.can('assets.replace')` - gates both buttons.
/// Held by SUPER_ADMIN and MAINTENANCE_STAFF only (rbac/registry.py).
bool canReplaceAssets(UserSession? s) => sessionAllows(s, 'assets.replace');

/// replace_asset additionally requires the MAINTENANCE_STAFF role (assets/views.py:2277).
bool canReplaceWholeAsset(UserSession? s) =>
    canReplaceAssets(s) && (s?.roles.contains(AuthRole.maintenanceStaff) ?? false);
