import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';

void main() {
  group('UserSession and AuthRole', () {
    const canonicalRoles = [
      ('SUPER_ADMIN', AuthRole.superAdmin),
      ('ZR_ADMIN', AuthRole.zrAdmin),
      ('ZR_HQ_USER', AuthRole.zrHqUser),
      ('DIV_ADMIN', AuthRole.divAdmin),
      ('DIV_HQ_USER', AuthRole.divHqUser),
      ('DEPOT_INCHARGE', AuthRole.depotIncharge),
      ('DEPOT_USER', AuthRole.depotUser),
      ('MAINTENANCE_STAFF', AuthRole.maintenanceStaff),
      ('CONTROL_CELL', AuthRole.controlCell),
      ('EB_BILL_CLERK', AuthRole.ebBillClerk),
      ('GUEST', AuthRole.guest),
    ];

    for (final (roleStr, expectedEnum) in canonicalRoles) {
      test('decodes canonical role $roleStr correctly', () {
        final claims = {
          'username': 'test_user',
          'role': roleStr,
          'roles': [roleStr],
          'permissions': ['maintenance.view'],
        };

        final session = UserSession.fromClaims(claims, 'dummy_token');
        expect(session.primaryRole, expectedEnum);
        expect(session.roles, contains(expectedEnum));
      });
    }

    test('normalizes legacy aliases and variant spellings properly', () {
      expect(AuthRole.fromString('ADMIN'), AuthRole.divAdmin);
      expect(AuthRole.fromString('HQ_USER'), AuthRole.divHqUser);
      expect(AuthRole.fromString('CONTROLL_CELL'), AuthRole.controlCell);
      expect(AuthRole.fromString('CONTROLLER'), AuthRole.controlCell);
      expect(AuthRole.fromString('CONTROL CELL'), AuthRole.controlCell);
      expect(AuthRole.fromString('VIEWER'), AuthRole.viewer);
    });

    test('unknown role strings map to AuthRole.unknown and never default to GUEST', () {
      expect(AuthRole.fromString('SOME_FUTURE_ROLE'), AuthRole.unknown);
      expect(AuthRole.fromString(null), AuthRole.unknown);
      expect(AuthRole.fromString(''), AuthRole.unknown);
    });

    test('resolves primary role by priority when role claim is missing', () {
      // In JWT, roles is alphabetically sorted: ['DIV_ADMIN', 'GUEST']
      final claims = {
        'username': 'multi_role_user',
        'roles': const ['GUEST', 'DIV_ADMIN'], // GUEST is priority 10, DIV_ADMIN is 70
        'permissions': const ['maintenance.view'],
      };

      final session = UserSession.fromClaims(claims, 'dummy_token');
      expect(session.primaryRole, AuthRole.divAdmin);
    });

    const scopeLevels = [
      ('GLOBAL', OrgScopeLevel.global),
      ('ZONE', OrgScopeLevel.zone),
      ('DIVISION', OrgScopeLevel.division),
      ('DEPOT', OrgScopeLevel.depot),
      ('SELF', OrgScopeLevel.self),
    ];

    for (final (scopeStr, expectedLevel) in scopeLevels) {
      test('decodes scope level $scopeStr correctly', () {
        final claims = {
          'username': 'scoped_user',
          'role': 'DEPOT_USER',
          'roles': const ['DEPOT_USER'],
          'scope': {
            'level': scopeStr,
            'depot': const {'id': 101, 'code': 'VRI', 'name': 'Vriddhachalam'},
          },
        };

        final session = UserSession.fromClaims(claims, 'dummy_token');
        expect(session.scope.level, expectedLevel);
        expect(session.scope.depot?.name, 'Vriddhachalam');
      });
    }

    test('SUPER_ADMIN without wildcard in permissions does NOT receive module access', () {
      // A SUPER_ADMIN with empty permissions must NOT bypass permission checks
      final restrictedSuperAdmin = UserSession.fromClaims(const {
        'username': 'admin_no_perms',
        'role': 'SUPER_ADMIN',
        'roles': ['SUPER_ADMIN'],
        'permissions': <String>[],
      }, 'token');

      expect(restrictedSuperAdmin.isSuperAdmin, isTrue);
      expect(restrictedSuperAdmin.hasPermission('maintenance.view'), isFalse);
    });

    test('evaluates wildcard * permission correctly for any role holding it', () {
      final wildcardSession = UserSession.fromClaims(const {
        'username': 'wildcard_user',
        'role': 'SUPER_ADMIN',
        'roles': ['SUPER_ADMIN'],
        'permissions': ['*'],
      }, 'token');

      expect(wildcardSession.hasPermission('anything.anywhere'), isTrue);
      expect(wildcardSession.isSuperAdmin, isTrue);

      final maintenanceSession = UserSession.fromClaims(const {
        'username': 'tech_1',
        'role': 'MAINTENANCE_STAFF',
        'roles': ['MAINTENANCE_STAFF'],
        'permissions': ['maintenance.view', 'maintenance.edit'],
      }, 'token');

      expect(maintenanceSession.hasPermission('maintenance.view'), isTrue);
      expect(maintenanceSession.hasPermission('maintenance.edit'), isTrue);
      expect(maintenanceSession.hasPermission('users.create'), isFalse);
    });

    test('authorizationChangedFrom detects permission and scope changes', () {
      const original = UserSession(
        accessToken: 't',
        username: 'u',
        userId: 1,
        depotId: 10,
        primaryRole: AuthRole.depotUser,
        roles: [AuthRole.depotUser],
        permissions: ['maintenance.view'],
        scope: OrgScope(level: OrgScopeLevel.depot),
      );
      const sameAuth = UserSession(
        accessToken: 'other-token',
        username: 'u',
        userId: 1,
        depotId: 10,
        primaryRole: AuthRole.depotUser,
        roles: [AuthRole.depotUser],
        permissions: ['maintenance.view'],
        scope: OrgScope(level: OrgScopeLevel.depot),
      );
      const narrowerPerms = UserSession(
        accessToken: 't2',
        username: 'u',
        userId: 1,
        depotId: 10,
        primaryRole: AuthRole.depotUser,
        roles: [AuthRole.depotUser],
        permissions: ['dashboard.view'],
        scope: OrgScope(level: OrgScopeLevel.depot),
      );
      const movedDepot = UserSession(
        accessToken: 't3',
        username: 'u',
        userId: 1,
        depotId: 99,
        primaryRole: AuthRole.depotUser,
        roles: [AuthRole.depotUser],
        permissions: ['maintenance.view'],
        scope: OrgScope(
          level: OrgScopeLevel.depot,
          depot: OrgUnitInfo(id: 99, name: 'Other'),
        ),
      );

      expect(sameAuth.authorizationChangedFrom(original), isFalse);
      expect(narrowerPerms.authorizationChangedFrom(original), isTrue);
      expect(movedDepot.authorizationChangedFrom(original), isTrue);
    });

    test('expired valid_until throws GuestExpiredException', () {
      expect(
        () => UserSession.fromClaims(const {
          'username': 'guest',
          'role': 'GUEST',
          'roles': ['GUEST'],
          'permissions': ['dashboard.view'],
          'valid_until': '2000-01-01T00:00:00Z',
        }, 'token'),
        throwsA(isA<GuestExpiredException>()),
      );
    });
  });
}
