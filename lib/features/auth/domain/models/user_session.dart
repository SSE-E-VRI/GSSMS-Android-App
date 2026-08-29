import 'package:equatable/equatable.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'auth_role.dart';
import 'org_scope.dart';

/// Immutable authenticated user session reconstructed from server-issued JWT claims.
class UserSession extends Equatable {
  const UserSession({
    required this.accessToken,
    required this.username,
    this.userId,
    this.firstName,
    this.lastName,
    required this.primaryRole,
    this.roles = const [],
    this.permissions = const [],
    this.depotId,
    this.depotName,
    this.has2FA = false,
    this.validUntil,
    this.scope = const OrgScope(),
  });

  final String accessToken;
  final String username;
  final int? userId;
  final String? firstName;
  final String? lastName;
  final AuthRole primaryRole;
  final List<AuthRole> roles;
  final List<String> permissions;
  final int? depotId;
  final String? depotName;
  final bool has2FA;
  final DateTime? validUntil;
  final OrgScope scope;

  String get displayName {
    final name = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return name.isNotEmpty ? name : username;
  }

  /// Check if the user has permission to perform an action.
  /// Wildcard '*' grants access to all modules/actions.
  /// Strict rule: permissions are governed exclusively by server-issued claims, not client-side role shortcuts.
  bool hasPermission(String permissionCode) {
    if (permissions.contains('*')) return true;
    return permissions.contains(permissionCode);
  }

  /// Display helper for Super Admin identity badge
  bool get isSuperAdmin => primaryRole == AuthRole.superAdmin;

  /// Construct UserSession by decoding JWT access token claims.
  factory UserSession.fromJwt(String token) {
    final Map<String, dynamic> claims = JwtDecoder.decode(token);
    return UserSession.fromClaims(claims, token);
  }

  /// Construct UserSession from pre-decoded claims map.
  factory UserSession.fromClaims(Map<String, dynamic> claims, String token) {
    // Parse roles array
    final rawRoles = claims['roles'];
    final List<AuthRole> parsedRoles = [];
    if (rawRoles is List) {
      for (final r in rawRoles) {
        final parsed = AuthRole.fromString(r?.toString());
        if (parsed != AuthRole.unknown) {
          parsedRoles.add(parsed);
        }
      }
    }

    // Determine primary role:
    // 1. Prefer explicitly provided 'role' claim if valid.
    // 2. Otherwise resolve the highest priority role among assigned roles.
    AuthRole primary = AuthRole.fromString(claims['role']?.toString());
    if (primary == AuthRole.unknown && parsedRoles.isNotEmpty) {
      // Sort descending by priority to find highest priority role
      final sortedRoles = List<AuthRole>.from(parsedRoles)
        ..sort((a, b) => b.priority.compareTo(a.priority));
      primary = sortedRoles.first;
    } else if (primary != AuthRole.unknown && !parsedRoles.contains(primary)) {
      parsedRoles.add(primary);
    } else if (primary == AuthRole.unknown && parsedRoles.isEmpty) {
      primary = AuthRole.unknown;
    }

    // Parse permissions array
    final rawPerms = claims['permissions'];
    final List<String> parsedPerms = [];
    if (rawPerms is List) {
      for (final p in rawPerms) {
        if (p != null) parsedPerms.add(p.toString());
      }
    }

    // Parse validUntil
    DateTime? validUntil;
    if (claims['valid_until'] != null) {
      validUntil = DateTime.tryParse(claims['valid_until'].toString());
    }

    // Parse scope
    final rawScope = claims['scope'];
    final OrgScope scope = rawScope is Map<String, dynamic>
        ? OrgScope.fromJson(rawScope)
        : const OrgScope();

    final userIdRaw = claims['user_id'] ?? claims['id'];
    final int? userId = userIdRaw is int ? userIdRaw : int.tryParse('$userIdRaw');

    final depotIdRaw = claims['depot_id'];
    final int? depotId = depotIdRaw is int ? depotIdRaw : int.tryParse('$depotIdRaw');

    return UserSession(
      accessToken: token,
      username: claims['username']?.toString() ?? '',
      userId: userId,
      firstName: claims['first_name']?.toString(),
      lastName: claims['last_name']?.toString(),
      primaryRole: primary,
      roles: parsedRoles,
      permissions: parsedPerms,
      depotId: depotId,
      depotName: claims['depot_name']?.toString(),
      has2FA: claims['has_2fa'] == true,
      validUntil: validUntil,
      scope: scope,
    );
  }

  @override
  List<Object?> get props => [
        accessToken,
        username,
        userId,
        firstName,
        lastName,
        primaryRole,
        roles,
        permissions,
        depotId,
        depotName,
        has2FA,
        validUntil,
        scope,
      ];
}
