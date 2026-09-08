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
