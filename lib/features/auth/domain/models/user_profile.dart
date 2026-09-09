import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Editable profile fields from `GET/PATCH /api/v1/users/{id}/`.
class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.username,
    this.role = '',
    this.email = '',
    this.phoneNumber = '',
    this.designation = '',
    this.profilePicture,
  });

  final int id;
  final String username;
  final String role;
  final String email;
  final String phoneNumber;
  final String designation;
  final String? profilePicture;

  UserProfile copyWith({
    int? id,
    String? username,
    String? role,
    String? email,
    String? phoneNumber,
    String? designation,
    String? profilePicture,
    bool clearProfilePicture = false,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      role: role ?? this.role,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      designation: designation ?? this.designation,
      profilePicture: clearProfilePicture ? null : (profilePicture ?? this.profilePicture),
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: asJsonInt(json['id']) ?? 0,
      username: asJsonString(json['username']) ?? '',
      role: asJsonString(json['role']) ?? '',
      email: asJsonString(json['email']) ?? '',
      phoneNumber: asJsonString(json['phone_number']) ?? '',
      designation: asJsonString(json['designation']) ?? '',
      profilePicture: asJsonString(json['profile_picture']),
    );
  }

  @override
  List<Object?> get props => [id, username, role, email, phoneNumber, designation, profilePicture];
}
