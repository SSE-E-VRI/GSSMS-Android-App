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
