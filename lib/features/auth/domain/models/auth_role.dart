/// Canonical roles and recognized legacy roles in GSSMS RBAC registry with priority ordering.
enum AuthRole {
  superAdmin('SUPER_ADMIN', 'Super Admin', 100),
  zrAdmin('ZR_ADMIN', 'Zone Admin', 90),
  zrHqUser('ZR_HQ_USER', 'Zone HQ User', 80),
  divAdmin('DIV_ADMIN', 'Division Admin', 70),
  divHqUser('DIV_HQ_USER', 'Division HQ User', 60),
  depotIncharge('DEPOT_INCHARGE', 'Depot Incharge', 50),
  depotUser('DEPOT_USER', 'Depot User', 40),
  maintenanceStaff('MAINTENANCE_STAFF', 'Maintenance Staff', 30),
  controlCell('CONTROL_CELL', 'Control Cell', 30),
  ebBillClerk('EB_BILL_CLERK', 'EB Bill Clerk', 30),
  guest('GUEST', 'Guest / Demo', 10),
  viewer('VIEWER', 'Viewer (Legacy)', 5),
  unknown('UNKNOWN', 'Unknown Role', 0);

  const AuthRole(this.code, this.displayName, this.priority);

  final String code;
  final String displayName;
  final int priority;

  /// Parse and normalize string to canonical AuthRole.
  /// Handles legacy aliases according to backend rbac/registry.py & rbac/roles.py:
  /// - ADMIN -> DIV_ADMIN
  /// - HQ_USER -> DIV_HQ_USER
  /// - CONTROLL_CELL / CONTROLLER / CONTROL CELL / CONTROL-CELL -> CONTROL_CELL
  /// - VIEWER -> VIEWER (distinct legacy global view role)
  /// Unknown or null values resolve to AuthRole.unknown (never defaulting to GUEST).
  static AuthRole fromString(String? roleStr) {
    if (roleStr == null || roleStr.trim().isEmpty) {
      return AuthRole.unknown;
    }
    final normalized = roleStr.trim().toUpperCase();
    switch (normalized) {
      case 'SUPER_ADMIN':
        return AuthRole.superAdmin;
      case 'ZR_ADMIN':
        return AuthRole.zrAdmin;
      case 'ZR_HQ_USER':
        return AuthRole.zrHqUser;
      case 'DIV_ADMIN':
      case 'ADMIN': // Legacy alias
        return AuthRole.divAdmin;
      case 'DIV_HQ_USER':
      case 'HQ_USER': // Legacy alias
        return AuthRole.divHqUser;
      case 'DEPOT_INCHARGE':
        return AuthRole.depotIncharge;
      case 'DEPOT_USER':
        return AuthRole.depotUser;
      case 'MAINTENANCE_STAFF':
        return AuthRole.maintenanceStaff;
      case 'CONTROL_CELL':
      case 'CONTROLL_CELL':
      case 'CONTROLLER':
      case 'CONTROL CELL':
      case 'CONTROL-CELL':
        return AuthRole.controlCell;
      case 'EB_BILL_CLERK':
        return AuthRole.ebBillClerk;
      case 'GUEST':
        return AuthRole.guest;
      case 'VIEWER':
        return AuthRole.viewer;
      default:
        return AuthRole.unknown;
    }
  }
}
