import 'package:equatable/equatable.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'auth_exceptions.dart';
import 'auth_role.dart';
import 'org_scope.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

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
    this.profilePicture,
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
  final String? profilePicture;

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

  /// True when a refreshed JWT changed identity, roles, permissions, or org
  /// scope. Cached work orders and outbox mutations from the previous context
  /// must not be reused.
  bool authorizationChangedFrom(UserSession previous) {
    if (userId != previous.userId) return true;
    if (depotId != previous.depotId) return true;
    if (primaryRole != previous.primaryRole) return true;
    if (scope != previous.scope) return true;
    final roleCodes = roles.map((r) => r.code).toSet();
    final previousRoleCodes = previous.roles.map((r) => r.code).toSet();
    if (roleCodes.length != previousRoleCodes.length ||
        !roleCodes.containsAll(previousRoleCodes)) {
      return true;
    }
    final permCodes = permissions.toSet();
    final previousPermCodes = previous.permissions.toSet();
    if (permCodes.length != previousPermCodes.length ||
        !permCodes.containsAll(previousPermCodes)) {
      return true;
    }
    return false;
  }

  UserSession copyWith({
    String? accessToken,
    String? username,
    int? userId,
    String? firstName,
    String? lastName,
    AuthRole? primaryRole,
    List<AuthRole>? roles,
    List<String>? permissions,
    int? depotId,
    String? depotName,
    bool? has2FA,
    DateTime? validUntil,
    OrgScope? scope,
    String? profilePicture,
    bool clearProfilePicture = false,
  }) {
    return UserSession(
      accessToken: accessToken ?? this.accessToken,
      username: username ?? this.username,
      userId: userId ?? this.userId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      primaryRole: primaryRole ?? this.primaryRole,
      roles: roles ?? this.roles,
      permissions: permissions ?? this.permissions,
      depotId: depotId ?? this.depotId,
      depotName: depotName ?? this.depotName,
      has2FA: has2FA ?? this.has2FA,
      validUntil: validUntil ?? this.validUntil,
      scope: scope ?? this.scope,
      profilePicture: clearProfilePicture ? null : (profilePicture ?? this.profilePicture),
    );
  }

  /// Construct UserSession by decoding JWT access token claims.
  factory UserSession.fromJwt(String token) {
    try {
      final Map<String, dynamic> claims = JwtDecoder.decode(token);
      final expSeconds = claims['exp'];
      if (expSeconds is num) {
        // Allow a small leeway for device/server clock skew so a token issued
        // moments ago by login()/refreshToken() isn't rejected as already
        // expired just because the device clock runs ahead of the server's.
        const clockSkewLeeway = Duration(seconds: 30);
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(
            (expSeconds * 1000).round(), isUtc: true);
        if (DateTime.now().toUtc().isAfter(expiresAt.add(clockSkewLeeway))) {
          throw const UnauthorizedException('Token is expired');
        }
      }
      return UserSession.fromClaims(claims, token);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw UnauthorizedException('Invalid JWT format or claims: $e');
    }
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
      validUntil = asJsonDateTime(claims['valid_until']);
    }
    if (validUntil != null &&
        DateTime.now().toUtc().isAfter(validUntil.toUtc())) {
      throw const GuestExpiredException();
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

    final profilePicture = claims['profile_picture']?.toString();

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
      profilePicture: profilePicture != null && profilePicture.isNotEmpty ? profilePicture : null,
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
        profilePicture,
      ];
}
