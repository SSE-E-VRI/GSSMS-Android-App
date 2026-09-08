import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';

class FakeAuthenticatedController extends AuthController {
  FakeAuthenticatedController(this._session);

  final UserSession _session;

  @override
  AuthState build() => Authenticated(_session);
}

UserSession fakeSession({
  AuthRole role = AuthRole.depotIncharge,
  List<String> permissions = const ['maintenance.view', 'maintenance.edit'],
  OrgScope scope = const OrgScope(level: OrgScopeLevel.depot),
}) {
  return UserSession(
    accessToken: 'test_token',
    username: 'test_user',
    firstName: 'Test',
    lastName: 'User',
    primaryRole: role,
    roles: [role],
    permissions: permissions,
    scope: scope,
  );
}
